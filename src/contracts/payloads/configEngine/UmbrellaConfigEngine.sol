// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import {IRescuableBase, RescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';
import {Rescuable} from 'solidity-utils/contracts/utils/Rescuable.sol';

import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from '../IUmbrellaEngineStructs.sol';
import {IUmbrellaEngineStructs as IStructs, IRewardsStructs as IRStructs} from '../IUmbrellaEngineStructs.sol';

import {IUmbrellaConfigEngine} from './IUmbrellaConfigEngine.sol';

import {EngineUtils} from '../utils/EngineUtils.sol';

import {IUmbrella} from '../../umbrella/interfaces/IUmbrella.sol';

import {IRewardsController} from '../../rewards/interfaces/IRewardsController.sol';

/**
 * @dev Helper smart contract performing actions using internal libraries.
 *
 * ***IMPORTANT*** This engine MUST BE STATELESS always.
 *
 * Assumptions:
 *   - Only one `RewardsController` per network
 *   - Only one `Umbrella` per `Pool`
 *   - For each `Umbrella` separate `UmbrellaConfigEngine` will be deployed
 *
 * @author BGD Labs
 */
contract UmbrellaConfigEngine is Rescuable, IUmbrellaConfigEngine {
  using SafeERC20 for IERC20;

  address public immutable REWARDS_CONTROLLER;
  address public immutable RESCUE_GUARDIAN;
  address public immutable UMBRELLA;

  constructor(address rewardsController, address umbrella, address guardian) {
    require(
      rewardsController != address(0) && umbrella != address(0) && guardian != address(0),
      ZeroAddress()
    );

    REWARDS_CONTROLLER = rewardsController;
    RESCUE_GUARDIAN = guardian;
    UMBRELLA = umbrella;
  }

  /// Functions for basic and extended payloads
  /////////////////////////////////////////////////////////////////////////////////////////

  /// Umbrella
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeCreateTokens(
    ISMStructs.StakeTokenSetup[] memory configs
  ) public returns (address[] memory) {
    return IUmbrella(UMBRELLA).createStakeTokens(configs);
  }

  function executeUpdateUnstakeConfigs(IStructs.UnstakeConfig[] memory configs) public {
    (
      ISMStructs.UnstakeWindowConfig[] memory unstakeWindowConfigs,
      ISMStructs.CooldownConfig[] memory cooldownConfigs
    ) = EngineUtils.repackUnstakeStructs(configs);

    executeChangeUnstakeWindows(unstakeWindowConfigs);
    executeChangeCooldowns(cooldownConfigs);
  }

  function executeChangeCooldowns(ISMStructs.CooldownConfig[] memory configs) public {
    IUmbrella(UMBRELLA).setCooldownStk(configs);
  }

  function executeChangeUnstakeWindows(ISMStructs.UnstakeWindowConfig[] memory configs) public {
    IUmbrella(UMBRELLA).setUnstakeWindowStk(configs);
  }

  function executeRemoveSlashingConfigs(ICStructs.SlashingConfigRemoval[] memory configs) public {
    IUmbrella(UMBRELLA).removeSlashingConfigs(configs);
  }

  function executeUpdateSlashingConfigs(ICStructs.SlashingConfigUpdate[] memory configs) public {
    IUmbrella(UMBRELLA).updateSlashingConfigs(configs);
  }

  function executeSetDeficitOffsets(IStructs.SetDeficitOffset[] memory configs) public {
    for (uint256 i; i < configs.length; ++i) {
      IUmbrella(UMBRELLA).setDeficitOffset(configs[i].reserve, configs[i].newDeficitOffset);
    }
  }

  function executeCoverPendingDeficits(IStructs.CoverDeficit[] memory configs) public {
    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].approve) {
        _approveBeforeCoverage(configs[i].reserve, configs[i].amount);
      }

      IUmbrella(UMBRELLA).coverPendingDeficit(configs[i].reserve, configs[i].amount);
    }
  }

  function executeCoverDeficitOffsets(IStructs.CoverDeficit[] memory configs) public {
    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].approve) {
        _approveBeforeCoverage(configs[i].reserve, configs[i].amount);
      }

      IUmbrella(UMBRELLA).coverDeficitOffset(configs[i].reserve, configs[i].amount);
    }
  }

  function executeCoverReserveDeficits(IStructs.CoverDeficit[] memory configs) public {
    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].approve) {
        _approveBeforeCoverage(configs[i].reserve, configs[i].amount);
      }

      IUmbrella(UMBRELLA).coverReserveDeficit(configs[i].reserve, configs[i].amount);
    }
  }

  /// RewardsController
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeConfigureStakesAndRewards(
    IStructs.ConfigureStakeAndRewardsConfig[] memory configs
  ) public {
    for (uint256 i; i < configs.length; ++i) {
      configs[i].targetLiquidity = EngineUtils.getTargetLiquidity(
        configs[i].umbrellaStake,
        configs[i].targetLiquidity,
        REWARDS_CONTROLLER
      );

      EngineUtils.repackRewardConfigs(
        configs[i].rewardConfigs,
        configs[i].umbrellaStake,
        REWARDS_CONTROLLER
      );

      IRewardsController(REWARDS_CONTROLLER).configureAssetWithRewards(
        configs[i].umbrellaStake,
        configs[i].targetLiquidity,
        configs[i].rewardConfigs
      );
    }
  }

  function executeConfigureRewards(IStructs.ConfigureRewardsConfig[] memory configs) public {
    for (uint256 i; i < configs.length; ++i) {
      EngineUtils.repackRewardConfigs(
        configs[i].rewardConfigs,
        configs[i].umbrellaStake,
        REWARDS_CONTROLLER
      );

      IRewardsController(REWARDS_CONTROLLER).configureRewards(
        configs[i].umbrellaStake,
        configs[i].rewardConfigs
      );
    }
  }

  /// Functions for extended payloads
  /////////////////////////////////////////////////////////////////////////////////////////

  function executeComplexRemovals(IStructs.TokenRemoval[] memory configs) public {
    (
      ICStructs.SlashingConfigRemoval[] memory slashingConfigs,
      IStructs.ConfigureRewardsConfig[] memory rewardsConfigs
    ) = EngineUtils.repackRemovalStructs(configs, REWARDS_CONTROLLER, UMBRELLA);

    executeRemoveSlashingConfigs(slashingConfigs);
    executeConfigureRewards(rewardsConfigs);

    (
      ISMStructs.UnstakeWindowConfig[] memory unstakeWindowConfigs,
      ISMStructs.CooldownConfig[] memory cooldownConfigs
    ) = EngineUtils.repackInstantUnstakeStructs(configs);

    executeChangeUnstakeWindows(unstakeWindowConfigs);
    executeChangeCooldowns(cooldownConfigs);
  }

  function executeComplexCreations(IStructs.TokenSetup[] memory configs) public {
    address[] memory createdTokens = executeCreateTokens(EngineUtils.repackCreateStructs(configs));

    (
      ICStructs.SlashingConfigUpdate[] memory slashingConfigs,
      IStructs.ConfigureStakeAndRewardsConfig[] memory rewardConfigs
    ) = EngineUtils.repackInitStructs(configs, createdTokens);

    executeUpdateSlashingConfigs(slashingConfigs);
    executeConfigureStakesAndRewards(rewardConfigs);

    executeSetDeficitOffsets(EngineUtils.repackDeficitIncreaseStructs(configs, UMBRELLA));
  }

  /////////////////////////////////////////////////////////////////////////////////////////

  function whoCanRescue() public view override returns (address) {
    return RESCUE_GUARDIAN;
  }

  function maxRescue(
    address
  ) public pure override(IRescuableBase, RescuableBase) returns (uint256) {
    return type(uint256).max;
  }

  /////////////////////////////////////////////////////////////////////////////////////////

  function _approveBeforeCoverage(address reserve, uint256 amount) internal {
    address tokenForCoverage = IUmbrella(UMBRELLA).tokenForDeficitCoverage(reserve);

    IERC20(tokenForCoverage).forceApprove(UMBRELLA, amount);
  }
}
