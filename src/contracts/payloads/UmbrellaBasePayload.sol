// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

import {IUmbrellaEngineStructs as IStructs} from './IUmbrellaEngineStructs.sol';
import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from './IUmbrellaEngineStructs.sol';

import {IUmbrellaConfigEngine as IEngine} from './configEngine/IUmbrellaConfigEngine.sol';

/**
 * @title UmbrellaBasePayload
 * @notice A contract for manually configuring the whole Umbrella system.
 * @dev Includes all governance-required calls.
 * To make additional actions (e.g., pausing or asset rescue), override `_preExecute` or `_postExecute`.
 *
 * ***IMPORTANT*** Payload inheriting this `UmbrellaBasePayload` MUST BE STATELESS always.
 *
 * At this moment payload covering:
 *   - `UmbrellaStakeToken`s creation
 *   - Updates of `cooldown`s
 *   - Updates of `unstakeWindow`s
 *   - Removals of `SlashingConfigs`s
 *   - Updates of `SlashingConfig`s
 *   - Updates of `deficitOffset`s
 *   - Covering of `pendingDeficit`s
 *   - Covering of `deficitOffset`s
 *   - Configuration of `reward`s (with and without `targetLiquidity`)
 *
 * @author BGD labs
 */
abstract contract UmbrellaBasePayload {
  using Address for address;

  /// @notice Address of `UmbrellaConfigEngine` for concrete `Pool`
  address public immutable ENGINE;

  /// @dev Attempted to set zero address as parameter.
  error ZeroAddress();

  constructor(address umbrellaConfigEngine) {
    if (umbrellaConfigEngine == address(0)) {
      revert ZeroAddress();
    }

    ENGINE = umbrellaConfigEngine;
  }

  function execute() external virtual {
    _preExecute();

    _umbrellaPayload();

    _rewardsControllerPayload();

    _extendedExecute();

    _postExecute();
  }

  /// @dev Functions to be overridden on the child
  /////////////////////////////////////////////////////////////////////////////////////////

  function _preExecute() internal virtual {}

  function _extendedExecute() internal virtual {}

  function _postExecute() internal virtual {}

  /// Umbrella
  /////////////////////////////////////////////////////////////////////////////////////////

  function createStkTokens() public view virtual returns (ISMStructs.StakeTokenSetup[] memory) {}

  function updateUnstakeConfig() public view virtual returns (IStructs.UnstakeConfig[] memory) {}

  function removeSlashingConfigs()
    public
    view
    virtual
    returns (ICStructs.SlashingConfigRemoval[] memory)
  {}

  function updateSlashingConfigs()
    public
    view
    virtual
    returns (ICStructs.SlashingConfigUpdate[] memory)
  {}

  function setDeficitOffset() public view virtual returns (IStructs.SetDeficitOffset[] memory) {}

  function coverPendingDeficit() public view virtual returns (IStructs.CoverDeficit[] memory) {}

  function coverDeficitOffset() public view virtual returns (IStructs.CoverDeficit[] memory) {}

  function coverReserveDeficit() public view virtual returns (IStructs.CoverDeficit[] memory) {}

  /// RewardsController
  /////////////////////////////////////////////////////////////////////////////////////////

  function configureStakeAndRewards()
    public
    view
    virtual
    returns (IStructs.ConfigureStakeAndRewardsConfig[] memory)
  {}

  function configureRewards()
    public
    view
    virtual
    returns (IStructs.ConfigureRewardsConfig[] memory)
  {}

  /////////////////////////////////////////////////////////////////////////////////////////

  function _umbrellaPayload() internal {
    // `coverReserveDeficit` to cover existing deficit in pool for reserve without `SlashingConfig` or before its setup,
    // otherwise `coverDeficitOffset` should be used
    IStructs.CoverDeficit[] memory coverReserveDeficitConfigs = coverReserveDeficit();
    if (coverReserveDeficitConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(
          IEngine.executeCoverReserveDeficits.selector,
          coverReserveDeficitConfigs
        )
      );
    }

    // if tokens are created and modified inside this basic payload, then their addresses should be predicted manually
    ISMStructs.StakeTokenSetup[] memory createTokens = createStkTokens();
    if (createTokens.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeCreateTokens.selector, createTokens)
      );
    }

    IStructs.UnstakeConfig[] memory unstakeConfigs = updateUnstakeConfig();
    if (unstakeConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeUpdateUnstakeConfigs.selector, unstakeConfigs)
      );
    }

    // Need to call remove slashing config before update due to edge case (Limitations in Umbrella README)
    ICStructs.SlashingConfigRemoval[] memory removeConfigs = removeSlashingConfigs();
    if (removeConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeRemoveSlashingConfigs.selector, removeConfigs)
      );
    }

    ICStructs.SlashingConfigUpdate[] memory updateConfigs = updateSlashingConfigs();
    if (updateConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeUpdateSlashingConfigs.selector, updateConfigs)
      );
    }

    IStructs.SetDeficitOffset[] memory setDeficitOffsetConfigs = setDeficitOffset();
    if (setDeficitOffsetConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeSetDeficitOffsets.selector, setDeficitOffsetConfigs)
      );
    }

    IStructs.CoverDeficit[] memory coverPendingDeficitConfigs = coverPendingDeficit();
    if (coverPendingDeficitConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(
          IEngine.executeCoverPendingDeficits.selector,
          coverPendingDeficitConfigs
        )
      );
    }

    IStructs.CoverDeficit[] memory coverDeficitOffsetConfigs = coverDeficitOffset();
    if (coverDeficitOffsetConfigs.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(
          IEngine.executeCoverDeficitOffsets.selector,
          coverDeficitOffsetConfigs
        )
      );
    }
  }

  function _rewardsControllerPayload() internal {
    IStructs.ConfigureStakeAndRewardsConfig[]
      memory configsForStakesAndRewards = configureStakeAndRewards();
    if (configsForStakesAndRewards.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(
          IEngine.executeConfigureStakesAndRewards.selector,
          configsForStakesAndRewards
        )
      );
    }

    IStructs.ConfigureRewardsConfig[] memory configsForRewards = configureRewards();
    if (configsForRewards.length != 0) {
      ENGINE.functionDelegateCall(
        abi.encodeWithSelector(IEngine.executeConfigureRewards.selector, configsForRewards)
      );
    }
  }
}
