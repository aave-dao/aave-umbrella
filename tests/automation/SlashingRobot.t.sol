// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {IRewardsStructs} from '../../src/contracts/rewards/interfaces/IRewardsStructs.sol';
import {IUmbrellaConfiguration} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol';

import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';
import {SlashingRobot, ISlashingRobot, Ownable} from '../../src/contracts/automation/SlashingRobot.sol';

import {UmbrellaBaseTest} from '../umbrella/utils/UmbrellaBase.t.sol';
import {MockOracle} from '../umbrella/utils/mocks/MockOracle.sol';

contract SlashingRobot_Test is UmbrellaBaseTest {
  SlashingRobot robot;
  address public constant ROBOT_GUARDIAN = address(99);

  function setUp() public virtual override {
    super.setUp();

    robot = new SlashingRobot(address(umbrella), ROBOT_GUARDIAN);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: _setUpOracles(address(underlying6Decimals))
    });
    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying18Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: _setUpOracles(address(underlying18Decimals))
    });

    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);

    _setUpRewardsController(address(stakeWith6Decimals));
    _setUpRewardsController(address(stakeWith18Decimals));
  }

  function test_slashReserve() public {
    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.expectEmit();
    emit ISlashingRobot.ReserveSlashed(address(underlying6Decimals), 1_000 * 1e6);

    assertTrue(_checkAndPerformAutomation());

    assertEq(stakeWith6Decimals.totalAssets(), 9_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 1_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 9_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);
  }

  function test_slashReserve_multiple() public {
    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    pool.addReserveDeficit(address(underlying18Decimals), 2_000 * 1e18);
    _depositToStake(address(stakeWith18Decimals), user, 20_000 * 1e18);

    vm.expectEmit();
    emit ISlashingRobot.ReserveSlashed(address(underlying6Decimals), 1_000 * 1e6);

    vm.expectEmit();
    emit ISlashingRobot.ReserveSlashed(address(underlying18Decimals), 2_000 * 1e18);

    assertTrue(_checkAndPerformAutomation());

    assertEq(stakeWith6Decimals.totalAssets(), 9_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 1_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 9_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    assertEq(stakeWith18Decimals.totalAssets(), 18_000 * 1e18);
    assertEq(underlying18Decimals.balanceOf(collector), 2_000 * 1e18);
    assertEq(underlying18Decimals.balanceOf(address(stakeWith18Decimals)), 18_000 * 1e18);
    assertEq(umbrella.getDeficitOffset(address(underlying18Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying18Decimals)), 2_000 * 1e18);
  }

  function test_revert_slashReserve_zeroFundsOnStakeToken() public {
    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    assertEq(stakeWith6Decimals.totalAssets(), 0);

    (bool shouldRunKeeper, ) = robot.checkUpkeep('');
    assertFalse(shouldRunKeeper);
  }

  function test_reserveDisabled() public {
    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.prank(ROBOT_GUARDIAN);
    robot.disable(address(underlying6Decimals), true);
    assertFalse(_checkAndPerformAutomation());

    vm.prank(ROBOT_GUARDIAN);
    robot.disable(address(underlying6Decimals), false);
    assertTrue(_checkAndPerformAutomation());
  }

  function test_setDisable(address reserve) public {
    vm.startPrank(ROBOT_GUARDIAN);

    vm.expectEmit();
    emit ISlashingRobot.ReserveDisabled(reserve, true);

    robot.disable(reserve, true);
    assertTrue(robot.isDisabled(reserve));

    vm.expectEmit();
    emit ISlashingRobot.ReserveDisabled(reserve, false);

    robot.disable(reserve, false);
    assertFalse(robot.isDisabled(reserve));
  }

  function test_revert_setDisable(address caller, address reserve, bool disable) public {
    vm.assume(caller != ROBOT_GUARDIAN);
    vm.prank(caller);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    robot.disable(reserve, disable);
  }

  function _setUpOracles(address reserve) internal returns (address oracle) {
    aaveOracle.setAssetPrice(reserve, 1e8);

    return address(new MockOracle(1e8));
  }

  function _setUpRewardsController(address stakeToken) internal {
    vm.startPrank(defaultAdmin);

    IRewardsStructs.RewardSetupConfig[] memory empty = new IRewardsStructs.RewardSetupConfig[](0);
    rewardsController.configureAssetWithRewards(
      stakeToken,
      1_000_000 * (10 ** StakeToken(stakeToken).decimals()),
      empty
    );

    vm.stopPrank();
  }

  function _depositToStake(address stake, address user, uint256 amount) internal returns (uint256) {
    deal(StakeToken(stake).asset(), user, amount);

    vm.startPrank(user);

    IERC20(StakeToken(stake).asset()).approve(stake, amount);
    uint256 shares = StakeToken(stake).deposit(amount, user);

    vm.stopPrank();

    return shares;
  }

  function _checkAndPerformAutomation() internal virtual returns (bool) {
    (bool shouldRunKeeper, bytes memory performData) = robot.checkUpkeep('');

    if (shouldRunKeeper) {
      robot.performUpkeep(performData);
    }

    return shouldRunKeeper;
  }
}
