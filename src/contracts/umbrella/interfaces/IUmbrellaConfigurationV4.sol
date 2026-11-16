// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {EnumerableMap} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableMap.sol';
import {EnumerableSet} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol';

import {IUmbrellaConfigurationBase} from './IUmbrellaConfigurationBase.sol';

interface IUmbrellaConfigurationV4 is IUmbrellaConfigurationBase {
  struct SlashingConfigUpdate {
    /// @notice `Hub` which configuration should be updated
    address hub;
    /// @notice Id of the `hub` asset which configuration should be updated
    uint256 assetId;
    /// @notice Address of `UmbrellaStakeToken` that should be set for this hub asset
    address umbrellaStake;
    /// @notice Percentage of funds slashed on top of the new deficit
    uint256 liquidationFee;
    /// @notice Oracle of `UmbrellaStakeToken`s underlying
    address umbrellaStakeUnderlyingOracle;
  }

  struct SlashingConfigRemoval {
    /// @notice `Hub` which configuration is being removed
    address hub;
    /// @notice Id of the `hub` asset which configuration is being removed
    uint256 assetId;
    /// @notice Address of `UmbrellaStakeToken` that will be removed from this hub asset
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
    address underlyingOracle;
    /// @notice Whether the `SlashingConfig` of this `UmbrellaStakeToken` has been removed
    bool deactivated;
    /// @notice `Hub` for which this `UmbrellaStakeToken` is configured
    address hub;
    /// @notice Id of the `hub` asset for which this `UmbrellaStakeToken` is configured
    /// @dev Narrowed to `uint96`, so that it shares a storage slot with `hub`
    uint96 assetId;
  }

  struct SpokeData {
    /// @notice Initial deficit (cannot be covered by funds taken from Umbrella users)
    uint256 deficitOffset;
    /// @notice Deficit on top of `deficitOffset` (already slashed and waiting to be covered by Umbrella)
    uint256 pendingDeficit;
    /// @notice Whether the `spoke` has been removed from the coverage of its hub asset
    bool deactivated;
  }

  struct AssetData {
    /// @notice Map with `UmbrellaStakeToken`s for this hub asset and their `liquidationFee`
    EnumerableMap.AddressToUintMap configurationMap;
    /// @notice Set of `spoke`s ever listed in the coverage of this hub asset
    EnumerableSet.AddressSet listedSpokes;
    /// @notice Map of `spoke` addresses and their tracked deficit
    mapping(address spoke => SpokeData) spokesData;
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
   * @notice Event is emitted whenever a `spoke` is added to the coverage of a hub asset.
   * @param hub `Hub` to which the `spoke` is connected
   * @param assetId Id of the `hub` asset for which the `spoke` deficit is tracked
   * @param spoke `Spoke` added to the coverage
   */
  event SpokeCoverageAdded(address indexed hub, uint256 indexed assetId, address indexed spoke);

  /**
   * @notice Event is emitted whenever a `spoke` is removed from the coverage of a hub asset.
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
   * @dev Attempted to set `UmbrellaStakeToken`, which is already set for another hub asset.
   */
  error UmbrellaStakeAlreadySetForAnotherAsset();

  /**
   * @dev Attempted to add `assetId` to configuration, which doesn't exist in the `Hub`.
   */
  error InvalidAsset();

  /**
   * @dev Attempted to set an oracle that doesn't report prices with the decimals of the `Spoke` oracles.
   */
  error OracleDecimalsMismatch();

  /**
   * @dev Attempted to add `spoke` to the coverage, which isn't connected to the `hub`.
   * A `spoke` without a reserve for the asset reverts on its own.
   */
  error InvalidSpoke();

  /**
   * @dev Attempted to add a `spoke` to the coverage of a hub asset for which this `Umbrella`
   * is not listed as a `spoke` itself, so a slashed deficit could never be eliminated.
   */
  error UmbrellaNotListedOnHub();

  /**
   * @dev Attempted to operate on a hub asset that does not have a slashing configuration.
   */
  error AssetCoverageNotSetup();

  /**
   * @dev Attempted to change the `deficitOffset` of a `spoke` that is not covered by this hub asset.
   */
  error SpokeNotCovered();

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Updates a set of slashing configurations.
   * @dev If the configs contain an already existing configuration, the configuration will be overwritten.
   * If install more than 1 configuration, then `slash` will not work in the current version.
   * When the first configuration of a hub asset is installed, the `deficitOffset` of every `spoke` it covers
   * is initialized with its current deficit, so that a deficit accrued before cannot be slashed.
   * The `umbrellaStake` underlying is expected to be the share token of the `TokenizationSpoke`
   * linked to the same hub asset. Its oracle must report prices with the decimals of the `Spoke` oracles,
   * since the covered asset is priced by the oracle of the `spoke` which deficit is slashed.
   * @param slashingConfigs An array of configurations
   */
  function updateSlashingConfigs(SlashingConfigUpdate[] calldata slashingConfigs) external;

  /**
   * @notice Removes a set of slashing configurations.
   * @dev If such a config did not exist, the function does not revert.
   * Pending and offset deficits of the covered `spoke`s are not modified.
   * @param removalPairs An array of coverage tuples (hub:assetId:stk) to remove
   */
  function removeSlashingConfigs(SlashingConfigRemoval[] calldata removalPairs) external;

  /**
   * @notice Adds a set of `spoke`s to the coverage of their hub asset.
   * @dev Only deficit of a covered `spoke` is tracked and can be slashed or covered.
   * On addition the `deficitOffset` of the `spoke` is initialized with its current deficit, so that a deficit
   * accrued before the coverage cannot be slashed.
   * The `spoke` must have a reserve for the asset, since its oracle prices the asset when slashing.
   * Reverts unless this `Umbrella` is listed as a `spoke` of the same hub asset,
   * as otherwise a slashed deficit could never be eliminated.
   * If such a `spoke` was already covered, the function does not revert.
   * @param spokes An array of coverage tuples (hub:assetId:spoke) to add
   */
  function addCoveredSpokes(SpokeCoverage[] calldata spokes) external;

  /**
   * @notice Removes a set of `spoke`s from the coverage of their hub asset.
   * @dev Once removed, a `spoke` is flagged as deactivated and its deficit can no longer be slashed.
   * Its `deficitOffset` and `pendingDeficit` are kept and can still be covered, and a re-addition of the same
   * `spoke` takes the funds already slashed for it into account.
   * If such a `spoke` was not covered, the function does not revert.
   * @param spokes An array of coverage tuples (hub:assetId:spoke) to remove
   */
  function removeCoveredSpokes(SpokeCoverage[] calldata spokes) external;

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Returns all the slashing configurations, configured for a given hub asset.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return An array of `SlashingConfig` structs
   */
  function getAssetSlashingConfigs(
    address hub,
    uint256 assetId
  ) external view returns (SlashingConfig[] memory);

  /**
   * @notice Returns the slashing configuration for a given `UmbrellaStakeToken` in regards to a specific hub asset.
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
   * @notice Returns all the `spoke`s currently covered by a given hub asset.
   * @dev Deactivated `spoke`s are not returned.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return An array of `spoke` addresses
   */
  function getCoveredSpokes(address hub, uint256 assetId) external view returns (address[] memory);

  /**
   * @notice Returns whether a `spoke` is covered by a given hub asset.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @param spoke Address of the `spoke`
   * @return True if the `spoke` deficit is tracked and covered by this `Umbrella`, false otherwise
   */
  function isSpokeCovered(address hub, uint256 assetId, address spoke) external view returns (bool);

  /**
   * @notice Returns if a `spoke` is currently slashable or not.
   * A `spoke` is slashable if:
   * - it is covered by this hub asset
   * - the hub asset has exactly one `SlashingConfig`, since slashing a basket of `UmbrellaStakeToken`s
   *   is not supported in the current version
   * - the deficit the `spoke` reports on the `hub` exceeds its `deficitOffset` and `pendingDeficit`,
   *   i.e. part of it is neither excluded from coverage nor already slashed for
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
   * @notice Returns the sum of the `deficitOffset` of every `spoke` covered by a given hub asset.
   * @dev Iterates over the covered `spoke`s, so the cost grows with their number.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of the `deficitOffset` covered by this hub asset
   */
  function getTotalDeficitOffset(address hub, uint256 assetId) external view returns (uint256);

  /**
   * @notice Returns the sum of the `pendingDeficit` of every `spoke` covered by a given hub asset.
   * @dev Iterates over the covered `spoke`s, so the cost grows with their number.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of funds pending for deficit elimination for this hub asset
   */
  function getTotalPendingDeficit(address hub, uint256 assetId) external view returns (uint256);

  /**
   * @notice Returns the sum of the new deficit of every `spoke` covered by a given hub asset,
   * i.e. the total amount by which the `UmbrellaStakeToken` of this hub asset could currently be slashed.
   * @dev Iterates over the covered `spoke`s and reads the deficit of each one from the `hub`,
   * so the cost grows with their number.
   * Returns 0 unless the hub asset has exactly one `SlashingConfig`, since slashing is not possible otherwise.
   * @param hub Address of the `Hub`
   * @param assetId Id of the asset
   * @return The total amount of the new deficit slashable for this hub asset
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
