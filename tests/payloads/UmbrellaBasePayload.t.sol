// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {Address} from 'openzeppelin-contracts/contracts/utils/Address.sol';

import {UmbrellaBasePayload} from '../../src/contracts/payloads/UmbrellaBasePayload.sol';

import {UmbrellaPayloadSetup} from './utils/UmbrellaPayloadSetup.t.sol';

import {IUmbrellaEngineStructs as IStructs, IRewardsStructs as IRStructs} from '../../src/contracts/payloads/IUmbrellaEngineStructs.sol';
import {IUmbrellaStkManager as ISMStructs, IUmbrellaConfiguration as ICStructs} from '../../src/contracts/payloads/IUmbrellaEngineStructs.sol';

import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';

import {MockOracle} from '../umbrella/utils/mocks/MockOracle.sol';

// vm.addr(0xDEAD)
address constant ENGINE = 0x7B1aFE2745533D852d6fD5A677F14c074210d896;

uint256 constant DEFAULT_COOLDOWN = 2 weeks;
uint256 constant NEW_COOLDOWN = 1 weeks;

uint256 constant DEFAULT_UNSTAKE_WINDOW = 2 days;
uint256 constant NEW_UNSTAKE_WINDOW = 1 days;

uint256 constant KEEP_CURRENT = type(uint256).max - 42;

contract UmbrellaBasePayloadTest is UmbrellaPayloadSetup {
  using Address for address;

  function test_constructor() public {
    DumbPayload payload = new DumbPayload(ENGINE);

    assertEq(payload.ENGINE(), ENGINE);
  }

  function test_constructorZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(UmbrellaBasePayload.ZeroAddress.selector));
    new DumbPayload(address(0));
  }

  function test_createStkTokens() public {
    CreateStakeTokens createPayload = new CreateStakeTokens(
      address(underlying_1),
      address(underlying_2)
    );
    address[] memory stakes = umbrella.getStkTokens();

    defaultAdmin.execute(address(createPayload));

    address[] memory newStakes = umbrella.getStkTokens();

    assertEq(newStakes.length, stakes.length + 2);
  }

  function test_updateCooldownsAndUnstake() public {
    UpdateCooldownsAndUnstake updatePayload = new UpdateCooldownsAndUnstake(
      address(stakeToken_1),
      address(stakeToken_2)
    );

    assertEq(stakeToken_1.getCooldown(), DEFAULT_COOLDOWN);
    assertEq(stakeToken_2.getCooldown(), DEFAULT_COOLDOWN);

    assertEq(stakeToken_1.getUnstakeWindow(), DEFAULT_UNSTAKE_WINDOW);
    assertEq(stakeToken_2.getUnstakeWindow(), DEFAULT_UNSTAKE_WINDOW);

    defaultAdmin.execute(address(updatePayload));

    assertEq(stakeToken_1.getCooldown(), NEW_COOLDOWN);
    assertEq(stakeToken_2.getCooldown(), DEFAULT_COOLDOWN);

    assertEq(stakeToken_1.getUnstakeWindow(), DEFAULT_UNSTAKE_WINDOW);
    assertEq(stakeToken_2.getUnstakeWindow(), NEW_UNSTAKE_WINDOW);
  }

  function test_updateSlashingConfig() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    address oracle = address(new MockOracle(1e8));

    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).underlyingOracle, address(0));
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).underlyingOracle, address(0));

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).reserve, address(0));
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).reserve, address(0));

    defaultAdmin.execute(address(payload));

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).underlyingOracle, oracle);
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).underlyingOracle, oracle);

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).reserve, address(underlying_1));
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).reserve, address(underlying_2));
  }

  function test_removeSlashingConfig() public {
    // update slashing config
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    address oracle = address(new MockOracle(1e8));

    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    // removeSlashingConfig
    RemoveSlashingConfig payload_2 = new RemoveSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2)
    );

    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).underlyingOracle, oracle);
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).underlyingOracle, oracle);

    assertEq(umbrella.getStakeTokenData(address(stakeToken_1)).reserve, address(0));
    assertEq(umbrella.getStakeTokenData(address(stakeToken_2)).reserve, address(0));
  }

  function test_setDeficitOffset() public {
    // update slashing config
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    address oracle = address(new MockOracle(1e8));

    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    // setDeficitOffset
    SetDeficitOffset payload_2 = new SetDeficitOffset(address(underlying_1), address(underlying_2));

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 0);

    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 1e18);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 1e18);
  }

  function test_coverPendingDeficitWithApprove() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    _setUpRewardsController(address(stakeToken_1));
    _setUpRewardsController(address(stakeToken_2));

    address oracle = address(new MockOracle(1e8));

    // setup SlashingConfig
    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    _depositToStake(address(stakeToken_1), user, 10_000 * 1e18);
    _depositToStake(address(stakeToken_2), user, 10_000 * 1e18);

    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    umbrella.slash(address(underlying_1));
    umbrella.slash(address(underlying_2));

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(umbrella.getPendingDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(umbrella.getPendingDeficit(address(underlying_2)), 1000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverPendingDeficitWithApprove payload_2 = new CoverPendingDeficitWithApprove(
      address(underlying_1),
      address(underlying_2)
    );

    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getPendingDeficit(address(underlying_1)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying_2)), 0);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_coverPendingDeficitWithoutApprove() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    _setUpRewardsController(address(stakeToken_1));
    _setUpRewardsController(address(stakeToken_2));

    address oracle = address(new MockOracle(1e8));

    // setup SlashingConfig
    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    _depositToStake(address(stakeToken_1), user, 10_000 * 1e18);
    _depositToStake(address(stakeToken_2), user, 10_000 * 1e18);

    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    umbrella.slash(address(underlying_1));
    umbrella.slash(address(underlying_2));

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(umbrella.getPendingDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(umbrella.getPendingDeficit(address(underlying_2)), 1000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverPendingDeficitWithoutApprove payload_2 = new CoverPendingDeficitWithoutApprove(
      address(underlying_1),
      address(underlying_2)
    );

    // try to cover without approve
    vm.expectRevert();
    defaultAdmin.execute(address(payload_2));

    vm.startPrank(address(defaultAdmin));

    underlying_1.approve(address(umbrella), 1000 * 1e18);
    underlying_2.approve(address(umbrella), 1000 * 1e18);

    vm.stopPrank();

    // with approval should be okay
    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getPendingDeficit(address(underlying_1)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying_2)), 0);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_coverDeficitOffsetWithApprove() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    _setUpRewardsController(address(stakeToken_1));
    _setUpRewardsController(address(stakeToken_2));

    address oracle = address(new MockOracle(1e8));

    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    // setup SlashingConfig
    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    _depositToStake(address(stakeToken_1), user, 10_000 * 1e18);
    _depositToStake(address(stakeToken_2), user, 10_000 * 1e18);

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 1000 * 1e18);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 1000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverDeficitOffsetWithApprove payload_2 = new CoverDeficitOffsetWithApprove(
      address(underlying_1),
      address(underlying_2)
    );

    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 0);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_coverDeficitOffsetWithoutApprove() public {
    aaveOracle.setAssetPrice(address(underlying_1), 1e8);
    aaveOracle.setAssetPrice(address(underlying_2), 1e8);

    _setUpRewardsController(address(stakeToken_1));
    _setUpRewardsController(address(stakeToken_2));

    address oracle = address(new MockOracle(1e8));

    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    // setup SlashingConfig
    UpdateSlashingConfig payload = new UpdateSlashingConfig(
      address(underlying_1),
      address(underlying_2),
      address(stakeToken_1),
      address(stakeToken_2),
      oracle
    );

    defaultAdmin.execute(address(payload));

    _depositToStake(address(stakeToken_1), user, 10_000 * 1e18);
    _depositToStake(address(stakeToken_2), user, 10_000 * 1e18);

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 1000 * 1e18);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 1000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverDeficitOffsetWithoutApprove payload_2 = new CoverDeficitOffsetWithoutApprove(
      address(underlying_1),
      address(underlying_2)
    );

    // try to cover without approve
    vm.expectRevert();
    defaultAdmin.execute(address(payload_2));

    vm.startPrank(address(defaultAdmin));

    underlying_1.approve(address(umbrella), 1000 * 1e18);
    underlying_2.approve(address(umbrella), 1000 * 1e18);

    vm.stopPrank();

    // with approval should be okay
    defaultAdmin.execute(address(payload_2));

    assertEq(umbrella.getDeficitOffset(address(underlying_1)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying_2)), 0);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_coverReserveDeficitWithApprove() public {
    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverReserveDeficitWithApprove payload = new CoverReserveDeficitWithApprove(
      address(underlying_1),
      address(underlying_2)
    );

    // with approval should be okay
    defaultAdmin.execute(address(payload));

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_coverReserveDeficitWithoutApprove() public {
    pool.addReserveDeficit(address(underlying_1), 1_000 * 1e18);
    pool.addReserveDeficit(address(underlying_2), 1_000 * 1e18);

    deal(address(underlying_1), address(defaultAdmin), 1_000 * 1e18);
    deal(address(underlying_2), address(defaultAdmin), 1_000 * 1e18);

    assertEq(pool.getReserveDeficit(address(underlying_1)), 1000 * 1e18);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 1000 * 1e18);

    // cover pendingDeficitWithApprove
    CoverReserveDeficitWithoutApprove payload = new CoverReserveDeficitWithoutApprove(
      address(underlying_1),
      address(underlying_2)
    );

    // try to cover without approve
    vm.expectRevert();
    defaultAdmin.execute(address(payload));

    vm.startPrank(address(defaultAdmin));

    underlying_1.approve(address(umbrella), 1000 * 1e18);
    underlying_2.approve(address(umbrella), 1000 * 1e18);

    vm.stopPrank();

    // with approval should be okay
    defaultAdmin.execute(address(payload));

    assertEq(pool.getReserveDeficit(address(underlying_1)), 0);
    assertEq(pool.getReserveDeficit(address(underlying_2)), 0);
  }

  function test_configureStakeAndRewards() public {
    ConfigureStakeAndRewards payload = new ConfigureStakeAndRewards(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 0);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 0);

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 0);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 0);

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp, 0);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp, 0);

    defaultAdmin.execute(address(payload));

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 1);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 1);

    assertEq(rewardsController.getAllRewards(address(stakeToken_1))[0], address(reward));
    assertEq(rewardsController.getAllRewards(address(stakeToken_2))[0], address(reward));

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 1e6 * 1e18);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 1e6 * 1e18);

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).addr,
      address(reward)
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).addr,
      address(reward)
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
  }

  function test_configureStakeAndRewardsAndUpdate() public {
    ConfigureStakeAndRewards payload = new ConfigureStakeAndRewards(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    defaultAdmin.execute(address(payload));

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 1);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 1);

    assertEq(rewardsController.getAllRewards(address(stakeToken_1))[0], address(reward));
    assertEq(rewardsController.getAllRewards(address(stakeToken_2))[0], address(reward));

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 1e6 * 1e18);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 1e6 * 1e18);

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).addr,
      address(reward)
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).addr,
      address(reward)
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );

    uint256 stake2RewardDistributionEnd = rewardsController
      .getRewardData(address(stakeToken_2), address(reward))
      .distributionEnd;

    assertEq(stake2RewardDistributionEnd, block.timestamp + 30 days);

    skip(1 days);

    ConfigureStakeAndRewardsUpdate payload_2 = new ConfigureStakeAndRewardsUpdate(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    defaultAdmin.execute(address(payload_2));

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 1);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 1);

    assertEq(rewardsController.getAllRewards(address(stakeToken_1))[0], address(reward));
    assertEq(rewardsController.getAllRewards(address(stakeToken_2))[0], address(reward));

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 1e5 * 1e18);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 1e6 * 1e18);

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).addr,
      address(reward)
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).addr,
      address(reward)
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).maxEmissionPerSecond,
      (10 * 1e6 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).distributionEnd,
      stake2RewardDistributionEnd
    );
  }

  function test_configureRewards() public {
    // initialize assets and rewards
    ConfigureStakeAndRewards payload = new ConfigureStakeAndRewards(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    defaultAdmin.execute(address(payload));

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 1);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 1);

    assertEq(rewardsController.getAllRewards(address(stakeToken_1))[0], address(reward));
    assertEq(rewardsController.getAllRewards(address(stakeToken_2))[0], address(reward));

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 1e6 * 1e18);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 1e6 * 1e18);

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    ConfigureRewards payload_2 = new ConfigureRewards(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    skip(1 days);

    defaultAdmin.execute(address(payload_2));

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).addr,
      address(reward)
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).addr,
      address(reward)
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).maxEmissionPerSecond,
      (1e7 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).maxEmissionPerSecond,
      (1e7 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
  }

  function test_configureRewardsUpdate() public {
    // initialize assets and rewards
    ConfigureStakeAndRewards payload = new ConfigureStakeAndRewards(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    defaultAdmin.execute(address(payload));

    assertEq(rewardsController.getAllRewards(address(stakeToken_1)).length, 1);
    assertEq(rewardsController.getAllRewards(address(stakeToken_2)).length, 1);

    assertEq(rewardsController.getAllRewards(address(stakeToken_1))[0], address(reward));
    assertEq(rewardsController.getAllRewards(address(stakeToken_2))[0], address(reward));

    assertEq(rewardsController.getAssetData(address(stakeToken_1)).targetLiquidity, 1e6 * 1e18);
    assertEq(rewardsController.getAssetData(address(stakeToken_2)).targetLiquidity, 1e6 * 1e18);

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    skip(1 days);

    ConfigureRewardsUpdate payload_2 = new ConfigureRewardsUpdate(
      address(stakeToken_1),
      address(stakeToken_2),
      address(reward),
      address(this)
    );

    defaultAdmin.execute(address(payload_2));

    assertEq(
      rewardsController.getAssetData(address(stakeToken_1)).lastUpdateTimestamp,
      block.timestamp
    );
    assertEq(
      rewardsController.getAssetData(address(stakeToken_2)).lastUpdateTimestamp,
      block.timestamp
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).addr,
      address(reward)
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).addr,
      address(reward)
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).maxEmissionPerSecond,
      (1e6 * 1e18) / 1e15
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).maxEmissionPerSecond,
      (1e7 * 1e18) / 1e15
    );

    assertEq(
      rewardsController.getRewardData(address(stakeToken_1), address(reward)).distributionEnd,
      block.timestamp + 30 days
    );
    assertEq(
      rewardsController.getRewardData(address(stakeToken_2), address(reward)).distributionEnd,
      block.timestamp + 30 days - 1 days
    );
  }

  function _depositToStake(address stake, address user, uint256 amount) internal returns (uint256) {
    deal(StakeToken(stake).asset(), user, amount);

    vm.startPrank(user);

    IERC20(StakeToken(stake).asset()).approve(stake, amount);
    uint256 shares = StakeToken(stake).deposit(amount, user);

    vm.stopPrank();

    return shares;
  }

  function _setUpRewardsController(address stakeToken) internal {
    vm.startPrank(address(defaultAdmin));

    IRStructs.RewardSetupConfig[] memory empty = new IRStructs.RewardSetupConfig[](0);
    rewardsController.configureAssetWithRewards(stakeToken, 1_000_000 * 1e18, empty);

    vm.stopPrank();
  }
}

contract DumbPayload is UmbrellaBasePayload {
  constructor(address umbrellaConfigEngine) UmbrellaBasePayload(umbrellaConfigEngine) {}
}

contract CreateStakeTokens is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function createStkTokens() public view override returns (ISMStructs.StakeTokenSetup[] memory) {
    ISMStructs.StakeTokenSetup[] memory config = new ISMStructs.StakeTokenSetup[](2);

    config[0] = ISMStructs.StakeTokenSetup({
      underlying: under1,
      cooldown: DEFAULT_COOLDOWN,
      unstakeWindow: DEFAULT_UNSTAKE_WINDOW,
      suffix: 'v2'
    });
    config[1] = ISMStructs.StakeTokenSetup({
      underlying: under2,
      cooldown: DEFAULT_COOLDOWN,
      unstakeWindow: DEFAULT_UNSTAKE_WINDOW,
      suffix: 'v2'
    });

    return config;
  }
}

contract UpdateCooldownsAndUnstake is UmbrellaBasePayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  constructor(address s1, address s2) {
    stake1 = s1;
    stake2 = s2;
  }

  function updateUnstakeConfig() public view override returns (IStructs.UnstakeConfig[] memory) {
    IStructs.UnstakeConfig[] memory config = new IStructs.UnstakeConfig[](2);

    config[0] = IStructs.UnstakeConfig({
      umbrellaStake: stake1,
      newCooldown: NEW_COOLDOWN,
      newUnstakeWindow: KEEP_CURRENT
    });
    config[1] = IStructs.UnstakeConfig({
      umbrellaStake: stake2,
      newCooldown: KEEP_CURRENT,
      newUnstakeWindow: NEW_UNSTAKE_WINDOW
    });

    return config;
  }
}

contract UpdateSlashingConfig is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  address immutable stake1;
  address immutable stake2;

  address immutable oracle;

  constructor(address u1, address u2, address s1, address s2, address or) {
    under1 = u1;
    under2 = u2;

    stake1 = s1;
    stake2 = s2;

    oracle = or;
  }

  function updateSlashingConfigs()
    public
    view
    override
    returns (ICStructs.SlashingConfigUpdate[] memory)
  {
    ICStructs.SlashingConfigUpdate[] memory config = new ICStructs.SlashingConfigUpdate[](2);

    config[0] = ICStructs.SlashingConfigUpdate({
      reserve: under1,
      umbrellaStake: stake1,
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });
    config[1] = ICStructs.SlashingConfigUpdate({
      reserve: under2,
      umbrellaStake: stake2,
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    return config;
  }
}

contract RemoveSlashingConfig is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  address immutable stake1;
  address immutable stake2;

  constructor(address u1, address u2, address s1, address s2) {
    under1 = u1;
    under2 = u2;

    stake1 = s1;
    stake2 = s2;
  }

  function removeSlashingConfigs()
    public
    view
    override
    returns (ICStructs.SlashingConfigRemoval[] memory)
  {
    ICStructs.SlashingConfigRemoval[] memory config = new ICStructs.SlashingConfigRemoval[](2);

    config[0] = ICStructs.SlashingConfigRemoval({reserve: under1, umbrellaStake: stake1});
    config[1] = ICStructs.SlashingConfigRemoval({reserve: under2, umbrellaStake: stake2});

    return config;
  }
}

contract SetDeficitOffset is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function setDeficitOffset() public view override returns (IStructs.SetDeficitOffset[] memory) {
    IStructs.SetDeficitOffset[] memory config = new IStructs.SetDeficitOffset[](2);

    config[0] = IStructs.SetDeficitOffset({reserve: under1, newDeficitOffset: 1e18});
    config[1] = IStructs.SetDeficitOffset({reserve: under2, newDeficitOffset: 1e18});

    return config;
  }
}

contract CoverPendingDeficitWithApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverPendingDeficit() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: true});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: true});

    return config;
  }
}

contract CoverPendingDeficitWithoutApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverPendingDeficit() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: false});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: false});

    return config;
  }
}

contract CoverDeficitOffsetWithApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverDeficitOffset() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: true});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: true});

    return config;
  }
}

contract CoverDeficitOffsetWithoutApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverDeficitOffset() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: false});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: false});

    return config;
  }
}

contract CoverReserveDeficitWithApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverReserveDeficit() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: true});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: true});

    return config;
  }
}

contract CoverReserveDeficitWithoutApprove is UmbrellaBasePayload(ENGINE) {
  address immutable under1;
  address immutable under2;

  constructor(address u1, address u2) {
    under1 = u1;
    under2 = u2;
  }

  function coverReserveDeficit() public view override returns (IStructs.CoverDeficit[] memory) {
    IStructs.CoverDeficit[] memory config = new IStructs.CoverDeficit[](2);

    config[0] = IStructs.CoverDeficit({reserve: under1, amount: 1000 * 1e18, approve: false});
    config[1] = IStructs.CoverDeficit({reserve: under2, amount: 1000 * 1e18, approve: false});

    return config;
  }
}

contract ConfigureStakeAndRewards is UmbrellaBasePayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  address immutable reward;
  address immutable rewardPayer;

  constructor(address s1, address s2, address r, address rp) {
    stake1 = s1;
    stake2 = s2;

    reward = r;
    rewardPayer = rp;
  }

  function configureStakeAndRewards()
    public
    view
    override
    returns (IStructs.ConfigureStakeAndRewardsConfig[] memory)
  {
    IStructs.ConfigureStakeAndRewardsConfig[]
      memory config = new IStructs.ConfigureStakeAndRewardsConfig[](2);
    IRStructs.RewardSetupConfig[] memory rewardConfig = new IRStructs.RewardSetupConfig[](1);

    rewardConfig[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: (1e6 * 1e18) / 1e15,
      distributionEnd: block.timestamp + 30 days
    });

    config[0] = IStructs.ConfigureStakeAndRewardsConfig({
      umbrellaStake: stake1,
      targetLiquidity: 1e6 * 1e18,
      rewardConfigs: rewardConfig
    });

    config[1] = IStructs.ConfigureStakeAndRewardsConfig({
      umbrellaStake: stake2,
      targetLiquidity: 1e6 * 1e18,
      rewardConfigs: rewardConfig
    });

    return config;
  }
}

contract ConfigureStakeAndRewardsUpdate is UmbrellaBasePayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  address immutable reward;
  address immutable rewardPayer;

  constructor(address s1, address s2, address r, address rp) {
    stake1 = s1;
    stake2 = s2;

    reward = r;
    rewardPayer = rp;
  }

  function configureStakeAndRewards()
    public
    view
    override
    returns (IStructs.ConfigureStakeAndRewardsConfig[] memory)
  {
    IStructs.ConfigureStakeAndRewardsConfig[]
      memory config = new IStructs.ConfigureStakeAndRewardsConfig[](2);
    IRStructs.RewardSetupConfig[] memory rewardConfig = new IRStructs.RewardSetupConfig[](1);

    rewardConfig[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: KEEP_CURRENT,
      distributionEnd: block.timestamp + 30 days
    });

    config[0] = IStructs.ConfigureStakeAndRewardsConfig({
      umbrellaStake: stake1,
      targetLiquidity: 1e5 * 1e18,
      rewardConfigs: rewardConfig
    });

    IRStructs.RewardSetupConfig[] memory rewardConfig2 = new IRStructs.RewardSetupConfig[](1);

    rewardConfig2[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: (10 * 1e6 * 1e18) / 1e15,
      distributionEnd: KEEP_CURRENT
    });

    config[1] = IStructs.ConfigureStakeAndRewardsConfig({
      umbrellaStake: stake2,
      targetLiquidity: KEEP_CURRENT,
      rewardConfigs: rewardConfig2
    });

    return config;
  }
}

contract ConfigureRewards is UmbrellaBasePayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  address immutable reward;
  address immutable rewardPayer;

  constructor(address s1, address s2, address r, address rp) {
    stake1 = s1;
    stake2 = s2;

    reward = r;
    rewardPayer = rp;
  }

  function configureRewards()
    public
    view
    override
    returns (IStructs.ConfigureRewardsConfig[] memory)
  {
    IStructs.ConfigureRewardsConfig[] memory config = new IStructs.ConfigureRewardsConfig[](2);
    IRStructs.RewardSetupConfig[] memory rewardConfig = new IRStructs.RewardSetupConfig[](1);

    rewardConfig[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: (10 * 1e6 * 1e18) / 1e15,
      distributionEnd: block.timestamp + 30 days
    });

    config[0] = IStructs.ConfigureRewardsConfig({
      umbrellaStake: stake1,
      rewardConfigs: rewardConfig
    });

    config[1] = IStructs.ConfigureRewardsConfig({
      umbrellaStake: stake2,
      rewardConfigs: rewardConfig
    });

    return config;
  }
}

contract ConfigureRewardsUpdate is UmbrellaBasePayload(ENGINE) {
  address immutable stake1;
  address immutable stake2;

  address immutable reward;
  address immutable rewardPayer;

  constructor(address s1, address s2, address r, address rp) {
    stake1 = s1;
    stake2 = s2;

    reward = r;
    rewardPayer = rp;
  }

  function configureRewards()
    public
    view
    override
    returns (IStructs.ConfigureRewardsConfig[] memory)
  {
    IStructs.ConfigureRewardsConfig[] memory config = new IStructs.ConfigureRewardsConfig[](2);
    IRStructs.RewardSetupConfig[] memory rewardConfig = new IRStructs.RewardSetupConfig[](1);

    rewardConfig[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: KEEP_CURRENT,
      distributionEnd: block.timestamp + 30 days
    });

    config[0] = IStructs.ConfigureRewardsConfig({
      umbrellaStake: stake1,
      rewardConfigs: rewardConfig
    });

    IRStructs.RewardSetupConfig[] memory rewardConfig2 = new IRStructs.RewardSetupConfig[](1);

    rewardConfig2[0] = IRStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: rewardPayer,
      maxEmissionPerSecond: (10 * 1e6 * 1e18) / 1e15,
      distributionEnd: KEEP_CURRENT
    });

    config[1] = IStructs.ConfigureRewardsConfig({
      umbrellaStake: stake2,
      rewardConfigs: rewardConfig2
    });

    return config;
  }
}
