// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaConfiguration} from './IUmbrellaConfiguration.sol';

interface IUmbrellaConfigurationV4 is IUmbrellaConfiguration {
  struct SlashingConfigUpdate {
    /// @notice `Hub` which configuration should be updated
    address hub;
    /// @notice Id of the `hub` asset which configuration should be updated
    uint256 assetId;
    /// @notice Address of `UmbrellaStakeToken` that should be set for this `hub` and `assetId` pair
    address umbrellaStake;
    /// @notice Percentage of funds slashed on top of the new deficit
    uint256 liquidationFee;
    /// @notice Oracle of the `hub` asset which deficit is covered
    /// @dev Shared by every `SlashingConfig` of this `hub` and `assetId` pair, the last update wins
    address assetOracle;
    /// @notice Oracle of `UmbrellaStakeToken`s underlying
    address umbrellaStakeUnderlyingOracle;
  }

  struct SlashingConfigRemoval {
    /// @notice `Hub` which configuration is being removed
    address hub;
    /// @notice Id of the `hub` asset which configuration is being removed
    uint256 assetId;
    /// @notice Address of `UmbrellaStakeToken` that will be removed from this `hub` and `assetId` pair
    address umbrellaStake;
  }

  struct SpokeCoverage {
    /// @notice `Hub` to which the `spoke` is connected
    address hub;
    /// @notice Id of the `hub` asset for which the `spoke` deficit is tracked
    uint256 assetId;
    /// @notice `Spoke` which deficit is tracked and covered by `Umbrella`
    address spoke;
  }

  struct StakeTokenData {
    /// @notice Oracle for pricing an underlying assets of `UmbrellaStakeToken`
    /// @dev Remains after removal of `SlashingConfig`
    address underlyingOracle;
    /// @notice `Hub` for which this `UmbrellaStakeToken` is configured
    /// @dev Will be deleted after removal of `SlashingConfig`
    address hub;
    /// @notice Id of the `hub` asset for which this `UmbrellaStakeToken` is configured
    /// @dev Will be deleted after removal of `SlashingConfig`.
    /// Narrowed to `uint96`, so that it shares a storage slot with `hub` and both are cleared together
    uint96 assetId;
  }

  /**
   * @notice Event is emitted whenever a configuration is added or updated.
   * @param hub `Hub` which configuration is changed
   * @param assetId Id of the `hub` asset which configuration is changed
   * @param umbrellaStake Address of `UmbrellaStakeToken`
   * @param liquidationFee Percentage of funds slashed on top of the deficit
   * @param umbrellaStakeUnderlyingOracle `UmbrellaStakeToken` underlying oracle address
   */
  event SlashingConfigurationChanged(
    address indexed hub,
    uint256 indexed assetId,
    address indexed umbrellaStake,
    uint256 liquidationFee,
    address umbrellaStakeUnderlyingOracle
  );

  /**
   * @notice Event is emitted whenever the oracle of a covered asset is set.
   * @param hub `Hub` which asset oracle is changed
   * @param assetId Id of the `hub` asset which oracle is changed
   * @param assetOracle Oracle of the `hub` asset which deficit is covered
   */
  event AssetOracleChanged(
    address indexed hub,
    uint256 indexed assetId,
    address indexed assetOracle
  );

  /**
   * @notice Event is emitted whenever a configuration is removed.
   * @param hub `Hub` which configuration is removed
   * @param assetId Id of the `hub` asset which configuration is removed
   * @param umbrellaStake Address of `UmbrellaStakeToken`
   */
  event SlashingConfigurationRemoved(
    address indexed hub,
    uint256 indexed assetId,
    address indexed umbrellaStake
  );

  /**
   * @notice Event is emitted whenever a `spoke` is added to the coverage of a `hub` and `assetId` pair.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset for which the `spoke` deficit is tracked
   * @param spoke `Spoke` added to the coverage
   */
  event SpokeCoverageAdded(address indexed hub, uint256 indexed assetId, address indexed spoke);

  /**
   * @notice Event is emitted whenever a `spoke` is removed from the coverage of a `hub` and `assetId` pair.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset for which the `spoke` deficit was tracked
   * @param spoke `Spoke` removed from the coverage
   */
  event SpokeCoverageRemoved(address indexed hub, uint256 indexed assetId, address indexed spoke);

  /**
   * @notice Event is emitted whenever the `deficitOffset` of a `spoke` is changed.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset which `deficitOffset` is changed
   * @param spoke `Spoke` which `deficitOffset` is changed
   * @param newDeficitOffset New amount of `deficitOffset`
   */
  event DeficitOffsetChanged(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    uint256 newDeficitOffset
  );

  /**
   * @notice Event is emitted whenever the `pendingDeficit` of a `spoke` is changed.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset which `pendingDeficit` is changed
   * @param spoke `Spoke` which `pendingDeficit` is changed
   * @param newPendingDeficit New amount of `pendingDeficit`
   */
  event PendingDeficitChanged(
    address indexed hub,
    uint256 indexed assetId,
    address indexed spoke,
    uint256 newPendingDeficit
  );

  /**
   * @dev Attempted to set `UmbrellaStakeToken`, which is already set for another `hub` and `assetId` pair.
   */
  error UmbrellaStakeAlreadySetForAnotherAsset();

  /**
   * @dev Attempted to add `hub` to configuration, which isn't a valid `Hub`.
   */
  error InvalidHub();

  /**
   * @dev Attempted to add `assetId` to configuration, which isn't exist in the `Hub`.
   */
  error InvalidAsset();

  /**
   * @dev Attempted to configure asset and stake underlying oracles with different decimals.
   */
  error OracleDecimalsMismatch();

  /**
   * @dev Attempted to add `spoke` to the coverage, which isn't connected to the `hub`.
   */
  error InvalidSpoke();

  /**
   * @dev Attempted to add a `spoke` to the coverage of a `hub` and `assetId` pair for which this `Umbrella`
   * is not listed as a `spoke` itself, so a slashed deficit could never be eliminated.
   */
  error UmbrellaNotListedOnHub();

  /**
   * @dev Attempted to operate on a `hub` and `assetId` pair that does not have a slashing configuration.
   */
  error AssetCoverageNotSetup();

  /**
   * @dev Attempted to remove the last slashing configuration of a `hub` and `assetId` pair that still has
   * `spoke`s listed in its coverage.
   */
  error SpokesStillCovered();

  /**
   * @dev Attempted to track, slash or cover a deficit of a `spoke` that is not listed
   * in the coverage of this `hub` and `assetId` pair.
   */
  error SpokeNotCovered();

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Updates a set of slashing configurations.
   * @dev If the configs contain an already existing configuration, the configuration will be overwritten.
   * If install more than 1 configuration, then `slash` will not work in the current version.
   * A `spoke` cannot be covered before its pair is configured, so installing the first configuration of a
   * pair never turns an already reported deficit into a slashable one and leaves every `deficitOffset` alone.
   * The `umbrellaStake` underlying is expected to be the share token of the `TokenizationSpoke`
   * linked to the same `hub` and `assetId` pair.
   * @param slashingConfigs An array of configurations
   */
  function updateSlashingConfigs(SlashingConfigUpdate[] calldata slashingConfigs) external;

  /**
   * @notice Removes a set of slashing configurations.
   * @dev If such a config did not exist, the function does not revert.
   * Reverts if it would leave a `hub` and `assetId` pair without any configuration while `spoke`s are still
   * listed in its coverage, so a covered `spoke` can never outlive the configuration of its pair.
   * Removing the last configuration therefore requires `removeCoveredSpokes` to be called first, while
   * replacing a configuration should install the new one before removing the old one.
   * @param removalPairs An array of coverage tuples (hub:assetId:stk) to remove
   */
  function removeSlashingConfigs(SlashingConfigRemoval[] calldata removalPairs) external;

  /**
   * @notice Adds a set of `spoke`s to the coverage of their `hub` and `assetId` pair.
   * @dev Only deficit of a listed `spoke` is tracked and can be slashed or covered.
   * On addition the `deficitOffset` of the `spoke` is initialized with its current deficit,
   * so that a deficit accrued before the listing cannot be slashed. Listing is therefore the only way for a
   * `spoke` deficit to become slashable and requires the pair to already have a slashing configuration.
   * Reverts unless this `Umbrella` is listed as a `spoke` of the same `hub` and `assetId` pair,
   * as otherwise a slashed deficit could never be eliminated.
   * If such a `spoke` was already listed, the function does not revert.
   * @param spokes An array of coverage tuples (hub:assetId:spoke) to add
   */
  function addCoveredSpokes(SpokeCoverage[] calldata spokes) external;

  /**
   * @notice Removes a set of `spoke`s from the coverage of their `hub` and `assetId` pair.
   * @dev Once removed, a `spoke` deficit is no longer tracked and can neither be slashed nor covered.
   * If such a `spoke` was not listed, the function does not revert.
   * @param spokes An array of coverage tuples (hub:assetId:spoke) to remove
   */
  function removeCoveredSpokes(SpokeCoverage[] calldata spokes) external;

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns all the slashing configurations, configured for a given `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return An array of `SlashingConfig` structs
   */
  function getAssetSlashingConfigs(
    address hub,
    uint256 assetId
  ) external view returns (SlashingConfig[] memory);

  /**
   * @notice Returns the slashing configuration for a given `UmbrellaStakeToken` in regards to a specific `hub` and `assetId` pair.
   * @dev Reverts if `SlashingConfig` doesn't exist.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param umbrellaStake Address of the `UmbrellaStakeToken`
   * @return A `SlashingConfig` struct
   */
  function getAssetSlashingConfig(
    address hub,
    uint256 assetId,
    address umbrellaStake
  ) external view returns (SlashingConfig memory);

  /**
   * @notice Returns the oracle used to price the asset which deficit is covered.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return Address of the asset oracle
   */
  function getAssetOracle(address hub, uint256 assetId) external view returns (address);

  /**
   * @notice Returns all the `spoke`s listed in the coverage of a given `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return An array of `spoke` addresses
   */
  function getCoveredSpokes(address hub, uint256 assetId) external view returns (address[] memory);

  /**
   * @notice Returns whether a `spoke` is listed in the coverage of a given `hub` and `assetId` pair.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return True if the `spoke` deficit is tracked and covered by this `Umbrella`, false otherwise
   */
  function isSpokeCovered(address hub, uint256 assetId, address spoke) external view returns (bool);

  /**
   * @notice Returns if a `spoke` is currently slashable or not.
   * A `spoke` is slashable if:
   * - it is listed in the coverage of this `hub` and `assetId` pair
   * - there's only one stk configured for slashing
   * - if there is a non zero new deficit
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return flag If `Umbrella` could slash for a given `spoke`
   * @return amount Amount of the new deficit, by which `UmbrellaStakeToken` potentially could be slashed
   */
  function isSpokeSlashable(
    address hub,
    uint256 assetId,
    address spoke
  ) external view returns (bool flag, uint256 amount);

  /**
   * @notice Returns the amount of `spoke` deficit that can't be slashed using `UmbrellaStakeToken` funds.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return The amount of the `deficitOffset`
   */
  function getDeficitOffset(
    address hub,
    uint256 assetId,
    address spoke
  ) external view returns (uint256);

  /**
   * @notice Returns the amount of already slashed funds that have not yet been used for the `spoke` deficit elimination.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return The amount of funds pending for deficit elimination
   */
  function getPendingDeficit(
    address hub,
    uint256 assetId,
    address spoke
  ) external view returns (uint256);

  /**
   * @notice Returns the sum of the `deficitOffset` of every `spoke` listed in the coverage of a given `hub` and `assetId` pair.
   * @dev Iterates over the listed `spoke`s, so the cost grows with their number.
   * A `spoke` of the same `hub` and `assetId` pair that is not listed contributes nothing.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of the `deficitOffset` covered by this pair
   */
  function getTotalDeficitOffset(address hub, uint256 assetId) external view returns (uint256);

  /**
   * @notice Returns the sum of the `pendingDeficit` of every `spoke` listed in the coverage of a given `hub` and `assetId` pair.
   * @dev Iterates over the listed `spoke`s, so the cost grows with their number.
   * A `spoke` of the same `hub` and `assetId` pair that is not listed contributes nothing.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of funds pending for deficit elimination for this pair
   */
  function getTotalPendingDeficit(address hub, uint256 assetId) external view returns (uint256);

  /**
   * @notice Returns the sum of the new deficit of every `spoke` listed in the coverage of a given `hub` and `assetId` pair,
   * i.e. the total amount by which the `UmbrellaStakeToken` of this pair could currently be slashed.
   * @dev Iterates over the listed `spoke`s and reads the deficit of each one from the `hub`,
   * so the cost grows with their number.
   * A `spoke` of the same `hub` and `assetId` pair that is not listed contributes nothing.
   * Returns 0 unless the pair has exactly one `SlashingConfig`, since slashing is not possible otherwise.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of the new deficit slashable for this pair
   */
  function getTotalSlashableDeficit(address hub, uint256 assetId) external view returns (uint256);

  /**
   * @notice Returns the `StakeTokenData` of the `umbrellaStake`.
   * @param umbrellaStake Address of the `UmbrellaStakeToken`
   * @return stakeTokenData A `StakeTokenData` struct
   */
  function getStakeTokenData(
    address umbrellaStake
  ) external view returns (StakeTokenData memory stakeTokenData);
}
