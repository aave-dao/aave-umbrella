// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

import {IUmbrellaBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaBase.sol';
import {IUmbrella} from '../../src/contracts/umbrella/interfaces/IUmbrella.sol';
import {IRewardsStructs} from '../../src/contracts/rewards/interfaces/IRewardsStructs.sol';
import {IUmbrellaStkManager} from '../../src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol';
import {IUmbrellaConfiguration} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol';

import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';

import {UmbrellaBaseTest} from './utils/UmbrellaBase.t.sol';
import {MockOracle} from './utils/mocks/MockOracle.sol';

contract Umbrella_Test is UmbrellaBaseTest {
  function test_tokenForDeficitCoverage() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);

    assertEq(
      umbrella.tokenForDeficitCoverage(address(underlying6Decimals)),
      address(underlying6Decimals)
    );

    _setUpVirtualAccounting(address(underlying6Decimals), true);
    pool.setATokenForReserve(address(underlying6Decimals), address(0xDEAD));

    assertEq(umbrella.tokenForDeficitCoverage(address(underlying6Decimals)), address(0xDEAD));

    _setUpVirtualAccounting(address(underlying6Decimals), false);

    assertEq(
      umbrella.tokenForDeficitCoverage(address(underlying6Decimals)),
      address(underlying6Decimals)
    );
  }

  function test_setDeficitOffset(uint256 amount) public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    amount = bound(amount, 1_000 * 1e6, type(uint256).max);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    umbrella.setDeficitOffset(address(underlying6Decimals), amount);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), amount);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    umbrella.setDeficitOffset(address(underlying6Decimals), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
  }

  function test_setDeficitOffsetNotSetup(uint256 amount) public {
    vm.startPrank(defaultAdmin);

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ReserveCoverageNotSetup.selector));
    umbrella.setDeficitOffset(address(underlying6Decimals), amount);
  }

  function test_setDeficitOffsetLowerThanActualDeficit(uint256 amount) public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    amount = bound(amount, 0, 1_000 * 1e6 - 1);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.TooMuchDeficitOffsetReduction.selector));
    umbrella.setDeficitOffset(address(underlying6Decimals), amount);
  }

  function test_coverDeficitOffsetReserveVirtualOff() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    deal(address(underlying6Decimals), defaultAdmin, 1_000 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    assertEq(underlying6Decimals.balanceOf(address(pool)), 0);

    umbrella.coverDeficitOffset(address(underlying6Decimals), 5_00 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(pool)), 500 * 1e6);

    umbrella.coverDeficitOffset(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(underlying6Decimals.balanceOf(address(pool)), 1_000 * 1e6);
  }

  function test_coverDeficitOffsetReserveVirtualOffWithManualIncrease() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    umbrella.setDeficitOffset(address(underlying6Decimals), 2_000 * 1e6);

    // make sure that we can't cover more than real deficit
    deal(address(underlying6Decimals), defaultAdmin, 1_500 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_500 * 1e6);

    assertEq(underlying6Decimals.balanceOf(address(pool)), 0);

    umbrella.coverDeficitOffset(address(underlying6Decimals), 1_500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    // not zero, cause we increase by 1000
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(pool)), 1_000 * 1e6);

    // could decrease to 0 back, cause actual deficit is zero
    umbrella.setDeficitOffset(address(underlying6Decimals), 0);
  }

  function test_coverDeficitOffsetReserveVirtualOn() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    _setUpVirtualAccounting(address(underlying6Decimals), true);
    pool.setATokenForReserve(address(underlying6Decimals), address(anotherUnderlying6Decimals));

    deal(address(anotherUnderlying6Decimals), defaultAdmin, 1_000 * 1e6);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    anotherUnderlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    umbrella.coverDeficitOffset(address(underlying6Decimals), 5_00 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);

    umbrella.coverDeficitOffset(address(underlying6Decimals), 5_00 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);
  }

  function test_coverPendingDeficitReserveVirtualOff() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    vm.stopPrank();
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    umbrella.slash(address(underlying6Decimals));

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    vm.startPrank(defaultAdmin);

    deal(address(underlying6Decimals), defaultAdmin, 1_000 * 1e6);
    underlying6Decimals.approve(address(umbrella), 500 * 1e6);

    assertEq(underlying6Decimals.balanceOf(address(pool)), 0);

    umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 500 * 1e6);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(pool)), 500 * 1e6);

    underlying6Decimals.approve(address(umbrella), 500 * 1e6);
    umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(underlying6Decimals.balanceOf(address(pool)), 1_000 * 1e6);
  }

  function test_coverPendingDeficitReserveVirtualOn() public {
    _setUpVirtualAccounting(address(underlying6Decimals), true);
    address oracle = _setUpOracles(address(underlying6Decimals));
    pool.setATokenForReserve(address(underlying6Decimals), address(anotherUnderlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    vm.stopPrank();
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    umbrella.slash(address(underlying6Decimals));

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    vm.startPrank(defaultAdmin);

    deal(address(anotherUnderlying6Decimals), defaultAdmin, 1_000 * 1e6);
    anotherUnderlying6Decimals.approve(address(umbrella), 500 * 1e6);

    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);

    umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 500 * 1e6);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);

    anotherUnderlying6Decimals.approve(address(umbrella), 500 * 1e6);
    umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);
  }

  function test_coverPendingDeficitVirtualOnATokenTransferred() public {
    _setUpVirtualAccounting(address(underlying6Decimals), true);
    address oracle = _setUpOracles(address(underlying6Decimals));
    pool.setATokenForReserve(address(underlying6Decimals), address(anotherUnderlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    vm.stopPrank();
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    umbrella.slash(address(underlying6Decimals));

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    vm.startPrank(defaultAdmin);

    deal(address(anotherUnderlying6Decimals), defaultAdmin, 1_000 * 1e6);
    anotherUnderlying6Decimals.approve(address(umbrella), 500 * 1e6);

    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);

    deal(address(anotherUnderlying6Decimals), address(umbrella), 10_000 * 1e6);

    // should not revert and return actual amount covered
    uint256 actualAmount = umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);
    assertEq(actualAmount, 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 500 * 1e6);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);

    anotherUnderlying6Decimals.approve(address(umbrella), 500 * 1e6);
    umbrella.coverPendingDeficit(address(underlying6Decimals), 500 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    assertEq(anotherUnderlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(anotherUnderlying6Decimals.balanceOf(address(pool)), 0);
  }

  function test_coverDeficitOffsetZeroDeficit() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);

    deal(address(underlying6Decimals), user, 1_000 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);

    vm.startPrank(defaultAdmin);

    underlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    umbrella.coverDeficitOffset(address(underlying6Decimals), 5_00 * 1e6);
  }

  function test_coverDeficitOffsetInvalidAmount() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.startPrank(defaultAdmin);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    deal(address(underlying6Decimals), defaultAdmin, 1_000 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    umbrella.coverPendingDeficit(address(underlying6Decimals), 0);
  }

  function test_coverPendingDeficitsetZeroDeficit() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    // skip slash

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    deal(address(underlying6Decimals), defaultAdmin, 1_000 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    umbrella.coverPendingDeficit(address(underlying6Decimals), 1_000 * 1e6);
  }

  function test_coverPendingDeficitsetInvalidAmount() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    umbrella.slash(address(underlying6Decimals));

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    deal(address(underlying6Decimals), defaultAdmin, 1_000 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    umbrella.coverPendingDeficit(address(underlying6Decimals), 0);
  }

  function test_coverReserveDeficit() public {
    vm.startPrank(defaultAdmin);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    deal(address(underlying6Decimals), defaultAdmin, 1_100 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_100 * 1e6);

    uint256 amount = umbrella.coverReserveDeficit(address(underlying6Decimals), 1_100 * 1e6);

    assertEq(amount, 1_000 * 1e6);
    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 0);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 100 * 1e6);
  }

  function test_coverReserveDeficitForConfiguredReserve() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    deal(address(underlying6Decimals), defaultAdmin, 1_100 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_100 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ReserveIsConfigured.selector));
    uint256 amount = umbrella.coverReserveDeficit(address(underlying6Decimals), 1_100 * 1e6);

    umbrella.slash(address(underlying6Decimals));

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory stakeRemoval = new IUmbrellaConfiguration.SlashingConfigRemoval[](1);

    stakeRemoval[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    umbrella.removeSlashingConfigs(stakeRemoval);

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ReserveIsConfigured.selector));
    amount = umbrella.coverReserveDeficit(address(underlying6Decimals), 1_100 * 1e6);
  }

  function test_coverReserveDeficitForConfiguredReserveWithOffset() public {
    _setUpVirtualAccounting(address(underlying6Decimals), false);
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    _setUpRewardsController(address(stakeWith6Decimals));

    vm.startPrank(defaultAdmin);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1_000 * 1e6);

    assertEq(pool.getReserveDeficit(address(underlying6Decimals)), 1_000 * 1e6);

    deal(address(underlying6Decimals), defaultAdmin, 1_100 * 1e6);
    underlying6Decimals.approve(address(umbrella), 1_100 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ReserveIsConfigured.selector));
    uint256 amount = umbrella.coverReserveDeficit(address(underlying6Decimals), 1_100 * 1e6);

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory stakeRemoval = new IUmbrellaConfiguration.SlashingConfigRemoval[](1);

    stakeRemoval[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    umbrella.removeSlashingConfigs(stakeRemoval);

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ReserveIsConfigured.selector));
    amount = umbrella.coverReserveDeficit(address(underlying6Decimals), 1_100 * 1e6);
  }

  function test_slash() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    assertEq(stakeWith6Decimals.totalAssets(), 10_000 * 1e6);

    uint256 coveredDeficit = umbrella.slash(address(underlying6Decimals));

    assertEq(stakeWith6Decimals.totalAssets(), 9_000 * 1e6);

    assertEq(underlying6Decimals.balanceOf(collector), 1_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 9_000 * 1e6);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);
    assertEq(coveredDeficit, umbrella.getPendingDeficit(address(underlying6Decimals)));
  }

  function test_slashHalfDeficit() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    _depositToStake(address(stakeWith6Decimals), user, 500 * 1e6 + 1e6);

    assertEq(stakeWith6Decimals.totalAssets(), 500 * 1e6 + 1e6);

    uint256 coveredDeficit = umbrella.slash(address(underlying6Decimals));

    // Slash up to MIN_ASSETS_REMAINING
    assertEq(stakeWith6Decimals.totalAssets(), 1e6);

    assertEq(underlying6Decimals.balanceOf(collector), 500 * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 1e6);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 500 * 1e6);
    assertEq(coveredDeficit, umbrella.getPendingDeficit(address(underlying6Decimals)));
  }

  function test_slashNoDeficit() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));

    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    assertEq(stakeWith6Decimals.totalAssets(), 10_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(underlying6Decimals));
  }

  function test_slashNoConfig() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));

    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory removalPairs = new IUmbrellaConfiguration.SlashingConfigRemoval[](2);

    removalPairs[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    umbrella.removeSlashingConfigs(removalPairs);
    vm.stopPrank();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(underlying6Decimals));
  }

  function test_slashSeveralConfigs() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaStkManager.StakeTokenSetup[]
      memory configs = new IUmbrellaStkManager.StakeTokenSetup[](1);

    configs[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'v2'
    });

    vm.startPrank(defaultAdmin);
    address[] memory newStakes = umbrella.createStakeTokens(configs);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(newStakes[0]),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));
    _setUpRewardsController(address(newStakes[0]));

    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);
    _depositToStake(address(newStakes[0]), user, 10_000 * 1e6);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(underlying6Decimals));
  }

  function test_slashWithNonZeroLb(uint256 lb) public {
    lb = bound(lb, 0, 10_000);

    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: lb,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    pool.addReserveDeficit(address(underlying6Decimals), 1_000 * 1e6);
    (bool isSlashable, uint256 newDeficit) = umbrella.isReserveSlashable(
      address(underlying6Decimals)
    );

    assertEq(isSlashable, true);
    assertEq(newDeficit, 1_000 * 1e6);

    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 10_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 0);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    uint256 slashedAmount = umbrella.slash(address(underlying6Decimals));

    assertEq(slashedAmount, 1_000 * 1e6);
    assertLe(slashedAmount, (1_000 * 1e6 * (10_000 + lb)) / 10_000);

    assertEq(underlying6Decimals.balanceOf(collector), (1_000 * 1e6 * (10_000 + lb)) / 10_000);
    assertEq(
      underlying6Decimals.balanceOf(address(stakeWith6Decimals)),
      10_000 * 1e6 - (1_000 * 1e6 * (10_000 + lb)) / 10_000
    );

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 1_000 * 1e6);
  }

  function test_slashWithNonZeroLbExceedDeficit(uint256 lb) public {
    lb = bound(lb, 0, 10_000);

    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: lb,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(stakeSetups);
    vm.stopPrank();

    _setUpRewardsController(address(stakeWith6Decimals));
    _depositToStake(address(stakeWith6Decimals), user, 10_000 * 1e6);

    pool.addReserveDeficit(address(underlying6Decimals), 10_000 * 1e6);
    (bool isSlashable, uint256 newDeficit) = umbrella.isReserveSlashable(
      address(underlying6Decimals)
    );

    assertEq(isSlashable, true);
    assertEq(newDeficit, 10_000 * 1e6);

    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 10_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 0);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    uint256 amountOfDeficitCovered = umbrella.slash(address(underlying6Decimals));

    assertLe(amountOfDeficitCovered, (10_000 - 1) * 1e6);

    assertEq(underlying6Decimals.balanceOf(collector), (10_000 - 1) * 1e6);
    assertEq(underlying6Decimals.balanceOf(address(stakeWith6Decimals)), 1e6);

    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), amountOfDeficitCovered);
  }

  function test_predictAndCreate(string memory suffix) public {
    vm.assume(keccak256(abi.encode(suffix)) != keccak256(abi.encode(string('v1'))));

    IUmbrellaStkManager.StakeTokenSetup[]
      memory configs = new IUmbrellaStkManager.StakeTokenSetup[](1);

    configs[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: suffix
    });

    address[] memory predictedAddress = umbrella.predictStakeTokensAddresses(configs);

    vm.startPrank(defaultAdmin);
    address[] memory newStakes = umbrella.createStakeTokens(configs);

    assertEq(predictedAddress[0], newStakes[0]);
  }

  function test_InvalidRoles() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.setDeficitOffset(address(0), 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.coverPendingDeficit(address(0), 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.coverDeficitOffset(address(0), 0);
  }

  function _setUpOracles(address reserve) internal returns (address oracle) {
    aaveOracle.setAssetPrice(reserve, 1e8);

    return address(new MockOracle(1e8));
  }

  function _setUpRewardsController(address stakeToken) internal {
    vm.startPrank(defaultAdmin);

    IRewardsStructs.RewardSetupConfig[] memory empty = new IRewardsStructs.RewardSetupConfig[](0);
    rewardsController.configureAssetWithRewards(stakeToken, 1_000_000 * 1e6, empty);

    vm.stopPrank();
  }

  function _setUpVirtualAccounting(address reserve, bool flag) internal {
    pool.activateVirtualAcc(reserve, flag);
  }

  function _depositToStake(address stake, address user, uint256 amount) internal returns (uint256) {
    deal(StakeToken(stake).asset(), user, amount);

    vm.startPrank(user);

    IERC20(StakeToken(stake).asset()).approve(stake, amount);
    uint256 shares = StakeToken(stake).deposit(amount, user);

    vm.stopPrank();

    return shares;
  }
}
