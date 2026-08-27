// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IUmbrellaConfigurationBase {
  struct SlashingConfig {
    /// @notice Address of `UmbrellaStakeToken`
    address umbrellaStake;
    /// @notice `UmbrellaStakeToken` underlying oracle address
    address umbrellaStakeUnderlyingOracle;
    /// @notice Percentage of funds slashed on top of the new deficit
    uint256 liquidationFee;
  }

  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();

  /**
   * @dev Attempted to interact with a `UmbrellaStakeToken` that should be deployed by this `Umbrella` instance, but is not.
   */
  error InvalidStakeToken();

  /**
   * @dev Attempted to set a `UmbrellaStakeToken` that has a different number of decimals than `reserve`.
   */
  error InvalidNumberOfDecimals();

  /**
   * @dev Attempted to set `liquidationFee` greater than 100%.
   */
  error InvalidLiquidationFee();

  /**
   * @dev Attempted to get `SlashingConfig` for this `reserve` and `StakeToken`, however config doesn't exist for this pair.
   */
  error ConfigurationDoesNotExist();

  /**
   * @dev Attempted to get price of `StakeToken` underlying, however the oracle has never been set.
   */
  error ConfigurationHasNotBeenSet();

  /**
   * @dev Attempted to set `umbrellaStakeUnderlyingOracle` that returns invalid price.
   */
  error InvalidOraclePrice();

  /**
   * @notice Returns the price of the `UmbrellaStakeToken` underlying.
   * @dev This price is used for calculations inside `Umbrella` and should not be used outside of this system.
   *
   * The underlying price is determined based on the current oracle, if the oracle has never been set, the function will revert.
   * The system retains information about the last oracle installed for a given `StakeToken`.
   *
   * If the `SlashingConfig` associated with the `StakeToken` is removed, this function will still be operational.
   * However, the results of its work are not guaranteed.
   *
   * @param umbrellaStake Address of the `UmbrellaStakeToken`
   * @return latestAnswer Price of the underlying
   */
  function latestUnderlyingAnswer(
    address umbrellaStake
  ) external view returns (int256 latestAnswer);

  /**
   * @notice Returns the address that is receiving the slashed funds.
   * @return Slashed funds recipient
   */
  function SLASHED_FUNDS_RECIPIENT() external view returns (address);
}
