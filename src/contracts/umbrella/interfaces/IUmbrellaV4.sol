// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaConfigurationV4} from './IUmbrellaConfigurationV4.sol';
import {IUmbrellaBase} from './IUmbrellaBase.sol';

interface IUmbrellaV4 is IUmbrellaConfigurationV4, IUmbrellaBase {
  /**
   * @notice Event is emitted whenever the `deficitOffset` of a `spoke` is covered on some amount.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset which `deficitOffset` is covered
   * @param spoke `Spoke` which `deficitOffset` is covered
   * @param amount Amount of covered `deficitOffset`
   */
  event DeficitOffsetCovered(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    uint256 amount
  );

  /**
   * @notice Event is emitted whenever the `pendingDeficit` of a `spoke` is covered on some amount.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset which `pendingDeficit` is covered
   * @param spoke `Spoke` which `pendingDeficit` is covered
   * @param amount Amount of covered `pendingDeficit`
   */
  event PendingDeficitCovered(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    uint256 amount
  );

  /**
   * @notice Event is emitted whenever the deficit of a `spoke` untuned inside `Umbrella` is covered on some amount.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset which `spoke` deficit is covered
   * @param spoke `Spoke` which deficit is covered
   * @param amount Amount of covered `spoke` deficit
   */
  event SpokeDeficitCovered(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    uint256 amount
  );

  /**
   * @notice Event is emitted when funds are slashed from a `umbrellaStake` to cover a `spoke` deficit.
   * @dev `umbrellaStake` is not indexed, cause the maximum number of indexed parameters is already
   * taken by the tuple identifying the covered position.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset for which funds are slashed
   * @param spoke `Spoke` for which funds are slashed
   * @param umbrellaStake Address of the `UmbrellaStakeToken` from which funds are transferred
   * @param amount Amount of funds slashed for future deficit elimination
   * @param fee Additional fee amount slashed on top of the amount
   */
  event StakeTokenSlashed(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    address umbrellaStake,
    uint256 amount,
    uint256 fee
  );

  /**
   * @notice Event is emitted when residual funds deposited in a `Hub` are withdrawn to the slashed funds recipient.
   * @param hub `Hub` from which the funds are withdrawn
   * @param assetId Id of the withdrawn asset
   * @param amount Amount of underlying withdrawn
   * @param shares Amount of `UmbrellaSpoke` shares removed from the `Hub`
   */
  event StrandedFundsWithdrawn(
    address indexed hub,
    uint256 indexed assetId,
    uint256 amount,
    uint256 shares
  );

  /**
   * @dev Attempted to call `coverSpokeDeficit()` of a `spoke`, which has some configuration.
   * In this case functions `coverPendingDeficit` or `coverDeficitOffset` should be used instead.
   */
  error SpokeIsConfigured();

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Sets a new `deficitOffset` value for this `spoke`.
   * @dev `deficitOffset` can be increased arbitrarily by a value exceeding `spokeDeficit - pendingDeficit`.
   * It can also be decreased, but not less than the same value `spokeDeficit - pendingDeficit`.
   * `deficitOffset` can only be changed for a `spoke` covered by a `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @param newDeficitOffset New amount of `deficitOffset` to set for this `spoke`
   */
  function setDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 newDeficitOffset
  ) external;

  /**
   * @notice Withdraws residual funds deposited by this contract in a `Hub` to the slashed funds recipient.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param amount Amount of underlying to withdraw
   * @return shares Amount of `UmbrellaSpoke` shares removed from the `Hub`
   */
  function withdrawStrandedFunds(
    address hub,
    uint256 assetId,
    uint256 amount
  ) external returns (uint256 shares);

  // COVERAGE_MANAGER_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Pulls funds to resolve the `pendingDeficit` of a `spoke` **up to** specified amount.
   * @dev If the amount exceeds the existing `pendingDeficit`, only the `pendingDeficit` will be eliminated.
   * Reverts if the `spoke` is not covered by this `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @param amount Amount of tokens to be eliminated
   * @return The amount of `pendingDeficit` eliminated
   */
  function coverPendingDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external returns (uint256);

  /**
   * @notice Pulls funds to resolve the `deficitOffset` of a `spoke` **up to** specified amount.
   * @dev If the amount exceeds the existing `deficitOffset`, only the `deficitOffset` will be eliminated.
   * Reverts if the `spoke` is not covered by this `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @param amount Amount of tokens to be eliminated
   * @return The amount of `deficitOffset` eliminated
   */
  function coverDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external returns (uint256);

  /**
   * @notice Pulls funds to resolve the deficit of a `spoke` **up to** specified amount.
   * @dev If the amount exceeds the existing `spoke` deficit, only the `spoke` deficit will be eliminated.
   * Can only be called if this `spoke` is not configured within `Umbrella`.
   * (If the `spoke` has uncovered `deficitOffset`, `pendingDeficit` or at least one `SlashingConfig` is set
   * for its `hub` and `assetId` pair, then the function will revert. In this case, to call this function you must
   * first cover `pendingDeficit` and `deficitOffset`, along with removing all `SlashingConfig`s
   * or use `coverPendingDeficit/coverDeficitOffset` instead.)
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @param amount Amount of tokens to be eliminated
   * @return The amount of `spoke` deficit eliminated
   */
  function coverSpokeDeficit(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external returns (uint256);

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Performs a slashing to cover **up to** the new deficit reported by a `spoke`,
   * i.e. `spokeDeficit - (pendingDeficit + deficitOffset)`.
   * @dev Reverts if the `spoke` is not covered by this `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return New added and covered deficit
   */
  function slash(address hub, uint256 assetId, address spoke) external returns (uint256);

  /**
   * @notice Returns an address of token, which should be used to cover a deficit of this `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return Address of token to use for deficit coverage
   */
  function tokenForDeficitCoverage(address hub, uint256 assetId) external view returns (address);
}
