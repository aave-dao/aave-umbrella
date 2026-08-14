// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaConfigurationV3} from './IUmbrellaConfigurationV3.sol';
import {IUmbrella} from './IUmbrella.sol';

interface IUmbrellaV3 is IUmbrellaConfigurationV3, IUmbrella {
  /**
   * @notice Event is emitted whenever the `deficitOffset` is covered on some amount.
   * @param reserve Reserve which `deficitOffset` is covered
   * @param amount Amount of covered `deficitOffset`
   */
  event DeficitOffsetCovered(address indexed reserve, uint256 amount);

  /**
   * @notice Event is emitted whenever the `pendingDeficit` is covered on some amount.
   * @param reserve Reserve which `pendingDeficit` is covered
   * @param amount Amount of covered `pendingDeficit`
   */
  event PendingDeficitCovered(address indexed reserve, uint256 amount);

  /**
   * @notice Event is emitted whenever the deficit for untuned inside `Umbrella` reserve is covered on some amount.
   * @param reserve Reserve which `reserve.deficit` is covered
   * @param amount Amount of covered `reserve.deficit`
   */
  event ReserveDeficitCovered(address indexed reserve, uint256 amount);

  /**
   * @notice Event is emitted when funds are slashed from a `umbrellaStake` to cover a reserve deficit.
   * @param reserve Reserve address for which funds are slashed
   * @param umbrellaStake Address of the `UmbrellaStakeToken` from which funds are transferred
   * @param amount Amount of funds slashed for future deficit elimination
   * @param fee Additional fee amount slashed on top of the amount
   */
  event StakeTokenSlashed(
    address indexed reserve,
    address indexed umbrellaStake,
    uint256 amount,
    uint256 fee
  );

  /**
   * @dev Attempted to change `deficitOffset` for a reserve that does not have a slashing configuration.
   */
  error ReserveCoverageNotSetup();

  /**
   * @dev Attempted to call `coverReserveDeficit()` of reserve, which has some configuration.
   * In this case functions `coverPendingDeficit` or `coverDeficitOffset` should be used instead.
   */
  error ReserveIsConfigured();

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Sets a new `deficitOffset` value for this `reserve`.
   * @dev `deficitOffset` can be increased arbitrarily by a value exceeding `poolDeficit - pendingDeficit`.
   * It can also be decreased, but not less than the same value `poolDeficit - pendingDeficit`.
   * `deficitOffset` can only be changed for reserves that have at least 1 `SlashingConfig` setup.
   * @param reserve Reserve address
   * @param newDeficitOffset New amount of `deficitOffset` to set for this reserve
   */
  function setDeficitOffset(address reserve, uint256 newDeficitOffset) external;

  // COVERAGE_MANAGER_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Pulls funds to resolve `pendingDeficit` **up to** specified amount.
   * @dev If the amount exceeds the existing `pendingDeficit`, only the `pendingDeficit` will be eliminated.
   * @param reserve Reserve address
   * @param amount Amount of `aToken`s (or reserve) to be eliminated
   * @return The amount of `pendingDeficit` eliminated
   */
  function coverPendingDeficit(address reserve, uint256 amount) external returns (uint256);

  /**
   * @notice Pulls funds to resolve `deficitOffset` **up to** specified amount.
   * @dev If the amount exceeds the existing `deficitOffset`, only the `deficitOffset` will be eliminated.
   * @param reserve Reserve address
   * @param amount Amount of `aToken`s (or reserve) to be eliminated
   * @return The amount of `deficitOffset` eliminated
   */
  function coverDeficitOffset(address reserve, uint256 amount) external returns (uint256);

  /**
   * @notice Pulls funds to resolve `reserve.deficit` **up to** specified amount.
   * @dev If the amount exceeds the existing `reserve.deficit`, only the `reserve.deficit` will be eliminated.
   * Can only be called if this reserve is not configured within `Umbrella`.
   * (If the reserve has uncovered `deficitOffset`, `pendingDeficit` or at least one `SlashingConfig` is set, then the function will revert.
   * In this case, to call this function you must first cover `pendingDeficit` and `deficitOffset`, along with removing all `SlashingConfig`s
   * or use `coverPendingDeficit/coverDeficitOffset` instead.)
   * @param reserve Reserve address
   * @param amount Amount of `aToken`s (or reserve) to be eliminated
   * @return The amount of `reserve.deficit` eliminated
   */
  function coverReserveDeficit(address reserve, uint256 amount) external returns (uint256);

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Performs a slashing to cover **up to** the `Pool.getReserveDeficit(reserve) - (pendingDeficit + deficitOffset)`.
   * @param reserve Reserve address
   * @return New added and covered deficit
   */
  function slash(address reserve) external returns (uint256);

  /**
   * @notice Returns an address of token, which should be used to cover reserve deficit.
   * @param reserve Reserve address
   * @return Address of token to use for deficit coverage
   */
  function tokenForDeficitCoverage(address reserve) external view returns (address);
}
