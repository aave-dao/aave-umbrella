// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';

import {IUmbrellaConfigurationBase} from './IUmbrellaConfigurationBase.sol';

interface IUmbrellaConfiguration is IUmbrellaConfigurationBase {
  struct SlashingConfigUpdate {
    /// @notice Reserve which configuration should be updated
    address reserve;
    /// @notice Address of `UmbrellaStakeToken` that should be set for this reserve
    address umbrellaStake;
    /// @notice Percentage of funds slashed on top of the new deficit
    uint256 liquidationFee;
    /// @notice Oracle of `UmbrellaStakeToken`s underlying
    address umbrellaStakeUnderlyingOracle;
  }

  struct SlashingConfigRemoval {
    /// @notice Reserve which configuration is being removed
    address reserve;
    /// @notice Address of `UmbrellaStakeToken` that will be removed from this reserve
    address umbrellaStake;
  }

  struct StakeTokenData {
    /// @notice Oracle for pricing an underlying assets of `UmbrellaStakeToken`
    /// @dev Remains after removal of `SlashingConfig`
    address underlyingOracle;
    /// @notice Reserve address for which this `UmbrellaStakeToken` is configured
    /// @dev Will be deleted after removal of `SlashingConfig`
    address reserve;
  }

  /**
   * @notice Event is emitted whenever a configuration is added or updated.
   * @param reserve Reserve which configuration is changed
   * @param umbrellaStake Address of `UmbrellaStakeToken`
   * @param liquidationFee Percentage of funds slashed on top of the deficit
   * @param umbrellaStakeUnderlyingOracle `UmbrellaStakeToken` underlying oracle address
   */
  event SlashingConfigurationChanged(
    address indexed reserve,
    address indexed umbrellaStake,
    uint256 liquidationFee,
    address umbrellaStakeUnderlyingOracle
  );

  /**
   * @notice Event is emitted whenever a configuration is removed.
   * @param reserve Reserve which configuration is removed
   * @param umbrellaStake Address of `UmbrellaStakeToken`
   */
  event SlashingConfigurationRemoved(address indexed reserve, address indexed umbrellaStake);

  /**
   * @notice Event is emitted whenever the `deficitOffset` is changed.
   * @param reserve Reserve which `deficitOffset` is changed
   * @param newDeficitOffset New amount of `deficitOffset`
   */
  event DeficitOffsetChanged(address indexed reserve, uint256 newDeficitOffset);

  /**
   * @notice Event is emitted whenever the `pendingDeficit` is changed.
   * @param reserve Reserve which `pendingDeficit` is changed
   * @param newPendingDeficit New amount of `pendingDeficit`
   */
  event PendingDeficitChanged(address indexed reserve, uint256 newPendingDeficit);

  /**
   * @dev Attempted to set `UmbrellaStakeToken`, which is already set for another reserve.
   */
  error UmbrellaStakeAlreadySetForAnotherReserve();

  /**
   * @dev Attempted to add `reserve` to configuration, which isn't exist in the `Pool`.
   */
  error InvalidReserve();

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Updates a set of slashing configurations.
   * @dev If the configs contain an already existing configuration, the configuration will be overwritten.
   * If install more than 1 configuration, then `slash` will not work in the current version.
   * @param slashingConfigs An array of configurations
   */
  function updateSlashingConfigs(SlashingConfigUpdate[] calldata slashingConfigs) external;

  /**
   * @notice Removes a set of slashing configurations.
   * @dev If such a config did not exist, the function does not revert.
   * @param removalPairs An array of coverage pairs (reserve:stk) to remove
   */
  function removeSlashingConfigs(SlashingConfigRemoval[] calldata removalPairs) external;

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns all the slashing configurations, configured for a given `reserve`.
   * @param reserve Address of the `reserve`
   * @return An array of `SlashingConfig` structs
   */
  function getReserveSlashingConfigs(
    address reserve
  ) external view returns (SlashingConfig[] memory);

  /**
   * @notice Returns the slashing configuration for a given `UmbrellaStakeToken` in regards to a specific `reserve`.
   * @dev Reverts if `SlashingConfig` doesn't exist.
   * @param reserve Address of the `reserve`
   * @param umbrellaStake Address of the `UmbrellaStakeToken`
   * @return A `SlashingConfig` struct
   */
  function getReserveSlashingConfig(
    address reserve,
    address umbrellaStake
  ) external view returns (SlashingConfig memory);

  /**
   * @notice Returns if a reserve is currently slashable or not.
   * A reserve is slashable if:
   * - there's only one stk configured for slashing
   * - if there is a non zero new deficit
   * @param reserve Address of the `reserve`
   * @return flag If `Umbrella` could slash for a given `reserve`
   * @return amount Amount of the new deficit, by which `UmbrellaStakeToken` potentially could be slashed
   */
  function isReserveSlashable(address reserve) external view returns (bool flag, uint256 amount);

  /**
   * @notice Returns the amount of deficit that can't be slashed using `UmbrellaStakeToken` funds.
   * @param reserve Address of the `reserve`
   * @return The amount of the `deficitOffset`
   */
  function getDeficitOffset(address reserve) external view returns (uint256);

  /**
   * @notice Returns the amount of already slashed funds that have not yet been used for the deficit elimination.
   * @param reserve Address of the `reserve`
   * @return The amount of funds pending for deficit elimination
   */
  function getPendingDeficit(address reserve) external view returns (uint256);

  /**
   * @notice Returns the `StakeTokenData` of the `umbrellaStake`.
   * @param umbrellaStake Address of the `UmbrellaStakeToken`
   * @return stakeTokenData A `StakeTokenData` struct
   */
  function getStakeTokenData(
    address umbrellaStake
  ) external view returns (StakeTokenData memory stakeTokenData);

  /**
   * @notice Returns the Pool addresses provider.
   * @return Pool addresses provider address
   */
  function POOL_ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider);

  /**
   * @notice Returns the Aave Pool for which this `Umbrella` instance is configured.
   * @return Pool address
   */
  function POOL() external view returns (IPool);
}
