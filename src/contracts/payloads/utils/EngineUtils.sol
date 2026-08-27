// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from '../IUmbrellaEngineStructs.sol';
import {IUmbrellaEngineStructs as IStructs, IRewardsStructs as IRStructs} from '../IUmbrellaEngineStructs.sol';

import {EngineFlags} from '../EngineFlags.sol';

import {IUmbrella} from '../../umbrella/interfaces/IUmbrella.sol';
import {IRewardsController} from '../../rewards/interfaces/IRewardsController.sol';

library EngineUtils {
  function getTargetLiquidity(
    address umbrellaStake,
    uint256 targetLiquidity,
    address rewardsController
  ) internal view returns (uint256) {
    if (targetLiquidity == EngineFlags.KEEP_CURRENT) {
      targetLiquidity = IRewardsController(rewardsController)
        .getAssetData(umbrellaStake)
        .targetLiquidity;
    }

    return targetLiquidity;
  }

  function repackRewardConfigs(
    IRStructs.RewardSetupConfig[] memory configs,
    address umbrellaStake,
    address rewardsController
  ) internal view {
    for (uint256 i; i < configs.length; ++i) {
      bool getEmission = configs[i].maxEmissionPerSecond == EngineFlags.KEEP_CURRENT;
      bool getDistribution = configs[i].distributionEnd == EngineFlags.KEEP_CURRENT;

      if (getEmission || getDistribution) {
        IRStructs.RewardDataExternal memory rewardData = IRewardsController(rewardsController)
          .getRewardData(umbrellaStake, configs[i].reward);

        if (getEmission) {
          configs[i].maxEmissionPerSecond = rewardData.maxEmissionPerSecond;
        }

        if (getDistribution) {
          configs[i].distributionEnd = rewardData.distributionEnd;
        }
      }
    }
  }

  function repackRemovalStructs(
    IStructs.TokenRemoval[] memory configs,
    address rewardsController,
    address umbrella
  )
    internal
    view
    returns (ICStructs.SlashingConfigRemoval[] memory, IStructs.ConfigureRewardsConfig[] memory)
  {
    IStructs.ConfigureRewardsConfig[]
      memory removeRewardsConfigs = new IStructs.ConfigureRewardsConfig[](configs.length);

    ICStructs.SlashingConfigRemoval[]
      memory removeSlashingConfigs = new ICStructs.SlashingConfigRemoval[](configs.length);

    for (uint256 i; i < configs.length; ++i) {
      removeRewardsConfigs[i] = repackRewardsRemovalStructs(configs[i], rewardsController);
      removeSlashingConfigs[i] = repackSlashingConfigRemovalStructs(
        configs[i].umbrellaStake,
        umbrella
      );
    }

    deleteStakesWithEmptyRewards(removeRewardsConfigs);

    return (removeSlashingConfigs, removeRewardsConfigs);
  }

  function repackDeficitIncreaseStructs(
    IStructs.TokenSetup[] memory configs,
    address umbrella
  ) internal view returns (IStructs.SetDeficitOffset[] memory) {
    IStructs.SetDeficitOffset[]
      memory deficitOffsetIncreaseConfigs = new IStructs.SetDeficitOffset[](configs.length);

    uint256 deficitOffsetIncreaseArrayLength;

    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].deficitOffsetIncrease != 0) {
        uint256 currentDeficitOffset = IUmbrella(umbrella).getDeficitOffset(configs[i].reserve);

        deficitOffsetIncreaseConfigs[deficitOffsetIncreaseArrayLength++] = IStructs
          .SetDeficitOffset({
            reserve: configs[i].reserve,
            newDeficitOffset: configs[i].deficitOffsetIncrease + currentDeficitOffset
          });
      }
    }

    assembly {
      mstore(deficitOffsetIncreaseConfigs, deficitOffsetIncreaseArrayLength)
    }

    return deficitOffsetIncreaseConfigs;
  }

  function repackRewardsRemovalStructs(
    IStructs.TokenRemoval memory tokenRemoval,
    address rewardsController
  ) internal view returns (IStructs.ConfigureRewardsConfig memory) {
    (, IRStructs.RewardDataExternal[] memory rewardsData) = IRewardsController(rewardsController)
      .getAssetAndRewardsData(tokenRemoval.umbrellaStake);

    IRStructs.RewardSetupConfig[] memory rewardsRemoval = new IRStructs.RewardSetupConfig[](
      rewardsData.length
    );

    uint256 numberOfActiveRewards;

    for (uint256 i; i < rewardsData.length; ++i) {
      if (
        rewardsData[i].maxEmissionPerSecond == 0 ||
        rewardsData[i].distributionEnd <= block.timestamp
      ) {
        continue;
      }

      rewardsRemoval[numberOfActiveRewards++] = IRStructs.RewardSetupConfig({
        reward: rewardsData[i].addr,
        rewardPayer: tokenRemoval.residualRewardPayer,
        maxEmissionPerSecond: 0,
        distributionEnd: block.timestamp
      });
    }

    assembly {
      mstore(rewardsRemoval, numberOfActiveRewards)
    }

    return
      IStructs.ConfigureRewardsConfig({
        umbrellaStake: tokenRemoval.umbrellaStake,
        rewardConfigs: rewardsRemoval
      });
  }

  function repackSlashingConfigRemovalStructs(
    address umbrellaStake,
    address umbrella
  ) internal view returns (ICStructs.SlashingConfigRemoval memory) {
    ICStructs.StakeTokenData memory data = IUmbrella(umbrella).getStakeTokenData(umbrellaStake);

    return ICStructs.SlashingConfigRemoval({reserve: data.reserve, umbrellaStake: umbrellaStake});
  }

  function repackUnstakeStructs(
    IStructs.UnstakeConfig[] memory configs
  )
    internal
    pure
    returns (ISMStructs.UnstakeWindowConfig[] memory, ISMStructs.CooldownConfig[] memory)
  {
    ISMStructs.UnstakeWindowConfig[] memory unstakeConfigs = new ISMStructs.UnstakeWindowConfig[](
      configs.length
    );
    ISMStructs.CooldownConfig[] memory cooldownConfigs = new ISMStructs.CooldownConfig[](
      configs.length
    );

    uint256 unstakeConfigsToChange;
    uint256 cooldownConfigsToChange;

    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].newUnstakeWindow != EngineFlags.KEEP_CURRENT) {
        unstakeConfigs[unstakeConfigsToChange++] = ISMStructs.UnstakeWindowConfig({
          umbrellaStake: configs[i].umbrellaStake,
          newUnstakeWindow: configs[i].newUnstakeWindow
        });
      }

      if (configs[i].newCooldown != EngineFlags.KEEP_CURRENT) {
        cooldownConfigs[cooldownConfigsToChange++] = ISMStructs.CooldownConfig({
          umbrellaStake: configs[i].umbrellaStake,
          newCooldown: configs[i].newCooldown
        });
      }
    }

    assembly {
      mstore(unstakeConfigs, unstakeConfigsToChange)
      mstore(cooldownConfigs, cooldownConfigsToChange)
    }

    return (unstakeConfigs, cooldownConfigs);
  }

  function repackInstantUnstakeStructs(
    IStructs.TokenRemoval[] memory configs
  )
    internal
    pure
    returns (ISMStructs.UnstakeWindowConfig[] memory, ISMStructs.CooldownConfig[] memory)
  {
    ISMStructs.UnstakeWindowConfig[] memory unstakeConfigs = new ISMStructs.UnstakeWindowConfig[](
      configs.length
    );
    ISMStructs.CooldownConfig[] memory cooldownConfigs = new ISMStructs.CooldownConfig[](
      configs.length
    );

    for (uint256 i; i < configs.length; ++i) {
      unstakeConfigs[i] = ISMStructs.UnstakeWindowConfig({
        umbrellaStake: configs[i].umbrellaStake,
        newUnstakeWindow: type(uint32).max
      });

      cooldownConfigs[i] = ISMStructs.CooldownConfig({
        umbrellaStake: configs[i].umbrellaStake,
        newCooldown: 0
      });
    }

    return (unstakeConfigs, cooldownConfigs);
  }

  function repackCreateStructs(
    IStructs.TokenSetup[] memory configs
  ) internal pure returns (ISMStructs.StakeTokenSetup[] memory) {
    ISMStructs.StakeTokenSetup[] memory createStkConfigs = new ISMStructs.StakeTokenSetup[](
      configs.length
    );

    for (uint256 i; i < configs.length; ++i) {
      createStkConfigs[i] = configs[i].stakeSetup;
    }

    return createStkConfigs;
  }

  function repackInitStructs(
    IStructs.TokenSetup[] memory configs,
    address[] memory createdTokens
  )
    internal
    pure
    returns (
      ICStructs.SlashingConfigUpdate[] memory,
      IStructs.ConfigureStakeAndRewardsConfig[] memory
    )
  {
    ICStructs.SlashingConfigUpdate[]
      memory initSlashingConfigs = new ICStructs.SlashingConfigUpdate[](configs.length);

    IStructs.ConfigureStakeAndRewardsConfig[]
      memory configsForStakesAndRewards = new IStructs.ConfigureStakeAndRewardsConfig[](
        configs.length
      );

    for (uint256 i; i < configs.length; ++i) {
      initSlashingConfigs[i] = ICStructs.SlashingConfigUpdate({
        reserve: configs[i].reserve,
        umbrellaStake: createdTokens[i],
        liquidationFee: configs[i].liquidationFee,
        umbrellaStakeUnderlyingOracle: configs[i].umbrellaStakeUnderlyingOracle
      });

      configsForStakesAndRewards[i] = IStructs.ConfigureStakeAndRewardsConfig({
        umbrellaStake: createdTokens[i],
        targetLiquidity: configs[i].targetLiquidity,
        rewardConfigs: configs[i].rewardConfigs
      });
    }

    return (initSlashingConfigs, configsForStakesAndRewards);
  }

  function deleteStakesWithEmptyRewards(
    IStructs.ConfigureRewardsConfig[] memory configs
  ) internal pure {
    uint256 numberOfConfigs;

    for (uint256 i; i < configs.length; ++i) {
      if (configs[i].rewardConfigs.length == 0) {
        continue;
      }

      configs[numberOfConfigs++] = configs[i];
    }

    assembly {
      mstore(configs, numberOfConfigs)
    }
  }
}
