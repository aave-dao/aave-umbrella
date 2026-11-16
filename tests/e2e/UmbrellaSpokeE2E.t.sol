// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAccessManaged} from 'aave-v4/dependencies/openzeppelin/IAccessManaged.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {Roles} from 'aave-v4/deployments/utils/libraries/Roles.sol';

import {UmbrellaSpokeE2EBaseTest} from './utils/UmbrellaSpokeE2EBase.t.sol';

import {IUmbrellaBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaBase.sol';
import {IUmbrellaConfigurationV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {IUmbrellaStkManager} from '../../src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol';
import {IUmbrellaV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaV4.sol';

import {UmbrellaStakeToken} from '../../src/contracts/stakeToken/UmbrellaStakeToken.sol';

import {MockOracleWithDecimals} from '../umbrella/utils/mocks/MockOracleWithDecimals.sol';

contract UmbrellaSpoke_E2E_Test is UmbrellaSpokeE2EBaseTest {
  /// @dev The whole lifecycle against a real `Hub`: a `spoke` writes off drawn liquidity, `Umbrella` takes
  /// over the deficit reported after its listing, slashes for it and eventually eliminates all of it
  function test_e2e_slashAndCoverDeficit() public {
    _reportDeficit(lendingSpoke, 1_000 * 1e6);

    uint256 deficitBeforeListing = _spokeDeficit(address(lendingSpoke));
    assertGt(deficitBeforeListing, 0);

    _coverSpoke(address(lendingSpoke));

    // the deficit which existed before the listing is not slashable
    assertEq(
      umbrella.getDeficitOffset(address(hub), assetId, address(lendingSpoke)),
      deficitBeforeListing
    );
    (bool slashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      assetId,
      address(lendingSpoke)
    );
    assertFalse(slashable);
    assertEq(newDeficit, 0);

    _reportDeficit(lendingSpoke, 400 * 1e6);
    _fillStake(10_000 * 1e6);

    (slashable, newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      assetId,
      address(lendingSpoke)
    );
    assertTrue(slashable);
    assertEq(newDeficit, _spokeDeficit(address(lendingSpoke)) - deficitBeforeListing);

    uint256 slashed = umbrella.slash(address(hub), assetId, address(lendingSpoke));

    assertEq(slashed, newDeficit);
    assertEq(underlying.balanceOf(collector), newDeficit);
    assertEq(stakeToken.totalAssets(), 10_000 * 1e6 - newDeficit);
    assertEq(umbrella.getPendingDeficit(address(hub), assetId, address(lendingSpoke)), newDeficit);

    // the funds slashed cover the deficit on the `hub`
    uint256 liquidityBefore = hub.getAssetLiquidity(assetId);
    _fundCoverageManager(newDeficit);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverPendingDeficit(
      address(hub),
      assetId,
      address(lendingSpoke),
      newDeficit
    );

    assertEq(covered, newDeficit);
    assertEq(umbrella.getPendingDeficit(address(hub), assetId, address(lendingSpoke)), 0);
    assertEq(hub.getAssetLiquidity(assetId), liquidityBefore + covered);
    assertEq(_spokeDeficit(address(lendingSpoke)), deficitBeforeListing);

    // and the rest is covered straight from the treasury
    _fundCoverageManager(deficitBeforeListing);

    vm.prank(defaultAdmin);
    covered = umbrella.coverDeficitOffset(
      address(hub),
      assetId,
      address(lendingSpoke),
      deficitBeforeListing
    );

    assertEq(covered, deficitBeforeListing);
    assertEq(umbrella.getDeficitOffset(address(hub), assetId, address(lendingSpoke)), 0);
    assertEq(_spokeDeficit(address(lendingSpoke)), 0);
    assertEq(hub.getAssetDeficitRay(assetId), 0);

    // nothing of the coverage is left stranded inside the `hub`
    assertEq(hub.getSpokeAddedShares(assetId, address(umbrella)), 0);
    assertEq(underlying.balanceOf(address(umbrella)), 0);
  }

  /// @dev Eliminating a deficit swaps bad debt for real liquidity, so neither the added shares of the
  /// `hub` nor the assets they are worth to the other spokes change
  function test_e2e_coverageDoesNotChangeOtherSuppliers() public {
    _reportDeficit(lendingSpoke, 1_000 * 1e6);

    uint256 suppliedAssetsBefore = hub.getSpokeAddedAssets(assetId, address(lendingSpoke));
    uint256 addedSharesBefore = hub.getAddedShares(assetId);

    _coverSpoke(address(lendingSpoke));
    _fundCoverageManager(1_000 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), assetId, address(lendingSpoke), 1_000 * 1e6);

    assertEq(hub.getSpokeAddedAssets(assetId, address(lendingSpoke)), suppliedAssetsBefore);
    assertEq(hub.getAddedShares(assetId), addedSharesBefore);
    assertEq(_spokeDeficit(address(lendingSpoke)), 0);
  }

  /// @dev Once the drawn interest has accrued the added shares are worth more than one asset each, which
  /// is why the coverage sizes the elimination from the shares it receives and not from the amount it paid
  function test_e2e_coverDeficitWithAppreciatedShares() public {
    lendingSpoke.draw(assetId, 500_000 * 1e6, borrower);

    vm.warp(block.timestamp + 365 days);

    // the value of the added shares has grown with the interest owed
    assertGt(hub.getSpokeAddedAssets(assetId, address(lendingSpoke)), SEEDED_LIQUIDITY);

    _reportDeficit(secondSpoke, 1_000 * 1e6);

    _coverSpoke(address(secondSpoke));

    uint256 deficit = _spokeDeficit(address(secondSpoke));
    uint256 offset = umbrella.getDeficitOffset(address(hub), assetId, address(secondSpoke));
    assertEq(offset, deficit);

    _fundCoverageManager(deficit + 2);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      assetId,
      address(secondSpoke),
      deficit
    );

    // the coverage pulls the assets worth the shares the elimination burns, so the whole deficit is
    // eliminated at the price of up to a couple of wei more paid by the caller
    assertEq(covered, deficit);

    assertEq(_spokeDeficit(address(secondSpoke)), 0);
    assertEq(umbrella.getDeficitOffset(address(hub), assetId, address(secondSpoke)), 0);
    assertEq(underlying.balanceOf(address(umbrella)), 0);
  }

  /// @dev With appreciated shares, `add()` of a single wei mints no share, so the last wei must still be coverable
  function test_e2e_coverLastWeiOfPendingDeficitWithAppreciatedShares() public {
    lendingSpoke.draw(assetId, 500_000 * 1e6, borrower);
    vm.warp(block.timestamp + 365 days);

    _coverSpoke(address(secondSpoke));
    _fillStake(10_000 * 1e6);
    _reportDeficit(secondSpoke, 1_000 * 1e6);

    uint256 slashed = umbrella.slash(address(hub), assetId, address(secondSpoke));
    _fundCoverageManager(slashed + 4);

    vm.startPrank(defaultAdmin);
    umbrella.coverPendingDeficit(address(hub), assetId, address(secondSpoke), slashed - 1);
    uint256 covered = umbrella.coverPendingDeficit(address(hub), assetId, address(secondSpoke), 1);
    vm.stopPrank();

    assertEq(covered, 1);
    assertEq(umbrella.getPendingDeficit(address(hub), assetId, address(secondSpoke)), 0);
    assertEq(_spokeDeficit(address(secondSpoke)), 0);
  }

  /// @dev As in V3, replacing a `UmbrellaStakeToken` by removing the old configuration first re-initializes the
  /// `deficitOffset`, so the new stakers are not slashed for a deficit the old ones did not cover
  function test_e2e_replaceStakeTokenDoesNotSlashNewStakersForOldDeficit() public {
    _coverSpoke(address(lendingSpoke));
    // the old stake is empty, so nothing of this deficit can be slashed from it
    _reportDeficit(lendingSpoke, 1_000 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(_removalPairs());

    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying),
      cooldown: 2 weeks,
      unstakeWindow: 2 days,
      suffix: 'v2'
    });

    vm.prank(defaultAdmin);
    stakeToken = UmbrellaStakeToken(umbrella.createStakeTokens(stakeSetups)[0]);
    _configureCoverage();
    _fillStake(10_000 * 1e6);

    (bool slashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      assetId,
      address(lendingSpoke)
    );
    assertFalse(slashable);
    assertEq(newDeficit, 0);
  }

  /// @dev Funds are only left behind when the deficit `Umbrella` tracks outlives the one on the `hub`,
  /// e.g. because a third party eliminated part of it directly
  function test_e2e_withdrawStrandedFundsAfterDesync() public {
    _coverSpoke(address(lendingSpoke));
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _fillStake(10_000 * 1e6);

    uint256 slashed = umbrella.slash(address(hub), assetId, address(lendingSpoke));
    uint256 eliminatedByThirdParty = slashed / 2;

    accessManager.grantRole(Roles.HUB_DEFICIT_ELIMINATOR_ROLE, address(lendingSpoke), 0);
    lendingSpoke.eliminateDeficit(assetId, eliminatedByThirdParty, address(lendingSpoke));

    _fundCoverageManager(slashed);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverPendingDeficit(
      address(hub),
      assetId,
      address(lendingSpoke),
      slashed
    );

    // only the deficit still standing on the `hub` could be eliminated
    assertEq(covered, slashed - eliminatedByThirdParty);
    assertEq(_spokeDeficit(address(lendingSpoke)), 0);
    // `Umbrella` keeps tracking the rest, which is now backed by an added position instead of a deficit
    assertEq(
      umbrella.getPendingDeficit(address(hub), assetId, address(lendingSpoke)),
      eliminatedByThirdParty
    );

    uint256 strandedAssets = hub.getSpokeAddedAssets(assetId, address(umbrella));
    assertApproxEqAbs(strandedAssets, eliminatedByThirdParty, 1);

    vm.prank(defaultAdmin);
    umbrella.withdrawStrandedFunds(address(hub), assetId, strandedAssets);

    assertEq(underlying.balanceOf(collector), slashed + strandedAssets);
    assertEq(hub.getSpokeAddedAssets(assetId, address(umbrella)), 0);
  }

  function test_e2e_coverSpokeDeficitWithoutConfiguration() public {
    _reportDeficit(secondSpoke, 1_000 * 1e6);
    uint256 deficit = _spokeDeficit(address(secondSpoke));

    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(_removalPairs());

    _fundCoverageManager(deficit);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverSpokeDeficit(
      address(hub),
      assetId,
      address(secondSpoke),
      deficit
    );

    assertEq(covered, deficit);
    assertEq(_spokeDeficit(address(secondSpoke)), 0);
  }

  /// @dev As in V3, the deficit reported while the hub asset had no `SlashingConfig` cannot be slashed once one is installed again,
  /// whatever the order in which the coverage of the `spoke` and the configuration of the hub asset are handled
  function test_e2e_decommissionedCoverageDoesNotSlashTheDeficitItMissed() public {
    _coverSpoke(address(lendingSpoke));

    // the last configuration can be dropped while the `spoke` is still covered
    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(_removalPairs());

    // the deficit reported while nothing was configured
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    uint256 missedDeficit = _spokeDeficit(address(lendingSpoke));
    assertGt(missedDeficit, 0);

    _configureCoverage();

    // the `spoke` takes over the missed deficit as its `deficitOffset`, so nothing of it is slashable
    assertEq(
      umbrella.getDeficitOffset(address(hub), assetId, address(lendingSpoke)),
      missedDeficit
    );

    (bool slashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      assetId,
      address(lendingSpoke)
    );
    assertFalse(slashable);
    assertEq(newDeficit, 0);

    // only the deficit reported from now on is
    _reportDeficit(lendingSpoke, 400 * 1e6);

    (slashable, newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      assetId,
      address(lendingSpoke)
    );
    assertTrue(slashable);
    assertEq(newDeficit, _spokeDeficit(address(lendingSpoke)) - missedDeficit);
  }

  /// @dev As in V3 with the `Pool` oracle, the asset is priced by the `AaveOracle` of the slashed `spoke`
  function test_e2e_slashUsesTheOracleOfTheSpoke() public {
    _coverSpoke(address(lendingSpoke));
    _fillStake(10_000 * 1e6);

    lendingSpoke.setReserveSource(
      assetId,
      address(new MockOracleWithDecimals(int256(ORACLE_PRICE) * 2, ORACLE_DECIMALS))
    );

    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    uint256 deficit = _spokeDeficit(address(lendingSpoke));

    uint256 covered = umbrella.slash(address(hub), assetId, address(lendingSpoke));

    assertEq(covered, deficit);
    // the asset is worth twice the stake underlying for this `spoke`, so twice as much of it is slashed
    assertEq(underlying.balanceOf(collector), deficit * 2);
  }

  function test_e2e_slashableDeficitAcrossSpokes() public {
    _coverSpoke(address(lendingSpoke));
    _coverSpoke(address(secondSpoke));

    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _reportDeficit(secondSpoke, 400 * 1e6);

    uint256 lendingDeficit = _spokeDeficit(address(lendingSpoke));
    uint256 secondDeficit = _spokeDeficit(address(secondSpoke));

    assertEq(
      umbrella.getTotalSlashableDeficit(address(hub), assetId),
      lendingDeficit + secondDeficit
    );
    assertEq(umbrella.getTotalDeficitOffset(address(hub), assetId), 0);

    // the `hub` wide deficit matches the sum tracked per `spoke`
    assertEq(_fromRayUp(hub.getAssetDeficitRay(assetId)), lendingDeficit + secondDeficit);

    _fillStake(10_000 * 1e6);
    umbrella.slash(address(hub), assetId, address(lendingSpoke));

    assertEq(umbrella.getTotalPendingDeficit(address(hub), assetId), lendingDeficit);
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), assetId), secondDeficit);
  }

  function test_e2e_coverRevertsWithoutDeficitEliminatorRole() public {
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _coverSpoke(address(lendingSpoke));
    _fundCoverageManager(1_000 * 1e6);

    accessManager.revokeRole(Roles.HUB_DEFICIT_ELIMINATOR_ROLE, address(umbrella));

    vm.expectRevert(
      abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, address(umbrella))
    );
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), assetId, address(lendingSpoke), 1_000 * 1e6);
  }

  function test_e2e_coverRevertsWhenUmbrellaIsNotAnActiveSpoke() public {
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _coverSpoke(address(lendingSpoke));
    _fundCoverageManager(1_000 * 1e6);

    hub.updateSpokeConfig(
      assetId,
      address(umbrella),
      IHub.SpokeConfig({
        addCap: hub.MAX_ALLOWED_SPOKE_CAP(),
        drawCap: hub.MAX_ALLOWED_SPOKE_CAP(),
        riskPremiumThreshold: hub.MAX_RISK_PREMIUM_THRESHOLD(),
        active: false,
        halted: false
      })
    );

    vm.expectRevert(abi.encodeWithSelector(IHub.SpokeNotActive.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), assetId, address(lendingSpoke), 1_000 * 1e6);
  }

  function test_e2e_configurationValidatesAgainstTheHub() public {
    // the `hub` reports the asset decimals used to validate the stake token
    (address assetUnderlying, uint8 assetDecimals) = hub.getAssetUnderlyingAndDecimals(assetId);

    assertEq(assetUnderlying, address(underlying));
    assertEq(assetDecimals, 6);
    assertEq(umbrella.tokenForDeficitCoverage(address(hub), assetId), address(underlying));

    // a `spoke` which the `hub` does not know cannot be listed in the coverage
    IUmbrellaConfigurationV4.SpokeCoverage[]
      memory coverages = new IUmbrellaConfigurationV4.SpokeCoverage[](1);

    coverages[0] = IUmbrellaConfigurationV4.SpokeCoverage({
      hub: address(hub),
      assetId: assetId,
      spoke: user
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.InvalidSpoke.selector));
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(coverages);
  }

  function test_e2e_coverMoreThanTheReportedDeficit() public {
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _coverSpoke(address(lendingSpoke));

    uint256 deficit = _spokeDeficit(address(lendingSpoke));

    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), assetId, address(lendingSpoke), 2_000 * 1e6);

    _fundCoverageManager(2_000 * 1e6);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      assetId,
      address(lendingSpoke),
      2_000 * 1e6
    );

    // only what the `hub` actually reports as a deficit can be eliminated
    assertEq(covered, deficit);
    assertEq(_spokeDeficit(address(lendingSpoke)), 0);
    assertEq(underlying.balanceOf(defaultAdmin), 2_000 * 1e6 - deficit);
  }

  function test_e2e_coverWithNothingToCover() public {
    _coverSpoke(address(lendingSpoke));
    _fundCoverageManager(1_000 * 1e6);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaBase.ZeroDeficitToCover.selector));
    vm.prank(defaultAdmin);
    umbrella.coverDeficitOffset(address(hub), assetId, address(lendingSpoke), 1_000 * 1e6);
  }

  function test_e2e_slashEmitsHubAndSpokeIdentity() public {
    _coverSpoke(address(lendingSpoke));
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    _fillStake(10_000 * 1e6);

    uint256 deficit = _spokeDeficit(address(lendingSpoke));

    vm.expectEmit(address(umbrella));
    emit IUmbrellaV4.StakeTokenSlashed(
      address(hub),
      assetId,
      address(lendingSpoke),
      address(stakeToken),
      deficit,
      0
    );

    umbrella.slash(address(hub), assetId, address(lendingSpoke));
  }

  function _removalPairs()
    internal
    view
    returns (IUmbrellaConfigurationV4.SlashingConfigRemoval[] memory removals)
  {
    removals = new IUmbrellaConfigurationV4.SlashingConfigRemoval[](1);
    removals[0] = IUmbrellaConfigurationV4.SlashingConfigRemoval({
      hub: address(hub),
      assetId: assetId,
      umbrellaStake: address(stakeToken)
    });
  }
}
