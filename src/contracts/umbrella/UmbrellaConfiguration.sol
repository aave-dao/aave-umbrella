// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';
import {AggregatorInterface} from 'aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol';

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import {EnumerableMap} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol';

import {IUmbrellaConfigurationBase} from './interfaces/IUmbrellaConfigurationBase.sol';
import {IUmbrellaConfiguration} from './interfaces/IUmbrellaConfiguration.sol';

import {UmbrellaBase} from './UmbrellaBase.sol';

/**
 * @title UmbrellaConfiguration
 * @notice This abstract contract provides base configuration for covering `reserve`s of an Aave V3 `Pool`,
 * including setting `UmbrellaStakeToken`s, `liquidationFee`s, `underlyingOracle`s for pricing, and tracking deficit.
 * @author BGD labs
 */
abstract contract UmbrellaConfiguration is UmbrellaBase, IUmbrellaConfiguration {
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  uint256 internal constant ONE_HUNDRED_PERCENT = 1e4;

  struct ReserveData {
    /// @notice Map with `UmbrellaStakeToken`s for this reserve and their `liquidationFee`
    EnumerableMap.AddressToUintMap configurationMap;
    /// @notice Initial deficit (cannot be covered by funds taken from Umbrella users)
    uint256 deficitOffset;
    /// @notice Deficit on top of `deficitOffset` (already slashed and waiting to be covered by Umbrella)
    uint256 pendingDeficit;
  }

  /// @custom:storage-location erc7201:umbrella.storage.UmbrellaConfiguration
  struct UmbrellaConfigurationStorage {
    /// @notice Map of reserve addresses and their data
    mapping(address reserve => ReserveData) reservesData;
    /// @notice Map of stake addresses and their data
    mapping(address umbrellaStake => StakeTokenData) stakesData;
    /// @notice Aave Pool addresses provider
    IPoolAddressesProvider poolAddressesProvider;
    /// @notice Address that is receiving the slashed funds
    address slashedFundsRecipient;
    /// @notice Aave Pool
    IPool pool;
  }

  // keccak256(abi.encode(uint256(keccak256("umbrella.storage.UmbrellaConfiguration")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant UmbrellaConfigurationStorageLocation =
    0x61e7d5b2c9a910ff2378dac2bb693c18f23b4adc05f805890f8a32ff43c62c00;

  function _getUmbrellaConfigurationStorage()
    private
    pure
    returns (UmbrellaConfigurationStorage storage $)
  {
    assembly {
      $.slot := UmbrellaConfigurationStorageLocation
    }
  }

  function __UmbrellaConfiguration_init(
    IPool pool,
    address slashedFundsRecipient
  ) internal onlyInitializing {
    require(address(pool) != address(0) && slashedFundsRecipient != address(0), ZeroAddress());

    UmbrellaConfigurationStorage storage $ = _getUmbrellaConfigurationStorage();
    $.poolAddressesProvider = IPoolAddressesProvider(pool.ADDRESSES_PROVIDER());
    $.slashedFundsRecipient = slashedFundsRecipient;
    $.pool = pool;
  }

  /// @inheritdoc IUmbrellaConfiguration
  function updateSlashingConfigs(
    SlashingConfigUpdate[] calldata slashingConfigs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i; i < slashingConfigs.length; ++i) {
      _updateSlashingConfig(slashingConfigs[i]);
    }
  }

  /// @inheritdoc IUmbrellaConfiguration
  function removeSlashingConfigs(
    SlashingConfigRemoval[] calldata removalPairs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    UmbrellaConfigurationStorage storage $ = _getUmbrellaConfigurationStorage();

    for (uint256 i; i < removalPairs.length; ++i) {
      EnumerableMap.AddressToUintMap storage map = $
        .reservesData[removalPairs[i].reserve]
        .configurationMap;

      bool configRemoved = map.remove(removalPairs[i].umbrellaStake);
      if (configRemoved) {
        // `underlyingOracle` will remain after config removal in order to make function `latestAnswer` inside `UmbrellaStakeToken` workable after config removal
        // This oracle should not be the only source of price and should not be used after removing the config, however, for the full functionality of `UmbrellaStakeToken`, we will leave it
        delete $.stakesData[removalPairs[i].umbrellaStake].reserve;

        emit SlashingConfigurationRemoved(removalPairs[i].reserve, removalPairs[i].umbrellaStake);
      }
    }
  }

  /// @inheritdoc IUmbrellaConfiguration
  function getReserveSlashingConfig(
    address reserve,
    address umbrellaStake
  ) external view returns (SlashingConfig memory) {
    UmbrellaConfigurationStorage storage $ = _getUmbrellaConfigurationStorage();
    (bool exist, uint256 value) = $.reservesData[reserve].configurationMap.tryGet(umbrellaStake);
    require(exist, ConfigurationDoesNotExist());

    return
      SlashingConfig({
        umbrellaStake: umbrellaStake,
        umbrellaStakeUnderlyingOracle: $.stakesData[umbrellaStake].underlyingOracle,
        liquidationFee: value
      });
  }

  /// @inheritdoc IUmbrellaConfiguration
  function getStakeTokenData(address umbrellaStake) external view returns (StakeTokenData memory) {
    return _getUmbrellaConfigurationStorage().stakesData[umbrellaStake];
  }

  /// @inheritdoc IUmbrellaConfigurationBase
  function latestUnderlyingAnswer(address umbrellaStake) external view returns (int256) {
    address underlyingOracle = _getUmbrellaConfigurationStorage()
      .stakesData[umbrellaStake]
      .underlyingOracle;
    require(underlyingOracle != address(0), ConfigurationHasNotBeenSet());

    return AggregatorInterface(underlyingOracle).latestAnswer();
  }

  /// @inheritdoc IUmbrellaConfiguration
  function getReserveSlashingConfigs(
    address reserve
  ) public view returns (SlashingConfig[] memory) {
    UmbrellaConfigurationStorage storage $ = _getUmbrellaConfigurationStorage();
    EnumerableMap.AddressToUintMap storage map = $.reservesData[reserve].configurationMap;
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

  /// @inheritdoc IUmbrellaConfiguration
  function isReserveSlashable(address reserve) public view returns (bool, uint256) {
    ReserveData storage reserveData = _getUmbrellaConfigurationStorage().reservesData[reserve];

    uint256 poolDeficit = POOL().getReserveDeficit(reserve);
    uint256 notSlashableDeficit = reserveData.deficitOffset + reserveData.pendingDeficit;

    uint256 newDeficit = poolDeficit > notSlashableDeficit ? poolDeficit - notSlashableDeficit : 0;

    if (reserveData.configurationMap.length() == 1 && newDeficit > 0) {
      return (true, newDeficit);
    }

    return (false, newDeficit);
  }

  /// @inheritdoc IUmbrellaConfiguration
  function getDeficitOffset(address reserve) public view returns (uint256) {
    return _getUmbrellaConfigurationStorage().reservesData[reserve].deficitOffset;
  }

  /// @inheritdoc IUmbrellaConfiguration
  function getPendingDeficit(address reserve) public view returns (uint256) {
    return _getUmbrellaConfigurationStorage().reservesData[reserve].pendingDeficit;
  }

  /// @inheritdoc IUmbrellaConfiguration
  function POOL_ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
    return _getUmbrellaConfigurationStorage().poolAddressesProvider;
  }

  /// @inheritdoc IUmbrellaConfigurationBase
  function SLASHED_FUNDS_RECIPIENT() public view returns (address) {
    return _getUmbrellaConfigurationStorage().slashedFundsRecipient;
  }

  /// @inheritdoc IUmbrellaConfiguration
  function POOL() public view returns (IPool) {
    return _getUmbrellaConfigurationStorage().pool;
  }

  function _updateSlashingConfig(SlashingConfigUpdate calldata slashConfig) internal {
    require(
      slashConfig.reserve != address(0) &&
        slashConfig.umbrellaStake != address(0) &&
        slashConfig.umbrellaStakeUnderlyingOracle != address(0),
      ZeroAddress()
    );

    require(slashConfig.liquidationFee <= ONE_HUNDRED_PERCENT, InvalidLiquidationFee());
    require(_isUmbrellaStkToken(slashConfig.umbrellaStake), InvalidStakeToken());
    require(
      IERC20Metadata(slashConfig.umbrellaStake).decimals() ==
        IERC20Metadata(slashConfig.reserve).decimals(),
      InvalidNumberOfDecimals()
    );

    // one-time safety checks
    require(POOL().getConfiguration(slashConfig.reserve).data != 0, InvalidReserve());
    require(
      AggregatorInterface(slashConfig.umbrellaStakeUnderlyingOracle).latestAnswer() > 0,
      InvalidOraclePrice()
    );

    UmbrellaConfigurationStorage storage $ = _getUmbrellaConfigurationStorage();
    ReserveData storage reserveData = $.reservesData[slashConfig.reserve];

    // Using the same `UmbrellaStakeToken` for several different reserves is prohibited
    // Cause of this we check `currentReserve` address:
    // If it's empty, then this stake isn't configured for another reserve
    // If `slashConfig.reserve` address match the current one, then we are trying to update `slashingConfig`
    // `revert` otherwise
    address currentReserve = $.stakesData[slashConfig.umbrellaStake].reserve;
    require(
      currentReserve == slashConfig.reserve || currentReserve == address(0),
      UmbrellaStakeAlreadySetForAnotherReserve()
    );

    // When a reserve is initialized the pool deficit is set to the `deficitOffset`, as otherwise an immediate slashing could be triggered.
    // Initialization should happen whenever a first stk is added to the coverage map.
    // If for some reason, all stake tokens are removed after initialization, then it is fine and correct to re-initialize `deficitOffset` for the same reason during this setup.
    if (reserveData.configurationMap.length() == 0) {
      // if `pendingDeficit` is not zero for some reason, e.g. reinitialize occurs without previous full coverage `pendingDeficit`,
      // than we need to take this value into account to set new `deficitOffset` here.
      uint256 poolDeficit = POOL().getReserveDeficit(slashConfig.reserve);
      uint256 pendingDeficit = reserveData.pendingDeficit;

      _setDeficitOffset(slashConfig.reserve, poolDeficit - pendingDeficit);
    }

    reserveData.configurationMap.set(slashConfig.umbrellaStake, slashConfig.liquidationFee);
    $.stakesData[slashConfig.umbrellaStake] = StakeTokenData({
      underlyingOracle: slashConfig.umbrellaStakeUnderlyingOracle,
      reserve: slashConfig.reserve
    });

    emit SlashingConfigurationChanged(
      slashConfig.reserve,
      slashConfig.umbrellaStake,
      slashConfig.liquidationFee,
      slashConfig.umbrellaStakeUnderlyingOracle
    );
  }

  function _setDeficitOffset(address reserve, uint256 newReserveDeficit) internal {
    _getUmbrellaConfigurationStorage().reservesData[reserve].deficitOffset = newReserveDeficit;

    emit DeficitOffsetChanged(reserve, newReserveDeficit);
  }

  function _setPendingDeficit(address reserve, uint256 newReserveDeficit) internal {
    _getUmbrellaConfigurationStorage().reservesData[reserve].pendingDeficit = newReserveDeficit;

    emit PendingDeficitChanged(reserve, newReserveDeficit);
  }
}
