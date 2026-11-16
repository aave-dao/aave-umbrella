// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AggregatorInterface} from 'aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol';

import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {IPriceOracle} from 'aave-v4/spoke/interfaces/IPriceOracle.sol';
import {ISpoke} from 'aave-v4/spoke/interfaces/ISpoke.sol';
import {MathUtils} from 'aave-v4/libraries/math/MathUtils.sol';
import {PercentageMath} from 'aave-v4/libraries/math/PercentageMath.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import {IUmbrellaV4} from './interfaces/IUmbrellaV4.sol';
import {IUmbrellaStakeToken} from '../stakeToken/interfaces/IUmbrellaStakeToken.sol';

import {UmbrellaConfigurationV4} from './UmbrellaConfigurationV4.sol';
import {UmbrellaStkManager} from './UmbrellaStkManager.sol';

/**
 * @title UmbrellaSpoke
 * @notice This contract provides mechanisms for managing and resolving `spoke` deficits within the Aave V4 protocol.
 * It facilitates deficit coverage through direct contributions and incorporates slashing functionality to address deficits by slashing umbrella stake tokens.
 * The contract supports only single-asset slashing in the current version.
 * @dev Deficit is covered by adding liquidity to the `Hub` and immediately removing the resulting shares through
 * `eliminateDeficit`. This contract must therefore be listed as an active `spoke` of every covered `hub` and
 * `assetId` hub asset and be authorized to call `Hub.eliminateDeficit()`.
 * @author BGD labs
 */
contract UmbrellaSpoke is UmbrellaConfigurationV4, UmbrellaStkManager, IUmbrellaV4 {
  using Math for uint256;
  using PercentageMath for uint256;
  using SafeERC20 for IERC20;
  using {MathUtils.zeroFloorSub} for uint256;

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address governance,
    address slashedFundsRecipient,
    address umbrellaStakeTokenImpl,
    address transparentProxyFactory
  ) external virtual initializer {
    __UmbrellaStkManager_init(governance, umbrellaStakeTokenImpl, transparentProxyFactory);
    __UmbrellaConfigurationV4_init(slashedFundsRecipient);
  }

  /// @inheritdoc IUmbrellaV4
  function setDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 newDeficitOffset
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_getAssetSlashingConfigsCount(hub, assetId) != 0, AssetCoverageNotSetup());
    require(isSpokeCovered(hub, assetId, spoke), SpokeNotCovered());
    require(
      newDeficitOffset + getPendingDeficit(hub, assetId, spoke) >=
        _getSpokeDeficit(hub, assetId, spoke),
      TooMuchDeficitOffsetReduction()
    );

    _setDeficitOffset(hub, assetId, spoke, newDeficitOffset);
  }

  /// @inheritdoc IUmbrellaV4
  function withdrawStrandedFunds(
    address hub,
    uint256 assetId,
    uint256 amount
  ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
    uint256 shares = IHub(hub).remove(assetId, amount, SLASHED_FUNDS_RECIPIENT());

    emit StrandedFundsWithdrawn(hub, assetId, amount, shares);

    return shares;
  }

  /// @inheritdoc IUmbrellaV4
  function coverDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 spokeDeficit = _getSpokeDeficit(hub, assetId, spoke);

    uint256 deficitOffset = getDeficitOffset(hub, assetId, spoke);
    uint256 pendingDeficit = getPendingDeficit(hub, assetId, spoke);

    uint256 coverableOffset = deficitOffset.min(spokeDeficit.zeroFloorSub(pendingDeficit));

    amount = _coverDeficit(hub, assetId, spoke, amount, coverableOffset);

    _setDeficitOffset(hub, assetId, spoke, deficitOffset - amount);

    emit DeficitOffsetCovered(hub, assetId, spoke, amount);

    return amount;
  }

  /// @inheritdoc IUmbrellaV4
  function coverPendingDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 pendingDeficit = getPendingDeficit(hub, assetId, spoke);

    amount = _coverDeficit(hub, assetId, spoke, amount, pendingDeficit);
    _setPendingDeficit(hub, assetId, spoke, pendingDeficit - amount);

    emit PendingDeficitCovered(hub, assetId, spoke, amount);

    return amount;
  }

  /// @inheritdoc IUmbrellaV4
  function coverSpokeDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 pendingDeficit = getPendingDeficit(hub, assetId, spoke);
    uint256 deficitOffset = getDeficitOffset(hub, assetId, spoke);

    require(
      pendingDeficit == 0 && deficitOffset == 0 && !isSpokeCovered(hub, assetId, spoke),
      SpokeIsConfigured()
    );
    uint256 spokeDeficit = _getSpokeDeficit(hub, assetId, spoke);

    amount = _coverDeficit(hub, assetId, spoke, amount, spokeDeficit);

    emit SpokeDeficitCovered(hub, assetId, spoke, amount);

    return amount;
  }

  /// @inheritdoc IUmbrellaV4
  function slash(address hub, uint256 assetId, address spoke) external returns (uint256) {
    (bool isSlashable, uint256 newDeficit) = isSpokeSlashable(hub, assetId, spoke);

    if (!isSlashable) {
      revert CannotSlash();
    }

    SlashingConfig[] memory configs = getAssetSlashingConfigs(hub, assetId);
    uint256 newCoveredAmount;

    if (configs.length == 1) {
      newCoveredAmount = _slashAsset(hub, assetId, spoke, configs[0], newDeficit);
    } else {
      // Specially removed for simplification in the current version
      // For now it's unreachable code
      revert NotImplemented();
    }

    _setPendingDeficit(
      hub,
      assetId,
      spoke,
      getPendingDeficit(hub, assetId, spoke) + newCoveredAmount
    );

    return newCoveredAmount;
  }

  /// @inheritdoc IUmbrellaV4
  function tokenForDeficitCoverage(address hub, uint256 assetId) external view returns (address) {
    (address underlying, ) = IHub(hub).getAssetUnderlyingAndDecimals(assetId);

    return underlying;
  }

  function _coverDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount,
    uint256 deficitToCover
  ) internal returns (uint256) {
    amount = amount.min(deficitToCover);
    require(amount != 0, ZeroDeficitToCover());

    (address underlying, ) = IHub(hub).getAssetUnderlyingAndDecimals(assetId);

    // `eliminateDeficit()` burns the shares of `amount` rounded up, while `add()` mints them rounding down.
    // Pulling the assets worth these shares rounded up makes `add()` mint at least the shares the elimination burns,
    // at the cost of up to a few wei more than `amount` paid by the caller.
    uint256 assetsToAdd = IHub(hub).previewAddByShares(
      assetId,
      IHub(hub).previewRemoveByAssets(assetId, amount)
    );

    // `Hub` expects the underlying to be transferred before the `add()` call
    IERC20(underlying).safeTransferFrom(_msgSender(), hub, assetsToAdd);
    IHub(hub).add(assetId, assetsToAdd);

    (, uint256 eliminatedAmount) = IHub(hub).eliminateDeficit(assetId, amount, spoke);

    // If the deficit turned out to be smaller than `amount`, e.g. because of some desynchronization, the `Hub` eliminates less
    // and the remaining shares stay inside it, to be withdrawn using `withdrawStrandedFunds()`.
    // However, we must not count them into the amount discounted from the deficit tracked here,
    // otherwise `Umbrella` will think that there is a deficit when in fact it's fully eliminated.

    return eliminatedAmount;
  }

  function _slashAsset(
    address hub,
    uint256 assetId,
    address spoke,
    SlashingConfig memory config,
    uint256 deficitToCover
  ) internal returns (uint256) {
    uint256 deficitToCoverWithFee = config.liquidationFee != 0
      ? deficitToCover.percentMulDown(config.liquidationFee + PercentageMath.PERCENTAGE_FACTOR)
      : deficitToCover;

    // amount of asset multiplied by it price
    uint256 deficitMulPrice = _deficitMulPrice(hub, assetId, spoke, deficitToCoverWithFee);

    // price of `UmbrellaStakeToken` underlying
    uint256 underlyingPrice = uint256(
      AggregatorInterface(config.umbrellaStakeUnderlyingOracle).latestAnswer()
    );

    // amount of underlying tokens to slash from `UmbrellaStakeToken`
    uint256 amountToSlash = deficitMulPrice / underlyingPrice;

    // amount of tokens that were actually slashed
    uint256 realSlashedAmount = IUmbrellaStakeToken(config.umbrellaStake).slash(
      SLASHED_FUNDS_RECIPIENT(),
      amountToSlash
    );

    uint256 newCoveredAmount;
    uint256 liquidationFeeAmount;

    // since `realSlashedAmount` always less or equal than `amountToSlash`
    if (realSlashedAmount == amountToSlash) {
      newCoveredAmount = deficitToCover;
      liquidationFeeAmount = deficitToCoverWithFee - deficitToCover;
    } else {
      newCoveredAmount = (deficitToCover * realSlashedAmount) / amountToSlash;
      liquidationFeeAmount =
        ((deficitToCoverWithFee - deficitToCover) * realSlashedAmount) /
        amountToSlash;
    }

    emit StakeTokenSlashed(
      hub,
      assetId,
      spoke,
      config.umbrellaStake,
      newCoveredAmount,
      liquidationFeeAmount
    );

    return newCoveredAmount;
  }

  function _deficitMulPrice(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 deficit
  ) internal view returns (uint256) {
    uint256 reserveId = ISpoke(spoke).getReserveId(hub, assetId);

    return IPriceOracle(ISpoke(spoke).ORACLE()).getReservePrice(reserveId) * deficit;
  }
}
