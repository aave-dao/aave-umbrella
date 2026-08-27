// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AggregatorInterface} from 'aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol';

import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {MathUtils} from 'aave-v4/libraries/math/MathUtils.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';
import {WadRayMath} from 'aave-v4/libraries/math/WadRayMath.sol';

import {EnumerableMap} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol';
import {EnumerableSet} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import {IUmbrellaConfigurationBase} from './interfaces/IUmbrellaConfigurationBase.sol';
import {IUmbrellaConfigurationV4} from './interfaces/IUmbrellaConfigurationV4.sol';

import {UmbrellaBase} from './UmbrellaBase.sol';

/**
 * @title UmbrellaConfigurationV4
 * @notice This abstract contract provides base configuration for covering `spoke`s of an Aave V4 `Hub`,
 * including setting `UmbrellaStakeToken`s, `liquidationFee`s, `underlyingOracle`s for pricing, and tracking deficit.
 * @dev Deficit is tracked per `spoke`, while slashing configurations are shared by every `spoke` covered by a
 * `hub` and `assetId` pair. A single instance can cover several `Hub`s.
 * @author BGD labs
 */
abstract contract UmbrellaConfigurationV4 is UmbrellaBase, IUmbrellaConfigurationV4 {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeCast for uint256;
  using WadRayMath for uint256;
  using {MathUtils.zeroFloorSub} for uint256;

  bytes32 public constant SPOKE_COVERAGE_MANAGER_ROLE = keccak256('SPOKE_COVERAGE_MANAGER_ROLE');

  /// @custom:storage-location erc7201:umbrella.storage.UmbrellaConfigurationV4
  struct UmbrellaConfigurationV4Storage {
    /// @notice Map of `hub` and `assetId` pairs and their data
    mapping(address hub => mapping(uint256 assetId => AssetData)) assetsData;
    /// @notice Map of stake addresses and their data
    mapping(address umbrellaStake => StakeTokenData) stakesData;
    /// @notice Address that is receiving the slashed funds
    address slashedFundsRecipient;
  }

  // keccak256(abi.encode(uint256(keccak256("umbrella.storage.UmbrellaConfigurationV4")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant UmbrellaConfigurationV4StorageLocation =
    0x79ae8116f23f55540731e4e4a7167ee397486dbd01fb916cafa204d8e498b900;

  function _getUmbrellaConfigurationV4Storage()
    private
    pure
    returns (UmbrellaConfigurationV4Storage storage $)
  {
    assembly {
      $.slot := UmbrellaConfigurationV4StorageLocation
    }
  }

  function __UmbrellaConfigurationV4_init(
    address superAdmin,
    address slashedFundsRecipient
  ) internal onlyInitializing {
    require(slashedFundsRecipient != address(0), ZeroAddress());

    _grantRole(SPOKE_COVERAGE_MANAGER_ROLE, superAdmin);

    _getUmbrellaConfigurationV4Storage().slashedFundsRecipient = slashedFundsRecipient;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function updateSlashingConfigs(
    SlashingConfigUpdate[] calldata slashingConfigs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i; i < slashingConfigs.length; ++i) {
      _updateSlashingConfig(slashingConfigs[i]);
    }
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function removeSlashingConfigs(
    SlashingConfigRemoval[] calldata removalPairs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    UmbrellaConfigurationV4Storage storage $ = _getUmbrellaConfigurationV4Storage();

    for (uint256 i; i < removalPairs.length; ++i) {
      AssetData storage assetData = $.assetsData[removalPairs[i].hub][removalPairs[i].assetId];

      bool configRemoved = assetData.configurationMap.remove(removalPairs[i].umbrellaStake);
      if (configRemoved) {
        // The `deficitOffset` of a `spoke` is initialized when it is added to the coverage of a configured
        // pair, so the last configuration of a pair stays until every `spoke` is removed from its coverage
        require(
          assetData.configurationMap.length() != 0 || _getCoveredSpokes(assetData).length == 0,
          SpokesStillCovered()
        );

        // `StakeTokenData` is only flagged as deactivated, so that `underlyingOracle` remains readable
        // and function `latestAnswer` inside `UmbrellaStakeToken` stays workable after config removal
        // This oracle should not be the only source of price and should not be used after removing the config, however, for the full functionality of `UmbrellaStakeToken`, we will leave it
        $.stakesData[removalPairs[i].umbrellaStake].deactivated = true;

        emit SlashingConfigurationRemoved(
          removalPairs[i].hub,
          removalPairs[i].assetId,
          removalPairs[i].umbrellaStake
        );
      }
    }
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function addCoveredSpokes(
    SpokeCoverage[] calldata spokes
  ) external onlyRole(SPOKE_COVERAGE_MANAGER_ROLE) {
    for (uint256 i; i < spokes.length; ++i) {
      _addCoveredSpoke(spokes[i]);
    }
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function removeCoveredSpokes(
    SpokeCoverage[] calldata spokes
  ) external onlyRole(SPOKE_COVERAGE_MANAGER_ROLE) {
    UmbrellaConfigurationV4Storage storage $ = _getUmbrellaConfigurationV4Storage();

    for (uint256 i; i < spokes.length; ++i) {
      AssetData storage assetData = $.assetsData[spokes[i].hub][spokes[i].assetId];
      SpokeData storage spokeData = assetData.spokesData[spokes[i].spoke];

      // `deficitOffset` and `pendingDeficit` of the `spoke` are kept, so that a re-addition of the same
      // `spoke` takes the funds already slashed for it into account
      if (assetData.listedSpokes.contains(spokes[i].spoke) && !spokeData.deactivated) {
        spokeData.deactivated = true;

        emit SpokeCoverageRemoved(spokes[i].hub, spokes[i].assetId, spokes[i].spoke);
      }
    }
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getAssetSlashingConfig(
    address hub,
    uint256 assetId,
    address umbrellaStake
  ) external view returns (SlashingConfig memory) {
    UmbrellaConfigurationV4Storage storage $ = _getUmbrellaConfigurationV4Storage();
    (bool exist, uint256 value) = $.assetsData[hub][assetId].configurationMap.tryGet(umbrellaStake);
    require(exist, ConfigurationDoesNotExist());

    return
      SlashingConfig({
        umbrellaStake: umbrellaStake,
        umbrellaStakeUnderlyingOracle: $.stakesData[umbrellaStake].underlyingOracle,
        liquidationFee: value
      });
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getCoveredSpokes(address hub, uint256 assetId) external view returns (address[] memory) {
    return _getCoveredSpokes(_getUmbrellaConfigurationV4Storage().assetsData[hub][assetId]);
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getTotalDeficitOffset(address hub, uint256 assetId) external view returns (uint256) {
    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId];
    address[] memory coveredSpokes = _getCoveredSpokes(assetData);
    uint256 totalDeficitOffset;

    for (uint256 i; i < coveredSpokes.length; ++i) {
      totalDeficitOffset += assetData.spokesData[coveredSpokes[i]].deficitOffset;
    }

    return totalDeficitOffset;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getTotalPendingDeficit(address hub, uint256 assetId) external view returns (uint256) {
    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId];
    address[] memory coveredSpokes = _getCoveredSpokes(assetData);
    uint256 totalPendingDeficit;

    for (uint256 i; i < coveredSpokes.length; ++i) {
      totalPendingDeficit += assetData.spokesData[coveredSpokes[i]].pendingDeficit;
    }

    return totalPendingDeficit;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getTotalSlashableDeficit(address hub, uint256 assetId) external view returns (uint256) {
    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId];
    if (assetData.configurationMap.length() != 1) {
      return 0;
    }

    address[] memory coveredSpokes = _getCoveredSpokes(assetData);
    uint256 totalSlashableDeficit;

    for (uint256 i; i < coveredSpokes.length; ++i) {
      totalSlashableDeficit += _getSlashableSpokeDeficit(
        assetData.spokesData[coveredSpokes[i]],
        hub,
        assetId,
        coveredSpokes[i]
      );
    }

    return totalSlashableDeficit;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getStakeTokenData(address umbrellaStake) external view returns (StakeTokenData memory) {
    return _getUmbrellaConfigurationV4Storage().stakesData[umbrellaStake];
  }

  /// @inheritdoc IUmbrellaConfigurationBase
  function latestUnderlyingAnswer(address umbrellaStake) external view returns (int256) {
    address underlyingOracle = _getUmbrellaConfigurationV4Storage()
      .stakesData[umbrellaStake]
      .underlyingOracle;
    require(underlyingOracle != address(0), ConfigurationHasNotBeenSet());

    return AggregatorInterface(underlyingOracle).latestAnswer();
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getAssetSlashingConfigs(
    address hub,
    uint256 assetId
  ) public view returns (SlashingConfig[] memory) {
    UmbrellaConfigurationV4Storage storage $ = _getUmbrellaConfigurationV4Storage();
    EnumerableMap.AddressToUintMap storage map = $.assetsData[hub][assetId].configurationMap;
    SlashingConfig[] memory configs = new SlashingConfig[](map.length());

    for (uint256 i; i < configs.length; ++i) {
      (address umbrellaStake, uint256 config) = map.at(i);

      configs[i] = SlashingConfig({
        umbrellaStake: umbrellaStake,
        umbrellaStakeUnderlyingOracle: $.stakesData[umbrellaStake].underlyingOracle,
        liquidationFee: config
      });
    }

    return configs;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function isSpokeCovered(address hub, uint256 assetId, address spoke) public view returns (bool) {
    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId];

    return assetData.listedSpokes.contains(spoke) && !assetData.spokesData[spoke].deactivated;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function isSpokeSlashable(
    address hub,
    uint256 assetId,
    address spoke
  ) public view returns (bool, uint256) {
    if (!isSpokeCovered(hub, assetId, spoke)) {
      return (false, 0);
    }

    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId];
    uint256 newDeficit = _getSlashableSpokeDeficit(
      assetData.spokesData[spoke],
      hub,
      assetId,
      spoke
    );

    if (assetData.configurationMap.length() == 1 && newDeficit > 0) {
      return (true, newDeficit);
    }

    return (false, newDeficit);
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke
  ) public view returns (uint256) {
    return
      _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId].spokesData[spoke].deficitOffset;
  }

  /// @inheritdoc IUmbrellaConfigurationV4
  function getPendingDeficit(
    address hub,
    uint256 assetId,
    address spoke
  ) public view returns (uint256) {
    return
      _getUmbrellaConfigurationV4Storage()
      .assetsData[hub][assetId].spokesData[spoke].pendingDeficit;
  }

  /// @inheritdoc IUmbrellaConfigurationBase
  function SLASHED_FUNDS_RECIPIENT() public view returns (address) {
    return _getUmbrellaConfigurationV4Storage().slashedFundsRecipient;
  }

  function _getAssetSlashingConfigsCount(
    address hub,
    uint256 assetId
  ) internal view returns (uint256) {
    return _getUmbrellaConfigurationV4Storage().assetsData[hub][assetId].configurationMap.length();
  }

  function _getAssetOracle(address umbrellaStake) internal view returns (address) {
    return _getUmbrellaConfigurationV4Storage().stakesData[umbrellaStake].assetOracle;
  }

  function _updateSlashingConfig(SlashingConfigUpdate calldata slashConfig) internal {
    require(
      slashConfig.hub != address(0) &&
        slashConfig.umbrellaStake != address(0) &&
        slashConfig.assetOracle != address(0) &&
        slashConfig.umbrellaStakeUnderlyingOracle != address(0),
      ZeroAddress()
    );

    require(
      slashConfig.liquidationFee <= PercentageMath.PERCENTAGE_FACTOR,
      InvalidLiquidationFee()
    );
    require(_isUmbrellaStkToken(slashConfig.umbrellaStake), InvalidStakeToken());

    // one-time safety checks
    (address underlying, ) = IHub(slashConfig.hub).getAssetUnderlyingAndDecimals(
      slashConfig.assetId
    );
    require(underlying != address(0), InvalidAsset());

    require(
      AggregatorInterface(slashConfig.assetOracle).latestAnswer() > 0 &&
        AggregatorInterface(slashConfig.umbrellaStakeUnderlyingOracle).latestAnswer() > 0,
      InvalidOraclePrice()
    );
    require(
      AggregatorInterface(slashConfig.assetOracle).decimals() ==
        AggregatorInterface(slashConfig.umbrellaStakeUnderlyingOracle).decimals(),
      OracleDecimalsMismatch()
    );

    UmbrellaConfigurationV4Storage storage $ = _getUmbrellaConfigurationV4Storage();

    // Using the same `UmbrellaStakeToken` for several different `hub` and `assetId` pairs is prohibited
    // Cause of this we check the `hub` address of the current pair:
    // If it's empty, then this stake has never been configured
    // If `slashConfig.hub` and `slashConfig.assetId` match the current pair, then we are trying to update `slashingConfig`
    // `revert` otherwise
    StakeTokenData storage stakeData = $.stakesData[slashConfig.umbrellaStake];
    require(
      stakeData.hub == address(0) ||
        (stakeData.hub == slashConfig.hub && stakeData.assetId == slashConfig.assetId),
      UmbrellaStakeAlreadySetForAnotherAsset()
    );

    // Unlike the V3 version, the `deficitOffset` is not initialized here, cause it is tracked per `spoke`
    // and is already initialized whenever a `spoke` is added to the coverage of this pair
    $.assetsData[slashConfig.hub][slashConfig.assetId].configurationMap.set(
      slashConfig.umbrellaStake,
      slashConfig.liquidationFee
    );
    $.stakesData[slashConfig.umbrellaStake] = StakeTokenData({
      underlyingOracle: slashConfig.umbrellaStakeUnderlyingOracle,
      deactivated: false,
      assetOracle: slashConfig.assetOracle,
      hub: slashConfig.hub,
      assetId: slashConfig.assetId.toUint96()
    });

    emit SlashingConfigurationChanged(
      slashConfig.hub,
      slashConfig.assetId,
      slashConfig.umbrellaStake,
      slashConfig.liquidationFee,
      slashConfig.assetOracle,
      slashConfig.umbrellaStakeUnderlyingOracle
    );
  }

  function _addCoveredSpoke(SpokeCoverage calldata coverage) internal {
    require(IHub(coverage.hub).isSpokeListed(coverage.assetId, coverage.spoke), InvalidSpoke());
    // A deficit is eliminated through `Hub.add()` and `Hub.eliminateDeficit()`, so this contract must be
    // a `spoke` of the pair itself, otherwise a slashed deficit could never be eliminated
    require(
      IHub(coverage.hub).isSpokeListed(coverage.assetId, address(this)),
      UmbrellaNotListedOnHub()
    );

    AssetData storage assetData = _getUmbrellaConfigurationV4Storage().assetsData[coverage.hub][
      coverage.assetId
    ];

    // Coverage initializes the `deficitOffset` below, so it can only be added to a configured pair. Otherwise
    // the deficit reported while the pair had no `SlashingConfig` would become slashable as soon as the
    // first one is installed.
    require(assetData.configurationMap.length() != 0, AssetCoverageNotSetup());

    SpokeData storage spokeData = assetData.spokesData[coverage.spoke];

    if (assetData.listedSpokes.add(coverage.spoke) || spokeData.deactivated) {
      delete spokeData.deactivated;

      // The deficit already reported by the `spoke` becomes its `deficitOffset`, as otherwise an immediate slashing could be triggered.
      // If `pendingDeficit` is not zero for some reason, e.g. the `spoke` is covered again without previous full coverage of its `pendingDeficit`,
      // then we need to take this value into account to set the new `deficitOffset` here.
      uint256 spokeDeficit = _getSpokeDeficit(coverage.hub, coverage.assetId, coverage.spoke);

      _setDeficitOffset(
        coverage.hub,
        coverage.assetId,
        coverage.spoke,
        spokeDeficit.zeroFloorSub(spokeData.pendingDeficit)
      );

      emit SpokeCoverageAdded(coverage.hub, coverage.assetId, coverage.spoke);
    }
  }

  function _setDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 newSpokeDeficit
  ) internal {
    _getUmbrellaConfigurationV4Storage()
    .assetsData[hub][assetId].spokesData[spoke].deficitOffset = newSpokeDeficit;

    emit DeficitOffsetChanged(hub, assetId, spoke, newSpokeDeficit);
  }

  function _setPendingDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 newSpokeDeficit
  ) internal {
    _getUmbrellaConfigurationV4Storage()
    .assetsData[hub][assetId].spokesData[spoke].pendingDeficit = newSpokeDeficit;

    emit PendingDeficitChanged(hub, assetId, spoke, newSpokeDeficit);
  }

  /// @dev Returns the deficit reported by the `spoke` to the `hub`, expressed in asset units and rounded up,
  /// i.e. the same way the `Hub` itself converts it whenever the deficit is eliminated
  function _getSpokeDeficit(
    address hub,
    uint256 assetId,
    address spoke
  ) internal view returns (uint256) {
    return IHub(hub).getSpokeDeficitRay(assetId, spoke).fromRayUp();
  }

  /// @dev Returns the part of the `spoke` deficit that is neither excluded from coverage by its `deficitOffset`
  /// nor already slashed for through its `pendingDeficit`
  function _getSlashableSpokeDeficit(
    SpokeData storage spokeData,
    address hub,
    uint256 assetId,
    address spoke
  ) private view returns (uint256) {
    return
      _getSpokeDeficit(hub, assetId, spoke).zeroFloorSub(
        spokeData.deficitOffset + spokeData.pendingDeficit
      );
  }

  function _getCoveredSpokes(AssetData storage assetData) private view returns (address[] memory) {
    address[] memory spokes = assetData.listedSpokes.values();
    uint256 coveredNumber;

    for (uint256 i; i < spokes.length; ++i) {
      if (!assetData.spokesData[spokes[i]].deactivated) {
        spokes[coveredNumber++] = spokes[i];
      }
    }

    // shrink the array to the `spoke`s that are still covered, the deactivated ones are moved past its end
    assembly {
      mstore(spokes, coveredNumber)
    }

    return spokes;
  }
}
