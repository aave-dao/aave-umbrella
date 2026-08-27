// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaStkManager} from '../umbrella/interfaces/IUmbrellaStkManager.sol';
import {IUmbrellaConfiguration} from '../umbrella/interfaces/IUmbrellaConfiguration.sol';

import {IRewardsStructs} from '../rewards/interfaces/IRewardsStructs.sol';

/**
 * @title IUmbrellaEngineStructs interface
 * @notice An interface containing structures that can be used externally.
 * @author BGD labs
 */
interface IUmbrellaEngineStructs {
  /// Umbrella
  /////////////////////////////////////////////////////////////////////////////////////////

  struct UnstakeConfig {
    /// @notice Address of the `UmbrellaStakeToken` to be configured
    address umbrellaStake;
    /// @notice New duration of `cooldown` to be set (could be set as `KEEP_CURRENT`)
    uint256 newCooldown;
    /// @notice New duration of `unstakeWindow` to be set (could be set as `KEEP_CURRENT`)
    uint256 newUnstakeWindow;
  }

  struct SetDeficitOffset {
    /// @notice Reserve address
    address reserve;
    /// @notice New amount of `deficitOffset` to set for this reserve
    uint256 newDeficitOffset;
  }

  struct CoverDeficit {
    /// @notice Reserve address
    address reserve;
    /// @notice Amount of `aToken`s (or reserve) to be eliminated
    uint256 amount;
    /// @notice True - make `forceApprove` for required amount of tokens, false - skip
    bool approve;
  }

  /// RewardsController
  /////////////////////////////////////////////////////////////////////////////////////////

  struct ConfigureStakeAndRewardsConfig {
    /// @notice Address of the `asset` to be configured/initialized
    address umbrellaStake;
    /// @notice Amount of liquidity where will be the maximum emission of rewards per second applied (could be set as KEEP_CURRENT)
    uint256 targetLiquidity;
    /// @notice Optional array of reward configs, can be empty
    IRewardsStructs.RewardSetupConfig[] rewardConfigs;
  }

  struct ConfigureRewardsConfig {
    /// @notice Address of the `asset` whose reward should be configured
    address umbrellaStake;
    /// @notice Array of structs with params to set
    IRewardsStructs.RewardSetupConfig[] rewardConfigs;
  }

  /// Structs for extended payloads
  /////////////////////////////////////////////////////////////////////////////////////////

  struct TokenRemoval {
    /// @notice Address of the `UmbrellaStakeToken` which should be removed from the system
    address umbrellaStake;
    /// @notice Address that must transfer all rewards that have not been received by users
    address residualRewardPayer;
  }

  struct TokenSetup {
    /// @notice `UmbrellaStakeToken`s setup config
    IUmbrellaStkManager.StakeTokenSetup stakeSetup;
    /// @notice Amount of liquidity where will be the maximum emission of rewards per second applied
    uint256 targetLiquidity;
    /// @notice Optional array of reward configs, can be empty
    IRewardsStructs.RewardSetupConfig[] rewardConfigs;
    /// @notice Reserve address
    address reserve;
    /// @notice Percentage of funds slashed on top of the new deficit
    uint256 liquidationFee;
    /// @notice Oracle of `UmbrellaStakeToken`s underlying
    address umbrellaStakeUnderlyingOracle;
    /// @notice The value by which `deficitOffset` will be increased
    uint256 deficitOffsetIncrease;
  }

  /////////////////////////////////////////////////////////////////////////////////////////
}
