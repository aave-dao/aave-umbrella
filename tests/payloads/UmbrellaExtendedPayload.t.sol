// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

import {UmbrellaExtendedPayload} from '../../src/contracts/payloads/UmbrellaExtendedPayload.sol';

import {UmbrellaPayloadSetup} from './utils/UmbrellaPayloadSetup.t.sol';

import {IUmbrellaEngineStructs as IStructs, IRewardsStructs as IRStructs} from '../../src/contracts/payloads/IUmbrellaEngineStructs.sol';
import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from '../../src/contracts/payloads/IUmbrellaEngineStructs.sol';

import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';

import {MockOracle} from '../umbrella/utils/mocks/MockOracle.sol';

// vm.addr(0xDEAD)
address constant ENGINE = 0x7B1aFE2745533D852d6fD5A677F14c074210d896;

uint256 constant DEFAULT_COOLDOWN = 2 weeks;
uint256 constant DEFAULT_UNSTAKE_WINDOW = 2 days;

contract UmbrellaExtendedPayloadTest is UmbrellaPayloadSetup {
  function test_complexCreation() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    address oracle = address(new MockOracle(1e8));

    ComplexCreation payload = new ComplexCreation(
      address(underlying_1),
      address(underlying_2),
      address(reward),
      address(this),
      oracle
    );

    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    address[] memory stakes = umbrella.getStkTokens();

    defaultAdmin.execute(address(payload));

    address[] memory newStakes = umbrella.getStkTokens();

    assertEq(newStakes.length, stakes.length + 2);

    assertEq(umbrella.getStakeTokenData(newStakes[2]).underlyingOracle, oracle);
    assertEq(umbrella.getStakeTokenData(newStakes[3]).underlyingOracle, oracle);

    assertEq(umbrella.getStakeTokenData(newStakes[2]).reserve, address(underlying_1));
    assertEq(umbrella.getStakeTokenData(newStakes[3]).reserve, address(underlying_2));

    assertEq(StakeToken(newStakes[2]).getCooldown(), DEFAULT_COOLDOWN);
    assertEq(StakeToken(newStakes[3]).getCooldown(), DEFAULT_COOLDOWN);

    assertEq(StakeToken(newStakes[2]).getUnstakeWindow(), DEFAULT_UNSTAKE_WINDOW);
    assertEq(StakeToken(newStakes[3]).getUnstakeWindow(), DEFAULT_UNSTAKE_WINDOW);

    assertEq(umbrella.getPendingDeficit(address(underlying_1)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying_2)), 0);

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 2000 * 1e18);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 1_000 * 1e18);

    assertEq(rewardsController.getAllRewards(newStakes[2]).length, 1);
    assertEq(rewardsController.getAllRewards(newStakes[3]).length, 1);

    assertEq(rewardsController.getAllRewards(newStakes[2])[0], address(reward));
    assertEq(rewardsController.getAllRewards(newStakes[3])[0], address(reward));

    assertEq(rewardsController.getAssetData(newStakes[2]).targetLiquidity, 1e6 * 1e18);
    assertEq(rewardsController.getAssetData(newStakes[3]).targetLiquidity, 1e6 * 1e18);

    assertEq(rewardsController.getAssetData(newStakes[2]).lastUpdateTimestamp, block.timestamp);
    assertEq(rewardsController.getAssetData(newStakes[3]).lastUpdateTimestamp, block.timestamp);

    assertEq(rewardsController.getRewardData(newStakes[2], address(reward)).addr, address(reward));
    assertEq(rewardsController.getRewardData(newStakes[3], address(reward)).addr, address(reward));

    assertEq(
      rewardsController.getRewardData(newStakes[2], address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(newStakes[3], address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(newStakes[2], address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
    assertEq(
      rewardsController.getRewardData(newStakes[3], address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
  }

  function test_complexRemoval() public {
    // complex token creation
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    address oracle = address(new MockOracle(1e8));

    ComplexCreation payload = new ComplexCreation(
      address(underlying_1),
      address(underlying_2),
      address(reward),
      address(this),
      oracle
    );

    defaultAdmin.execute(address(payload));

    address[] memory newStakes = umbrella.getStkTokens();

    ComplexRemoval payload_2 = new ComplexRemoval(newStakes[2], newStakes[3], address(this));

    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getStakeTokenData(newStakes[2]).underlyingOracle, oracle);
    assertEq(umbrella.getStakeTokenData(newStakes[3]).underlyingOracle, oracle);

    assertEq(umbrella.getStakeTokenData(newStakes[2]).reserve, address(0));
    assertEq(umbrella.getStakeTokenData(newStakes[3]).reserve, address(0));

    assertEq(rewardsController.getAssetData(newStakes[2]).lastUpdateTimestamp, block.timestamp);
    assertEq(rewardsController.getAssetData(newStakes[3]).lastUpdateTimestamp, block.timestamp);

    assertEq(
      rewardsController.getRewardData(newStakes[2], address(reward)).maxEmissionPerSecond,
      0
    );
    assertEq(
      rewardsController.getRewardData(newStakes[3], address(reward)).maxEmissionPerSecond,
      0
    );

    assertEq(
      rewardsController.getRewardData(newStakes[2], address(reward)).distributionEnd,
      block.timestamp
    );
    assertEq(
      rewardsController.getRewardData(newStakes[3], address(reward)).distributionEnd,
      block.timestamp
    );
  }
}

contract ComplexCreation is UmbrellaExtendedPayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  address immutable reward;
  address immutable rewardPayer;

  address immutable oracle;

  constructor(address u1, address u2, address r, address rp, address or) {
    under1 = u1;
    under2 = u2;

    reward = r;
    rewardPayer = rp;
    oracle = or;
  }

  function complexTokenCreations() public view override returns (IStructs.TokenSetup[] memory) {
    IStructs.TokenSetup[] memory config = new IStructs.TokenSetup[](2);
    ISMStructs.StakeTokenSetup[] memory tokenConfig = new ISMStructs.StakeTokenSetup[](2);

    tokenConfig[0] = ISMStructs.StakeTokenSetup({
      underlying: under1,
      cooldown: DEFAULT_COOLDOWN,
      unstakeWindow: DEFAULT_UNSTAKE_WINDOW,
      suffix: 'v2'
    });
    tokenConfig[1] = ISMStructs.StakeTokenSetup({
      underlying: under2,
      cooldown: DEFAULT_COOLDOWN,
      unstakeWindow: DEFAULT_UNSTAKE_WINDOW,
      suffix: 'v2'
    });

    IRStructs.RewardSetupConfig[] memory rewardConfigs = new IRStructs.RewardSetupConfig[](1);

    rewardConfigs[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: (1e6 * 1e18) / 1e15,
      distributionEnd: block.timestamp + 30 days
    });

    config[0] = IStructs.TokenSetup({
      stakeSetup: tokenConfig[0],
      targetLiquidity: 1e6 * 1e18,
      rewardConfigs: rewardConfigs,
      reserve: under1,
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle,
      deficitOffsetIncrease: 1000 * 1e18
    });

    config[1] = IStructs.TokenSetup({
      stakeSetup: tokenConfig[1],
      targetLiquidity: 1e6 * 1e18,
      rewardConfigs: rewardConfigs,
      reserve: under2,
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle,
      deficitOffsetIncrease: 0
    });

    return config;
  }
}

contract ComplexRemoval is UmbrellaExtendedPayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  address immutable residualRewardPayer;

  constructor(address s1, address s2, address rrp) {
    stake1 = s1;
    stake2 = s2;

    residualRewardPayer = rrp;
  }

  function complexTokenRemovals() public view override returns (IStructs.TokenRemoval[] memory) {
    IStructs.TokenRemoval[] memory config = new IStructs.TokenRemoval[](2);

    config[0] = IStructs.TokenRemoval({
      umbrellaStake: stake1,
      residualRewardPayer: residualRewardPayer
    });

    config[1] = IStructs.TokenRemoval({
      umbrellaStake: stake2,
      residualRewardPayer: residualRewardPayer
    });

    return config;
  }
}
