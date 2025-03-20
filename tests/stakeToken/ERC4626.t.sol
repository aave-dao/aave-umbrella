// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ERC4626Upgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Errors} from 'openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol';

import {StakeTestBase} from './utils/StakeTestBase.t.sol';

contract ERC4626Tests is StakeTestBase {
  event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  function test_baseFunctionsBeforeActions() public view {
    assertEq(stakeToken.asset(), address(underlying));

    assertEq(stakeToken.totalAssets(), 0);
    assertEq(stakeToken.totalSupply(), 0);

    assertEq(stakeToken.maxDeposit(user), type(uint256).max);
    assertEq(stakeToken.maxMint(user), type(uint256).max);
  }

  // Due to default 1e18 exchange rate there's no rounding here at all, so I checked these values striclty
  function test_previewFunctions(uint192 assets) public view {
    uint256 shares = stakeToken.convertToShares(assets);

    uint256 previewDeposit = stakeToken.previewDeposit(assets);
    assertEq(previewDeposit, shares);

    uint256 previewMint = stakeToken.previewMint(shares);
    assertEq(previewMint, assets);

    uint256 previewWithdraw = stakeToken.previewWithdraw(assets);
    assertEq(previewWithdraw, shares);

    uint256 previewRedeem = stakeToken.previewRedeem(shares);
    assertEq(previewRedeem, assets);
  }

  function test_deposit(uint192 amountToStake) public {
    vm.assume(amountToStake > 0);

    uint256 shares = _deposit(amountToStake, user, user);

    assertEq(stakeToken.totalAssets(), amountToStake);
    assertEq(stakeToken.totalAssets(), underlying.balanceOf(address(stakeToken)));

    assertEq(stakeToken.totalSupply(), shares);
    assertEq(stakeToken.balanceOf(user), shares);
  }

  function test_depositToSomeone(uint192 amountToStake) public {
    vm.assume(amountToStake > 0);

    uint256 shares = _deposit(amountToStake, user, someone);

    assertEq(stakeToken.totalAssets(), amountToStake);
    assertEq(stakeToken.totalAssets(), underlying.balanceOf(address(stakeToken)));

    assertEq(stakeToken.totalSupply(), shares);
    assertEq(stakeToken.balanceOf(someone), shares);
  }

  function test_mint(uint192 amountOfShares) public {
    vm.assume(amountOfShares > 0);

    uint256 amountToStake = stakeToken.previewMint(amountOfShares);
    uint256 assets = _mint(amountOfShares, user, user);

    assertEq(assets, amountToStake);

    assertEq(stakeToken.totalAssets(), amountToStake);
    assertEq(stakeToken.totalAssets(), underlying.balanceOf(address(stakeToken)));

    assertEq(stakeToken.totalSupply(), amountOfShares);
    assertEq(stakeToken.balanceOf(user), amountOfShares);
  }

  function test_mintToSomeone(uint192 amountOfShares) public {
    vm.assume(amountOfShares > 0);

    uint256 amountToStake = stakeToken.previewMint(amountOfShares);
    uint256 assets = _mint(amountOfShares, user, someone);

    assertEq(assets, amountToStake);

    assertEq(stakeToken.totalAssets(), amountToStake);
    assertEq(stakeToken.totalAssets(), underlying.balanceOf(address(stakeToken)));

    assertEq(stakeToken.totalSupply(), amountOfShares);
    assertEq(stakeToken.balanceOf(someone), amountOfShares);
  }

  function test_maxWithdraw(uint192 amountToStake) public {
    vm.assume(amountToStake > 0);

    deal(address(underlying), user, amountToStake);

    _deposit(amountToStake, user, user);

    uint256 zeroAssetsBeforeCooldown = stakeToken.maxWithdraw(user);
    assertEq(zeroAssetsBeforeCooldown, 0);

    vm.startPrank(user);
    stakeToken.cooldown();

    uint256 assetsAvailable = stakeToken.maxWithdraw(user);
    assertEq(assetsAvailable, 0);

    skip(stakeToken.getCooldown());

    assetsAvailable = stakeToken.maxWithdraw(user);
    assertEq(assetsAvailable, amountToStake);
  }

  function test_maxRedeem(uint192 amountToStake) public {
    vm.assume(amountToStake > 0);

    uint256 shares = _deposit(amountToStake, user, user);

    uint256 zeroSharesBeforeCooldown = stakeToken.maxRedeem(user);
    assertEq(zeroSharesBeforeCooldown, 0);

    vm.startPrank(user);
    stakeToken.cooldown();

    uint256 sharesAvailable = stakeToken.maxRedeem(user);
    assertEq(sharesAvailable, 0);

    skip(stakeToken.getCooldown());

    sharesAvailable = stakeToken.maxRedeem(user);
    assertEq(sharesAvailable, shares);
  }

  function test_redeem(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    stakeToken.redeem(sharesToRedeem, user, user);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(user), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_redeemToSomeone(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    stakeToken.redeem(sharesToRedeem, someone, user);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(someone), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_redeemWithApprove(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();
    skip(stakeToken.getCooldown());
    stakeToken.approve(someone, sharesToRedeem);

    vm.stopPrank();
    vm.startPrank(someone);

    stakeToken.redeem(sharesToRedeem, someone, user);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(someone), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_redeemWithoutApprove(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.prank(user);

    stakeToken.cooldown();
    skip(stakeToken.getCooldown());

    vm.stopPrank();
    vm.startPrank(someone);

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(someone),
        0,
        sharesToRedeem
      )
    );
    stakeToken.redeem(sharesToRedeem, someone, user);
  }

  function test_redeemMoreThanHave(uint192 amountStaked) public {
    vm.assume(amountStaked > 0);

    uint256 shares = _deposit(amountStaked, user, user);

    vm.startPrank(user);

    stakeToken.cooldown();
    skip(stakeToken.getCooldown());

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector,
        address(user),
        shares + 1,
        shares
      )
    );

    stakeToken.redeem(shares + 1, user, user);
  }

  function test_withdraw(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    uint256 sharesRedeemed = stakeToken.withdraw(amountRedeemed, user, user);

    assertEq(sharesToRedeem, sharesRedeemed);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(user), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_withdrawToSomeone(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    uint256 sharesRedeemed = stakeToken.withdraw(amountRedeemed, someone, user);

    assertEq(sharesToRedeem, sharesRedeemed);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(someone), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_withdrawWithApprove(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();
    skip(stakeToken.getCooldown());
    stakeToken.approve(someone, sharesToRedeem);

    vm.stopPrank();
    vm.startPrank(someone);

    uint256 sharesRedeemed = stakeToken.withdraw(amountRedeemed, someone, user);

    assertEq(sharesRedeemed, sharesToRedeem);

    assertEq(stakeToken.totalAssets(), amountStaked - amountRedeemed);
    assertEq(underlying.balanceOf(someone), amountRedeemed);

    assertEq(stakeToken.totalSupply(), stakeToken.balanceOf(user));
    assertEq(stakeToken.balanceOf(user), stakeToken.convertToShares(amountStaked - amountRedeemed));
  }

  function test_withdrawWithoutApprove(uint192 amountStaked, uint192 amountRedeemed) public {
    vm.assume(amountStaked > 0);
    amountRedeemed = uint192(bound(amountRedeemed, 1, amountStaked));

    _deposit(amountStaked, user, user);
    uint256 sharesToRedeem = stakeToken.convertToShares(amountRedeemed);

    vm.startPrank(user);

    stakeToken.cooldown();
    skip(stakeToken.getCooldown());

    vm.stopPrank();
    vm.startPrank(someone);

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(someone),
        0,
        sharesToRedeem
      )
    );

    stakeToken.withdraw(amountRedeemed, someone, user);
  }

  function test_withdrawMoreThanHave(uint192 amountStaked) public {
    vm.assume(amountStaked > 0);

    _deposit(amountStaked, user, user);

    vm.startPrank(user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    vm.expectRevert(
      abi.encodeWithSelector(
        ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector,
        address(user),
        uint256(amountStaked) + 1,
        amountStaked
      )
    );
    stakeToken.withdraw(uint256(amountStaked) + 1, user, user);
  }

  function test_donationDoesntChangeTotalAssets(uint192 amountStaked, uint192 donation) public {
    vm.assume(amountStaked > 0);

    _deposit(amountStaked, user, user);

    uint256 totalAssets = stakeToken.totalAssets();

    _dealUnderlying(donation, someone);

    vm.startPrank(someone);

    IERC20(underlying).transfer(address(stakeToken), donation);

    vm.stopPrank();

    uint256 totalAssetsAfterDonation = stakeToken.totalAssets();

    assertEq(totalAssets, totalAssetsAfterDonation);
  }

  function test_events(uint192 amountStaked, uint224 sharesRedeemed) public {
    vm.assume(stakeToken.convertToShares(amountStaked) > sharesRedeemed && sharesRedeemed > 0);

    _dealUnderlying(amountStaked, user);

    vm.startPrank(user);

    IERC20(stakeToken.asset()).approve(address(stakeToken), amountStaked);

    vm.expectEmit(true, true, false, true);
    emit Deposit(user, user, amountStaked, stakeToken.convertToShares(amountStaked));
    stakeToken.deposit(amountStaked, user);

    stakeToken.cooldown();

    skip(stakeToken.getCooldown());

    vm.expectEmit(true, true, false, true);
    emit Withdraw(user, user, user, stakeToken.convertToAssets(sharesRedeemed), sharesRedeemed);
    stakeToken.redeem(sharesRedeemed, user, user);
  }
}
