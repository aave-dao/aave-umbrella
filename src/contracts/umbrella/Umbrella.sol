// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {AggregatorInterface} from 'aave-v3-origin/contracts/dependencies/chainlink/AggregatorInterface.sol';
import {IAaveOracle} from 'aave-v3-origin/contracts/interfaces/IAaveOracle.sol';
import {IPool, DataTypes} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import {IUmbrella} from './interfaces/IUmbrella.sol';
import {IUmbrellaStakeToken} from '../stakeToken/interfaces/IUmbrellaStakeToken.sol';

import {UmbrellaConfiguration} from './UmbrellaConfiguration.sol';
import {UmbrellaStkManager} from './UmbrellaStkManager.sol';

/**
 * @title Umbrella
 * @notice This contract provides mechanisms for managing and resolving reserve deficits within the Aave V3 protocol.
 * It facilitates deficit coverage through direct contributions and incorporates slashing functionality to address deficits by slashing umbrella stake tokens.
 * The contract supports only single-asset slashing in the current version.
 * @author BGD labs
 */
contract Umbrella is UmbrellaConfiguration, UmbrellaStkManager, IUmbrella {
  using Math for uint256;
  using SafeERC20 for IERC20;
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  constructor() {
    _disableInitializers();
  }

  function initialize(
    IPool pool,
    address governance,
    address slashedFundsRecipient,
    address umbrellaStakeTokenImpl,
    address transparentProxyFactory
  ) external virtual initializer {
    __UmbrellaStkManager_init(governance, umbrellaStakeTokenImpl, transparentProxyFactory);
    __UmbrellaConfiguration_init(pool, slashedFundsRecipient);
  }

  /// @inheritdoc IUmbrella
  function setDeficitOffset(
    address reserve,
    uint256 newDeficitOffset
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(getReserveSlashingConfigs(reserve).length > 0, ReserveCoverageNotSetup());
    require(
      newDeficitOffset + getPendingDeficit(reserve) >= POOL().getReserveDeficit(reserve),
      TooMuchDeficitOffsetReduction()
    );

    _setDeficitOffset(reserve, newDeficitOffset);
  }

  /// @inheritdoc IUmbrella
  function coverDeficitOffset(
    address reserve,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 poolDeficit = POOL().getReserveDeficit(reserve);

    uint256 deficitOffset = getDeficitOffset(reserve);
    uint256 pendingDeficit = getPendingDeficit(reserve);

    if (deficitOffset + pendingDeficit > poolDeficit) {
      // This means, that `deficitOffset` was manually increased using `setDeficitOffset`.
      // Therefore, we need to recalculate the actual amount of deficit that can be covered in this case using `coverDeficitOffset` function.
      // Otherwise, we might reduce the pool deficit by the `pendingDeficit` value without updating its corresponding value in Umbrella,
      // which could lead to a desynchronization of these values.
      amount = _coverDeficit(reserve, amount, poolDeficit - pendingDeficit);
    } else {
      // This means that there is no artificially high `deficitOffset` now, so we can cover it 100%.
      amount = _coverDeficit(reserve, amount, deficitOffset);
    }

    _setDeficitOffset(reserve, deficitOffset - amount);

    emit DeficitOffsetCovered(reserve, amount);

    return amount;
  }

  /// @inheritdoc IUmbrella
  function coverPendingDeficit(
    address reserve,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 pendingDeficit = getPendingDeficit(reserve);

    amount = _coverDeficit(reserve, amount, pendingDeficit);
    _setPendingDeficit(reserve, pendingDeficit - amount);

    emit PendingDeficitCovered(reserve, amount);

    return amount;
  }

  /// @inheritdoc IUmbrella
  function coverReserveDeficit(
    address reserve,
    uint256 amount
  ) external onlyRole(COVERAGE_MANAGER_ROLE) returns (uint256) {
    uint256 length = getReserveSlashingConfigs(reserve).length;
    uint256 pendingDeficit = getPendingDeficit(reserve);
    uint256 deficitOffset = getDeficitOffset(reserve);

    require(pendingDeficit == 0 && deficitOffset == 0 && length == 0, ReserveIsConfigured());
    uint256 poolDeficit = POOL().getReserveDeficit(reserve);

    amount = _coverDeficit(reserve, amount, poolDeficit);

    emit ReserveDeficitCovered(reserve, amount);

    return amount;
  }

  /// @inheritdoc IUmbrella
  function slash(address reserve) external returns (uint256) {
    (bool isSlashable, uint256 newDeficit) = isReserveSlashable(reserve);

    if (!isSlashable) {
      revert CannotSlash();
    }

    SlashingConfig[] memory configs = getReserveSlashingConfigs(reserve);
    uint256 newCoveredAmount;

    if (configs.length == 1) {
      newCoveredAmount = _slashAsset(reserve, configs[0], newDeficit);
    } else {
      // Specially removed for simplification in the current version
      // For now it's unreachable code
      revert NotImplemented();
    }

    _setPendingDeficit(reserve, getPendingDeficit(reserve) + newCoveredAmount);

    return newCoveredAmount;
  }

  /// @inheritdoc IUmbrella
  function tokenForDeficitCoverage(address reserve) external view returns (address) {
    if (POOL().getConfiguration(reserve).getIsVirtualAccActive()) {
      return POOL().getReserveAToken(reserve);
    } else {
      return reserve;
    }
  }

  function _coverDeficit(
    address reserve,
    uint256 amount,
    uint256 deficitToCover
  ) internal returns (uint256) {
    amount = amount <= deficitToCover ? amount : deficitToCover;
    require(amount != 0, ZeroDeficitToCover());

    if (POOL().getConfiguration(reserve).getIsVirtualAccActive()) {
      // If virtual accounting is active, than we pull `aToken`
      address aToken = POOL().getReserveAToken(reserve);
      IERC20(aToken).safeTransferFrom(_msgSender(), address(this), amount);
      // Due to rounding error (cause of index growth), it is possible that we receive some wei less than expected
      uint256 balance = IERC20(aToken).balanceOf(address(this));
      // `balance <= amount` means, that we might have lost some wei due to rounding error
      // `balance > amount` means, that `aToken` was directly sent to this contract
      amount = balance <= amount ? balance : amount;
      // No need to approve, cause `aTokens` will be burned
    } else {
      // If virtual accounting isn't active, then we pull the underlying token
      IERC20(reserve).safeTransferFrom(_msgSender(), address(this), amount);
      // Need to approve, cause inside `Pool` `safeTransferFrom()` will be performed
      IERC20(reserve).forceApprove(address(POOL()), amount);
    }

    POOL().eliminateReserveDeficit(reserve, amount);

    // If for some reason there is dust left on this contract (for example, the deficit is less than we tried to cover, due to some desynchronization problems)
    // then the dust can be saved using the `emergencyTokenTransfer()` function.
    // However, we must not count this dust into the amount value for changing the deficit set in Umbrella,
    // otherwise Umbrella will think that there is a deficit when in fact it's fully eliminated.

    return amount;
  }

  function _slashAsset(
    address reserve,
    SlashingConfig memory config,
    uint256 deficitToCover
  ) internal returns (uint256) {
    uint256 deficitToCoverWithFee = config.liquidationFee != 0
      ? deficitToCover.mulDiv(config.liquidationFee + ONE_HUNDRED_PERCENT, ONE_HUNDRED_PERCENT)
      : deficitToCover;

    // amount of reserve multiplied by it price
    uint256 deficitMulPrice = _deficitMulPrice(reserve, deficitToCoverWithFee);

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

    emit StakeTokenSlashed(reserve, config.umbrellaStake, newCoveredAmount, liquidationFeeAmount);

    return newCoveredAmount;
  }

  function _deficitMulPrice(address reserve, uint256 deficit) internal view returns (uint256) {
    return IAaveOracle(POOL_ADDRESSES_PROVIDER().getPriceOracle()).getAssetPrice(reserve) * deficit;
  }
}
