// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

import {UmbrellaSpokeBaseTest} from './utils/UmbrellaSpokeBase.t.sol';
import {MockHub} from './utils/mocks/MockHub.sol';

import {IUmbrellaBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaBase.sol';
import {IUmbrellaConfigurationV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {IUmbrellaV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaV4.sol';

contract UmbrellaSpoke_Test is UmbrellaSpokeBaseTest {
  function test_tokenForDeficitCoverage() public view {
    assertEq(
      umbrella.tokenForDeficitCoverage(address(hub), ASSET_6_DECIMALS),
      address(underlying6Decimals)
    );
    assertEq(
      umbrella.tokenForDeficitCoverage(address(hub), ASSET_18_DECIMALS),
      address(underlying18Decimals)
    );
    assertEq(
      umbrella.tokenForDeficitCoverage(address(anotherHub), ASSET_6_DECIMALS),
      address(anotherUnderlying6Decimals)
    );
    assertEq(umbrella.tokenForDeficitCoverage(address(hub), UNLISTED_ASSET), address(0));
  }

  function test_setDeficitOffset(uint256 amount) public {
    amount = bound(amount, 1_000 * 1e6, type(uint256).max);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.DeficitOffsetChanged(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      amount
    );

    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, amount);

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), amount);

    // it can always be brought back to the deficit reported by the `spoke`
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
  }

  /// @dev A `spoke` can only be listed while its pair is configured, so an unconfigured pair covers no `spoke`
  function test_setDeficitOffsetNotSetup(uint256 amount) public {
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokeNotCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, amount);
  }

  function test_setDeficitOffsetSpokeNotCovered(uint256 amount) public {
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokeNotCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeB, amount);
  }

  function test_setDeficitOffsetLowerThanActualDeficit(uint256 amount) public {
    amount = bound(amount, 0, 1_000 * 1e6 - 1);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.TooMuchDeficitOffsetReduction.selector));
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, amount);
  }

  /// @dev The `pendingDeficit` is already slashed, so the offset may go below the reported deficit by that much
  function test_setDeficitOffsetTakesPendingDeficitIntoAccount() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 400 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 600 * 1e6);

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 600 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.TooMuchDeficitOffsetReduction.selector));
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 600 * 1e6 - 1);
  }

  function test_coverDeficitOffset() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);

    uint256 hubLiquidityBefore = hub.getAssetLiquidity(ASSET_6_DECIMALS);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.DeficitOffsetCovered(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      500 * 1e6
    );

    assertEq(covered, 500 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 500 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);
    // the funds are added to the `hub`, nothing is left behind
    assertEq(underlying6Decimals.balanceOf(address(umbrella)), 0);
    assertEq(hub.getAssetLiquidity(ASSET_6_DECIMALS), hubLiquidityBefore + 500 * 1e6);

    vm.prank(defaultAdmin);
    covered = umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    assertEq(covered, 500 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 0);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 0);
    assertEq(hub.getAssetLiquidity(ASSET_6_DECIMALS), hubLiquidityBefore + 1_000 * 1e6);
  }

  /// @dev Only the deficit actually reported by the `spoke` can be covered, not a manually inflated offset
  function test_coverDeficitOffsetWithManualIncrease() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_500 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 2_000 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      1_500 * 1e6
    );

    assertEq(covered, 1_000 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 0);
    // not zero, cause the offset was increased by 1000 on top of the reported deficit
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 500 * 1e6);

    // the offset can now be brought back to zero, cause the reported deficit is fully eliminated
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 0);
  }

  function test_coverDeficitOffsetPartOfTheOffsetIsAlreadySlashed() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    // 400 of the reported deficit is backed by already slashed funds
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 400 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      1_000 * 1e6
    );

    assertEq(covered, 600 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 400 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 400 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 400 * 1e6);
  }

  function test_coverDeficitOffsetPendingExceedsSpokeDeficit() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 500 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1e6);
  }

  function test_coverDeficitOffsetZeroDeficit() public {
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);
  }

  function test_coverDeficitOffsetZeroAmount() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 0);
  }

  function test_coverDeficitOffsetSpokeNotCovered() public {
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokeNotCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeB, 1e6);
  }

  function test_coverPendingDeficit() public {
    _setUpSlashedSpoke(1_000 * 1e6);
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.PendingDeficitCovered(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverPendingDeficit(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      500 * 1e6
    );

    assertEq(covered, 500 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 500 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 500 * 1e6);

    // an amount above the `pendingDeficit` covers only the `pendingDeficit`
    vm.prank(defaultAdmin);
    covered = umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6 + 1);

    assertEq(covered, 500 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 0);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 0);
  }

  function test_coverPendingDeficitZeroPending() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
  }

  function test_coverPendingDeficitZeroAmount() public {
    _setUpSlashedSpoke(1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 0);
  }

  function test_coverPendingDeficitSpokeNotCovered() public {
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokeNotCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeB, 1e6);
  }

  function test_coverSpokeDeficit() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _fundCoverageManager(address(underlying6Decimals), 1_100 * 1e6);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.SpokeDeficitCovered(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverSpokeDeficit(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      1_100 * 1e6
    );

    assertEq(covered, 1_000 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 0);

    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 0);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    assertEq(underlying6Decimals.balanceOf(defaultAdmin), 100 * 1e6);
  }

  function test_coverSpokeDeficitPartially() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _fundCoverageManager(address(underlying6Decimals), 400 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 400 * 1e6);

    assertEq(covered, 400 * 1e6);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 600 * 1e6);
  }

  function test_coverSpokeDeficitZeroDeficit() public {
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
  }

  function test_coverSpokeDeficitForConfiguredSpoke() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_100 * 1e6);

    // a `SlashingConfig` is set and the offset was initialized on the listing
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaV4.SpokeIsConfigured.selector));
    vm.prank(defaultAdmin);
    umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_100 * 1e6);

    // covering the offset isn't enough while the `SlashingConfig` is in place
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaV4.SpokeIsConfigured.selector));
    vm.prank(defaultAdmin);
    umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    // with the coverage of the `spoke` and the configuration removed the remaining deficit can be
    // covered directly, the `spoke` first, as a covered one cannot outlive the configuration of its pair
    vm.startPrank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );
    vm.stopPrank();

    _fundCoverageManager(address(underlying6Decimals), 500 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    assertEq(covered, 500 * 1e6);
  }

  function test_coverSpokeDeficitWithPendingDeficit() public {
    _setUpSlashedSpoke(1_000 * 1e6);
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );
    vm.stopPrank();

    // the `pendingDeficit` is kept for a re-listing of the `spoke`, so it has to be covered through
    // `coverPendingDeficit` and blocks a direct coverage even once the pair is unconfigured
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaV4.SpokeIsConfigured.selector));
    vm.prank(defaultAdmin);
    umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
  }

  function test_slash() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.StakeTokenSlashed(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      address(stakeWith6Decimals),
      1_000 * 1e6,
      0
    );

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(coveredDeficit, 1_000 * 1e6);
    assertEq(stakeWith6Decimals.totalAssets(), 9_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 1_000 * 1e6);

    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);
    // the deficit stays on the `hub` until it is covered
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
  }

  function test_slashHalfDeficit() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 500 * 1e6 + 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    // slashed up to `MIN_ASSETS_REMAINING`
    assertEq(coveredDeficit, 500 * 1e6);
    assertEq(stakeWith6Decimals.totalAssets(), 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 500 * 1e6);

    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 500 * 1e6);
  }

  function test_slashWith18Decimals() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_18_DECIMALS, address(stakeWith18Decimals), 0)
    );
    _listAndCoverSpoke(address(hub), ASSET_18_DECIMALS, spokeA);
    _fillStake(address(stakeWith18Decimals), 10_000 * 1e18);

    hub.addSpokeDeficit(ASSET_18_DECIMALS, spokeA, 1_000 * 1e18);

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_18_DECIMALS, spokeA);

    assertEq(coveredDeficit, 1_000 * 1e18);
    assertEq(underlying18Decimals.balanceOf(collector), 1_000 * 1e18);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_18_DECIMALS, spokeA), 1_000 * 1e18);
  }

  /// @dev The asset and the stake underlying are priced independently, so the slashed amount follows their ratio
  function test_slashWithDifferentPrices() public {
    _updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        _newOracle(2e8, ORACLE_DECIMALS),
        _newOracle(1e8, ORACLE_DECIMALS)
      )
    );
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(coveredDeficit, 1_000 * 1e6);
    // the asset is worth twice the stake underlying, so twice as much of it is slashed
    assertEq(underlying6Decimals.balanceOf(collector), 2_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
  }

  function test_slashWithNonZeroLiquidationFee(uint256 liquidationFee) public {
    liquidationFee = bound(liquidationFee, 0, 10_000);

    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), liquidationFee)
    );
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);
    _fillStake(address(stakeWith6Decimals), 30_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    uint256 expectedFee = (1_000 * 1e6 * liquidationFee) / 10_000;

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.StakeTokenSlashed(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      address(stakeWith6Decimals),
      1_000 * 1e6,
      expectedFee
    );

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(coveredDeficit, 1_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), 1_000 * 1e6 + expectedFee);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
  }

  /// @dev The `liquidationFee` is applied rounding up, so that the fee is never short by a wei
  function test_slashRoundsLiquidationFeeUp() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 1)
    );
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);
    _fillStake(address(stakeWith6Decimals), 30_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000_001);

    // 1 bps of 1_000_001 is 100.0001
    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.StakeTokenSlashed(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      address(stakeWith6Decimals),
      1_000_001,
      101
    );

    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(underlying6Decimals.balanceOf(collector), 1_000_001 + 101);
  }

  function test_slashWithNonZeroLiquidationFeeExceedingStake(uint256 liquidationFee) public {
    liquidationFee = bound(liquidationFee, 1, 10_000);

    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), liquidationFee)
    );
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 10_000 * 1e6);

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    // the fee is taken on top of the deficit, so less than the whole deficit ends up covered
    assertLt(coveredDeficit, 10_000 * 1e6);
    assertEq(underlying6Decimals.balanceOf(collector), (10_000 - 1) * 1e6);
    assertEq(stakeWith6Decimals.totalAssets(), 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), coveredDeficit);
  }

  function test_slashNoDeficit() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);
  }

  function test_slashSpokeNotCovered() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeB);
  }

  /// @dev Decommissioning the coverage of a pair unlists its `spoke`s first, so that no `spoke` is ever
  /// covered while the pair has no `SlashingConfig`
  function test_slashNoConfig() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );
    vm.stopPrank();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);
  }

  function test_slashSeveralConfigs() public {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    address anotherStake = _createStakeToken(address(underlying6Decimals), 'v2');
    _updateSlashingConfigs(_slashingConfigs(address(hub), ASSET_6_DECIMALS, anotherStake, 0));
    _fillStake(anotherStake, 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);
  }

  function test_slashOnlyNewDeficit() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    // the deficit reported before the listing isn't slashable
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 400 * 1e6);

    uint256 coveredDeficit = umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(coveredDeficit, 400 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 400 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);

    // and a repeated slashing has nothing left to slash
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.CannotSlash.selector));
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);
  }

  function test_withdrawStrandedFunds() public {
    uint256 strandedAmount = 100 * 1e6;
    uint256 withdrawnAmount = 40 * 1e6;

    underlying6Decimals.mint(address(hub), strandedAmount);
    hub.seedSpokeShares(ASSET_6_DECIMALS, address(umbrella), strandedAmount);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.StrandedFundsWithdrawn(
      address(hub),
      ASSET_6_DECIMALS,
      withdrawnAmount,
      withdrawnAmount
    );

    vm.prank(defaultAdmin);
    uint256 removedShares = umbrella.withdrawStrandedFunds(
      address(hub),
      ASSET_6_DECIMALS,
      withdrawnAmount
    );

    assertEq(removedShares, withdrawnAmount);
    assertEq(
      hub.getSpokeAddedShares(ASSET_6_DECIMALS, address(umbrella)),
      strandedAmount - withdrawnAmount
    );
    assertEq(underlying6Decimals.balanceOf(collector), withdrawnAmount);
  }

  function test_withdrawStrandedFundsMoreThanAvailable() public {
    underlying6Decimals.mint(address(hub), 100 * 1e6);
    hub.seedSpokeShares(ASSET_6_DECIMALS, address(umbrella), 100 * 1e6);

    uint256 liquidity = hub.getAssetLiquidity(ASSET_6_DECIMALS);

    vm.expectRevert(abi.encodeWithSelector(MockHub.InsufficientLiquidity.selector));
    vm.prank(defaultAdmin);
    umbrella.withdrawStrandedFunds(address(hub), ASSET_6_DECIMALS, liquidity + 1);
  }

  /// @dev The `Hub` mints added shares rounding down and burns them rounding up, so covering the full
  /// amount transferred would need one share more than the coverage just added
  function test_coverDeficitOffsetWithAppreciatedShares() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 500 * 1e6);

    // the added shares appreciated by 10% through the interest paid by the borrowers
    hub.accrueInterest(ASSET_6_DECIMALS, hub.getAssetLiquidity(ASSET_6_DECIMALS) / 10);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      500 * 1e6
    );

    // the shares received cannot buy back the whole amount, the dust stays in the `Hub`
    assertLe(covered, 500 * 1e6);
    assertGe(covered, 500 * 1e6 - 2);

    assertEq(
      umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA),
      1_000 * 1e6 - covered
    );
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 1_000 * 1e6 - covered);
    assertEq(underlying6Decimals.balanceOf(address(umbrella)), 0);
  }

  function test_coverRevertsWhenUmbrellaIsNotAnActiveSpoke() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    hub.setSpokeDeactivated(address(umbrella), true);

    vm.expectRevert(abi.encodeWithSelector(MockHub.SpokeNotActive.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
  }

  function test_coverRevertsWhenUmbrellaCannotEliminateDeficit() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    _setUpDefaultCoverage();
    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    hub.setDeficitEliminatorRevoked(address(umbrella), true);

    vm.expectRevert(abi.encodeWithSelector(MockHub.NotAuthorized.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
  }

  function test_deficitIsCoveredPerSpoke() public {
    _setUpDefaultCoverage();
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeB);
    _fillStake(address(stakeWith6Decimals), 10_000 * 1e6);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 400 * 1e6);

    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeB), 0);
    assertEq(umbrella.getTotalPendingDeficit(address(hub), ASSET_6_DECIMALS), 1_000 * 1e6);
    // only the deficit of the slashed `spoke` is now waiting to be covered
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 400 * 1e6);

    _fundCoverageManager(address(underlying6Decimals), 1_000 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeA), 0);
    assertEq(hub.getSpokeDeficit(ASSET_6_DECIMALS, spokeB), 400 * 1e6);
  }

  function test_InvalidRoles() public {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.withdrawStrandedFunds(address(hub), ASSET_6_DECIMALS, 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.coverDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.coverPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.coverSpokeDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 0);
  }

  /// @dev Brings the default `spoke` to a state where the whole reported deficit is already slashed
  function _setUpSlashedSpoke(uint256 deficit) internal {
    _setUpDefaultCoverage();
    _fillStake(address(stakeWith6Decimals), deficit * 10);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, deficit);
    umbrella.slash(address(hub), ASSET_6_DECIMALS, spokeA);
  }
}
