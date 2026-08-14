// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAccessManaged} from 'aave-v4/dependencies/openzeppelin/IAccessManaged.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {Roles} from 'aave-v4/deployments/utils/libraries/Roles.sol';

import {UmbrellaSpokeE2EBaseTest} from './utils/UmbrellaSpokeE2EBase.t.sol';

import {IUmbrella} from '../../src/contracts/umbrella/interfaces/IUmbrella.sol';
import {IUmbrellaConfigurationV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {IUmbrellaV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaV4.sol';

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

  /// @dev Eliminating a deficit swaps bad debt for real liquidity, so the suppliers of the `hub` are
  /// left exactly as well off as they were
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

  /// @dev With the drawn interest accrued the added shares are worth more than one asset each, which is
  /// the case the coverage has to round through the shares it receives instead of the amount it paid
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

    _fundCoverageManager(deficit);

    vm.prank(defaultAdmin);
    uint256 covered = umbrella.coverDeficitOffset(
      address(hub),
      assetId,
      address(secondSpoke),
      deficit
    );

    // the elimination is sized from the shares received, so it never needs more of them than the
    // coverage just added, at the price of leaving up to a couple of wei of the deficit standing
    assertLe(covered, deficit);
    assertGe(covered, deficit - 2);

    assertEq(_spokeDeficit(address(secondSpoke)), deficit - covered);
    assertEq(
      umbrella.getDeficitOffset(address(hub), assetId, address(secondSpoke)),
      offset - covered
    );
    assertEq(underlying.balanceOf(address(umbrella)), 0);
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

  /// @dev A covered `spoke` never outlives the configuration of its pair, so the deficit reported while the
  /// coverage was decommissioned cannot be slashed once a `SlashingConfig` is installed again
  function test_e2e_decommissionedCoverageDoesNotSlashTheDeficitItMissed() public {
    _coverSpoke(address(lendingSpoke));

    // the last configuration cannot be dropped while a `spoke` is still listed in the coverage
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokesStillCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(_removalPairs());

    _uncoverSpoke(address(lendingSpoke));

    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(_removalPairs());

    // the deficit reported while nothing was covered
    _reportDeficit(lendingSpoke, 1_000 * 1e6);
    uint256 missedDeficit = _spokeDeficit(address(lendingSpoke));
    assertGt(missedDeficit, 0);

    // re-listing the `spoke` requires the pair to be configured first
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationV4.AssetCoverageNotSetup.selector)
    );
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(lendingSpoke)));

    _configureCoverage();
    _coverSpoke(address(lendingSpoke));

    // and it takes over the missed deficit as its `deficitOffset`, so nothing of it is slashable
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

    vm.expectRevert(abi.encodeWithSelector(IUmbrella.ZeroDeficitToCover.selector));
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
