// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaEngineStructs as IStructs} from '../IUmbrellaEngineStructs.sol';
import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from '../IUmbrellaEngineStructs.sol';

/**
 * @title IUmbrellaConfigEngine interface
 * @notice Interface to define functions that can be called from `UmbrellaBasePayload` and `UmbrellaExtendedPayload`.
 * @author BGD labs
 */
interface IUmbrellaConfigEngine {
  /// @dev Attempted to set zero address as parameter.
  error ZeroAddress();

  /// Umbrella
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeCreateTokens(
    ISMStructs.StakeTokenSetup[] memory configs
  ) external returns (address[] memory);

  function executeUpdateUnstakeConfigs(IStructs.UnstakeConfig[] memory configs) external;

  function executeChangeCooldowns(ISMStructs.CooldownConfig[] memory configs) external;

  function executeChangeUnstakeWindows(ISMStructs.UnstakeWindowConfig[] memory configs) external;

  function executeRemoveSlashingConfigs(ICStructs.SlashingConfigRemoval[] memory configs) external;

  function executeUpdateSlashingConfigs(ICStructs.SlashingConfigUpdate[] memory configs) external;

  function executeSetDeficitOffsets(IStructs.SetDeficitOffset[] memory configs) external;

  function executeCoverPendingDeficits(IStructs.CoverDeficit[] memory configs) external;

  function executeCoverDeficitOffsets(IStructs.CoverDeficit[] memory configs) external;

  function executeCoverReserveDeficits(IStructs.CoverDeficit[] memory configs) external;

  /// RewardsController
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeConfigureStakesAndRewards(
    IStructs.ConfigureStakeAndRewardsConfig[] memory configs
  ) external;

  function executeConfigureRewards(IStructs.ConfigureRewardsConfig[] memory configs) external;

  /// Functions for extended payloads
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeComplexRemovals(IStructs.TokenRemoval[] memory configs) external;

  function executeComplexCreations(IStructs.TokenSetup[] memory configs) external;

  /////////////////////////////////////////////////////////////////////////////////////////
}
