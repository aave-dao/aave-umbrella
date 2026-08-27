// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

import {UmbrellaSpokeBaseTest, UmbrellaSpokeHarness} from './utils/UmbrellaSpokeBase.t.sol';

import {IUmbrellaConfigurationBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationBase.sol';
import {IUmbrellaConfigurationV4} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {UmbrellaSpoke} from '../../src/contracts/umbrella/UmbrellaSpoke.sol';

contract UmbrellaSpoke_Configuration_Test is UmbrellaSpokeBaseTest {
  uint256 internal constant RAY = 1e27;

  function test_setup() public view {
    assertEq(address(umbrella.TRANSPARENT_PROXY_FACTORY()), address(transparentProxyFactory));

    assertEq(umbrella.UMBRELLA_STAKE_TOKEN_IMPL(), address(umbrellaStakeTokenImpl));
    assertEq(umbrella.SLASHED_FUNDS_RECIPIENT(), collector);
    assertEq(umbrella.SUPER_ADMIN(), defaultAdmin);

    assertTrue(umbrella.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin));
    assertTrue(umbrella.hasRole(COVERAGE_MANAGER_ROLE, defaultAdmin));
    assertTrue(umbrella.hasRole(RESCUE_GUARDIAN_ROLE, defaultAdmin));
    assertTrue(umbrella.hasRole(PAUSE_GUARDIAN_ROLE, defaultAdmin));
    assertTrue(umbrella.hasRole(SPOKE_COVERAGE_MANAGER_ROLE, defaultAdmin));
  }

  function test_invalidInit() public {
    UmbrellaSpokeHarness umbrellaImpl = new UmbrellaSpokeHarness();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    transparentProxyFactory.create(
      address(umbrellaImpl),
      defaultAdmin,
      abi.encodeWithSelector(
        UmbrellaSpoke.initialize.selector,
        address(0),
        collector,
        umbrellaStakeTokenImpl,
        address(transparentProxyFactory)
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    transparentProxyFactory.create(
      address(umbrellaImpl),
      defaultAdmin,
      abi.encodeWithSelector(
        UmbrellaSpoke.initialize.selector,
        defaultAdmin,
        address(0),
        umbrellaStakeTokenImpl,
        address(transparentProxyFactory)
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    transparentProxyFactory.create(
      address(umbrellaImpl),
      defaultAdmin,
      abi.encodeWithSelector(
        UmbrellaSpoke.initialize.selector,
        defaultAdmin,
        collector,
        address(0),
        address(transparentProxyFactory)
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    transparentProxyFactory.create(
      address(umbrellaImpl),
      defaultAdmin,
      abi.encodeWithSelector(
        UmbrellaSpoke.initialize.selector,
        defaultAdmin,
        collector,
        umbrellaStakeTokenImpl,
        address(0)
      )
    );
  }

  function test_updateSlashingConfigsOkSetup() public {
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    IUmbrellaConfigurationV4.SlashingConfigUpdate[]
      memory configs = new IUmbrellaConfigurationV4.SlashingConfigUpdate[](2);

    configs[0] = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      0,
      assetOracle,
      stakeUnderlyingOracle
    )[0];
    configs[1] = _slashingConfigs(
      address(hub),
      ASSET_18_DECIMALS,
      address(stakeWith18Decimals),
      100,
      assetOracle,
      stakeUnderlyingOracle
    )[0];

    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);

    IUmbrellaConfigurationBase.SlashingConfig memory config6Decimals = umbrella
      .getAssetSlashingConfig(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals));

    assertEq(config6Decimals.umbrellaStake, address(stakeWith6Decimals));
    assertEq(config6Decimals.umbrellaStakeUnderlyingOracle, stakeUnderlyingOracle);
    assertEq(config6Decimals.liquidationFee, 0);

    IUmbrellaConfigurationBase.SlashingConfig memory config18Decimals = umbrella
      .getAssetSlashingConfig(address(hub), ASSET_18_DECIMALS, address(stakeWith18Decimals));

    assertEq(config18Decimals.umbrellaStake, address(stakeWith18Decimals));
    assertEq(config18Decimals.umbrellaStakeUnderlyingOracle, stakeUnderlyingOracle);
    assertEq(config18Decimals.liquidationFee, 100);

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs6Decimals = umbrella
      .getAssetSlashingConfigs(address(hub), ASSET_6_DECIMALS);

    assertEq(configs6Decimals.length, 1);
    assertEq(configs6Decimals[0].umbrellaStake, config6Decimals.umbrellaStake);
    assertEq(
      configs6Decimals[0].umbrellaStakeUnderlyingOracle,
      config6Decimals.umbrellaStakeUnderlyingOracle
    );
    assertEq(configs6Decimals[0].liquidationFee, config6Decimals.liquidationFee);

    assertEq(umbrella.getStakeTokenData(address(stakeWith6Decimals)).assetOracle, assetOracle);
    assertEq(umbrella.getStakeTokenData(address(stakeWith18Decimals)).assetOracle, assetOracle);
    // an unconfigured stake keeps no oracle
    assertEq(umbrella.getStakeTokenData(address(unusedStake)).assetOracle, address(0));
  }

  function test_updateSlashingConfigsEmitsEvents() public {
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.SlashingConfigurationChanged(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      50,
      assetOracle,
      stakeUnderlyingOracle
    );

    _updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        50,
        assetOracle,
        stakeUnderlyingOracle
      )
    );
  }

  /// @dev Unlike the V3 version, the `deficitOffset` is initialized per `spoke` on its listing
  function test_updateSlashingConfigsDoesNotInitDeficitOffset() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);
    assertEq(umbrella.getTotalDeficitOffset(address(hub), ASSET_6_DECIMALS), 0);
  }

  function test_updateSlashingConfigTwoTimes() public {
    address assetOracle = _newOracle(int256(ORACLE_PRICE), ORACLE_DECIMALS);
    address stakeUnderlyingOracle = _newOracle(int256(ORACLE_PRICE), ORACLE_DECIMALS);

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.SlashingConfigurationChanged(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      10,
      assetOracle,
      stakeUnderlyingOracle
    );
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        10,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    IUmbrellaConfigurationBase.SlashingConfig memory config = umbrella.getAssetSlashingConfig(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals)
    );

    assertEq(config.liquidationFee, 10);
    assertEq(config.umbrellaStakeUnderlyingOracle, stakeUnderlyingOracle);
    assertEq(umbrella.getAssetSlashingConfigs(address(hub), ASSET_6_DECIMALS).length, 1);

    address newAssetOracle = _newOracle(int256(ORACLE_PRICE) * 2, ORACLE_DECIMALS);
    address newStakeOracle = _newOracle(int256(ORACLE_PRICE) * 3, ORACLE_DECIMALS);

    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        10,
        newAssetOracle,
        newStakeOracle
      )
    );

    assertEq(umbrella.getStakeTokenData(address(stakeWith6Decimals)).assetOracle, newAssetOracle);
    assertEq(
      umbrella
        .getAssetSlashingConfig(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
        .umbrellaStakeUnderlyingOracle,
      newStakeOracle
    );
    vm.stopPrank();
  }

  function test_updateSlashingConfigsSeveralStakesForOnePair() public {
    address anotherStake = _createAnotherStakeToken();
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    IUmbrellaConfigurationV4.SlashingConfigUpdate[]
      memory configs = new IUmbrellaConfigurationV4.SlashingConfigUpdate[](2);

    configs[0] = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      0,
      assetOracle,
      stakeUnderlyingOracle
    )[0];
    configs[1] = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      anotherStake,
      0,
      assetOracle,
      stakeUnderlyingOracle
    )[0];

    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);

    assertEq(umbrella.getAssetSlashingConfigs(address(hub), ASSET_6_DECIMALS).length, 2);
    assertEq(umbrella.getStakeTokenData(address(stakeWith6Decimals)).assetOracle, assetOracle);
    assertEq(umbrella.getStakeTokenData(anotherStake).assetOracle, assetOracle);
  }

  function test_updateSlashingConfigsZeroAddresses() public {
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    vm.startPrank(defaultAdmin);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(0),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(0),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        address(0),
        stakeUnderlyingOracle
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        address(0)
      )
    );

    vm.stopPrank();
  }

  function test_updateSlashingConfigsLFGreaterThan100() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      1e4 + 1
    );

    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidLiquidationFee.selector)
    );
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  function test_updateSlashingConfigsInvalidStake() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      address(unusedStake),
      0
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  /// @dev The `hub` isn't checked for code, the asset lookup performed on it reverts on its own
  function test_updateSlashingConfigsCodelessHub() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      someone,
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      0
    );

    vm.expectRevert();
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  function test_updateSlashingConfigsInvalidAsset() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      address(hub),
      UNLISTED_ASSET,
      address(stakeWith6Decimals),
      0
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.InvalidAsset.selector));
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  /// @dev The decimals of the `umbrellaStake` aren't matched against the ones of the covered asset,
  /// the conversion between both is done through their oracles
  function test_updateSlashingConfigsDifferentDecimals() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith18Decimals), 0)
    );

    assertEq(
      umbrella
        .getAssetSlashingConfig(address(hub), ASSET_6_DECIMALS, address(stakeWith18Decimals))
        .umbrellaStake,
      address(stakeWith18Decimals)
    );
  }

  function test_updateSlashingConfigsInvalidOraclePrice(uint128 amount) public {
    address invalidOracle = _newOracle(-int256(uint256(amount)), ORACLE_DECIMALS);
    address validOracle = _newOracle(int256(ORACLE_PRICE), ORACLE_DECIMALS);

    vm.startPrank(defaultAdmin);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidOraclePrice.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        invalidOracle,
        validOracle
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidOraclePrice.selector));
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        validOracle,
        invalidOracle
      )
    );

    vm.stopPrank();
  }

  function test_updateSlashingConfigsOracleDecimalsMismatch() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals),
      0,
      _newOracle(1e8, 8),
      _newOracle(1e18, 18)
    );

    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationV4.OracleDecimalsMismatch.selector)
    );
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  function test_updateSlashingConfigsMatchingOracleDecimals() public {
    address assetOracle = _newOracle(1e8, 8);

    _updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        _newOracle(2e8, 8)
      )
    );

    assertEq(umbrella.getStakeTokenData(address(stakeWith6Decimals)).assetOracle, assetOracle);
  }

  function test_updateSlashingConfigsStakeAlreadySetForAnotherAsset() public {
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    vm.startPrank(defaultAdmin);
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    // the same `hub`, but another `assetId`
    hub.listAsset(UNLISTED_ASSET, address(underlying6Decimals), 6);

    vm.expectRevert(
      abi.encodeWithSelector(
        IUmbrellaConfigurationV4.UmbrellaStakeAlreadySetForAnotherAsset.selector
      )
    );
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        UNLISTED_ASSET,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    // the same `assetId`, but another `hub`
    vm.expectRevert(
      abi.encodeWithSelector(
        IUmbrellaConfigurationV4.UmbrellaStakeAlreadySetForAnotherAsset.selector
      )
    );
    umbrella.updateSlashingConfigs(
      _slashingConfigs(
        address(anotherHub),
        ASSET_6_DECIMALS,
        address(stakeWith6Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    vm.stopPrank();
  }

  /// @dev The removal of a `SlashingConfig` only deactivates it, so the stake stays bound to its pair
  function test_updateSlashingConfigsAfterRemovalKeepsStakeBoundToItsPair() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );

    assertTrue(umbrella.getStakeTokenData(address(stakeWith6Decimals)).deactivated);

    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs = _slashingConfigs(
      address(hub),
      ASSET_18_DECIMALS,
      address(stakeWith6Decimals),
      0
    );

    vm.expectRevert(
      abi.encodeWithSelector(
        IUmbrellaConfigurationV4.UmbrellaStakeAlreadySetForAnotherAsset.selector
      )
    );
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);

    // re-installing the configuration of the same pair activates the stake back
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    assertFalse(umbrella.getStakeTokenData(address(stakeWith6Decimals)).deactivated);
  }

  function test_removeSlashingConfigs() public {
    _setUpDefaultCoverage();
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    // the last configuration of a pair can only be removed once its `spoke`s are unlisted
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.SlashingConfigurationRemoved(
      address(hub),
      ASSET_6_DECIMALS,
      address(stakeWith6Decimals)
    );
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );
    vm.stopPrank();

    assertEq(umbrella.getAssetSlashingConfigs(address(hub), ASSET_6_DECIMALS).length, 0);

    // the unlisted `spoke` keeps its tracked deficit, so that a re-listing takes it into account
    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);

    IUmbrellaConfigurationV4.StakeTokenData memory stakeData = umbrella.getStakeTokenData(
      address(stakeWith6Decimals)
    );

    // the data of the stake token remains, so that `latestAnswer` inside it keeps working
    assertTrue(stakeData.deactivated);
    assertNotEq(stakeData.underlyingOracle, address(0));
    assertEq(stakeData.hub, address(hub));
    assertEq(stakeData.assetId, ASSET_6_DECIMALS);

    stakeWith6Decimals.latestAnswer();
  }

  function test_removeSlashingConfigsSpokesStillCovered() public {
    _setUpDefaultCoverage();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.SpokesStillCovered.selector));
    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );
  }

  /// @dev A `SlashingConfig` can be replaced while the `spoke`s stay covered, as long as the new one is
  /// installed before the old one is removed, so that the pair is never left unconfigured
  function test_removeSlashingConfigsKeepsCoverageWhileAnotherConfigRemains() public {
    _setUpDefaultCoverage();

    address anotherStake = _createAnotherStakeToken();
    _updateSlashingConfigs(_slashingConfigs(address(hub), ASSET_6_DECIMALS, anotherStake, 0));

    vm.prank(defaultAdmin);
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );

    IUmbrellaConfigurationV4.SlashingConfig[] memory configs = umbrella.getAssetSlashingConfigs(
      address(hub),
      ASSET_6_DECIMALS
    );

    assertEq(configs.length, 1);
    assertEq(configs[0].umbrellaStake, anotherStake);
    assertTrue(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
  }

  function test_removeSlashingConfigsUnexistingConfig() public {
    vm.prank(defaultAdmin);
    // shouldn't revert
    umbrella.removeSlashingConfigs(
      _removalPairs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals))
    );

    assertEq(umbrella.getAssetSlashingConfigs(address(hub), ASSET_6_DECIMALS).length, 0);
  }

  function test_getStakeTokenData() public {
    IUmbrellaConfigurationV4.StakeTokenData memory stakeData = umbrella.getStakeTokenData(
      address(stakeWith6Decimals)
    );

    assertEq(stakeData.underlyingOracle, address(0));
    assertEq(stakeData.assetOracle, address(0));
    assertEq(stakeData.hub, address(0));
    assertEq(stakeData.assetId, 0);
    assertFalse(stakeData.deactivated);

    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    _updateSlashingConfigs(
      _slashingConfigs(
        address(hub),
        ASSET_18_DECIMALS,
        address(stakeWith18Decimals),
        0,
        assetOracle,
        stakeUnderlyingOracle
      )
    );

    stakeData = umbrella.getStakeTokenData(address(stakeWith18Decimals));

    assertEq(stakeData.underlyingOracle, stakeUnderlyingOracle);
    assertEq(stakeData.assetOracle, assetOracle);
    assertEq(stakeData.hub, address(hub));
    assertEq(stakeData.assetId, ASSET_18_DECIMALS);
    assertFalse(stakeData.deactivated);
  }

  function test_getAssetSlashingConfigNotExist() public {
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.ConfigurationDoesNotExist.selector)
    );
    umbrella.getAssetSlashingConfig(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals));
  }

  function test_latestUnderlyingAnswer() public {
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.ConfigurationHasNotBeenSet.selector)
    );
    umbrella.latestUnderlyingAnswer(address(stakeWith6Decimals));

    vm.expectRevert();
    stakeWith6Decimals.latestAnswer();

    _setUpDefaultCoverage();

    assertEq(umbrella.latestUnderlyingAnswer(address(stakeWith6Decimals)), int256(ORACLE_PRICE));
  }

  function test_addCoveredSpokes() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    hub.setSpokeListed(ASSET_6_DECIMALS, spokeA, true);

    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
    assertEq(umbrella.getCoveredSpokes(address(hub), ASSET_6_DECIMALS).length, 0);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.DeficitOffsetChanged(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA,
      1_000 * 1e6
    );
    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.SpokeCoverageAdded(address(hub), ASSET_6_DECIMALS, spokeA);

    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));

    assertTrue(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));

    address[] memory coveredSpokes = umbrella.getCoveredSpokes(address(hub), ASSET_6_DECIMALS);
    assertEq(coveredSpokes.length, 1);
    assertEq(coveredSpokes[0], spokeA);

    // the deficit reported before the listing cannot be slashed
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    (bool isSlashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA
    );
    assertFalse(isSlashable);
    assertEq(newDeficit, 0);
  }

  /// @dev The `Hub` rounds the deficit up whenever it eliminates it, so the offset has to be rounded up too
  function test_addCoveredSpokesRoundsDeficitUp() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    hub.addSpokeDeficitRay(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6 * RAY + 1);
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6 + 1);
  }

  function test_addCoveredSpokesTwice() public {
    _setUpDefaultCoverage();

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    // a repeated listing neither reverts nor re-initializes the `deficitOffset`
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));

    assertEq(umbrella.getCoveredSpokes(address(hub), ASSET_6_DECIMALS).length, 1);
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);
  }

  /// @dev The `hub` isn't checked for code, the `spoke` lookup performed on it reverts on its own
  function test_addCoveredSpokesCodelessHub() public {
    IUmbrellaConfigurationV4.SpokeCoverage[] memory coverages = _coverages(
      someone,
      ASSET_6_DECIMALS,
      spokeA
    );

    vm.expectRevert();
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(coverages);
  }

  function test_addCoveredSpokesAssetCoverageNotSetup() public {
    hub.setSpokeListed(ASSET_6_DECIMALS, spokeA, true);

    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationV4.AssetCoverageNotSetup.selector)
    );
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
  }

  function test_addCoveredSpokesInvalidSpoke() public {
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationV4.InvalidSpoke.selector));
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, unlistedSpoke));
  }

  function test_addCoveredSpokesUmbrellaNotListedOnHub() public {
    hub.setSpokeListed(ASSET_6_DECIMALS, address(umbrella), false);
    hub.setSpokeListed(ASSET_6_DECIMALS, spokeA, true);

    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationV4.UmbrellaNotListedOnHub.selector)
    );
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
  }

  function test_addCoveredSpokesReListedTakesPendingDeficitIntoAccount() public {
    _setUpDefaultCoverage();
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 400 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    vm.stopPrank();

    // the funds already slashed for this `spoke` stay slashable
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 600 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA), 400 * 1e6);
  }

  function test_addCoveredSpokesZeroOffsetWhenPendingExceedsDeficit() public {
    _setUpDefaultCoverage();
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    vm.stopPrank();

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 0);
  }

  function test_removeCoveredSpokes() public {
    _setUpDefaultCoverage();
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    vm.expectEmit(address(umbrella));
    emit IUmbrellaConfigurationV4.SpokeCoverageRemoved(address(hub), ASSET_6_DECIMALS, spokeA);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    vm.stopPrank();

    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
    assertEq(umbrella.getCoveredSpokes(address(hub), ASSET_6_DECIMALS).length, 0);

    // the tracked deficit is kept for a potential re-listing, but stops contributing to the totals
    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getTotalDeficitOffset(address(hub), ASSET_6_DECIMALS), 0);
    assertEq(umbrella.getTotalPendingDeficit(address(hub), ASSET_6_DECIMALS), 0);
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 0);

    (bool isSlashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA
    );
    assertFalse(isSlashable);
    assertEq(newDeficit, 0);
  }

  function test_removeCoveredSpokesNotListed() public {
    vm.prank(defaultAdmin);
    // shouldn't revert
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));

    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
  }

  function test_removeCoveredSpokesByGrantedRole() public {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );
    hub.setSpokeListed(ASSET_6_DECIMALS, spokeA, true);

    vm.prank(defaultAdmin);
    umbrella.grantRole(SPOKE_COVERAGE_MANAGER_ROLE, someone);

    vm.startPrank(someone);
    umbrella.addCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    assertTrue(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));

    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));
    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_6_DECIMALS, spokeA));
    vm.stopPrank();
  }

  function test_isSpokeSlashable() public {
    // not listed in the coverage
    (bool isSlashable, uint256 newDeficit) = umbrella.isSpokeSlashable(
      address(hub),
      ASSET_6_DECIMALS,
      spokeA
    );
    assertFalse(isSlashable);
    assertEq(newDeficit, 0);

    _setUpDefaultCoverage();

    // listed and configured, but without any new deficit
    (isSlashable, newDeficit) = umbrella.isSpokeSlashable(address(hub), ASSET_6_DECIMALS, spokeA);
    assertFalse(isSlashable);
    assertEq(newDeficit, 0);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    (isSlashable, newDeficit) = umbrella.isSpokeSlashable(address(hub), ASSET_6_DECIMALS, spokeA);
    assertTrue(isSlashable);
    assertEq(newDeficit, 1_000 * 1e6);

    // the deficit fully covered by the offset isn't slashable
    vm.prank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    (isSlashable, newDeficit) = umbrella.isSpokeSlashable(address(hub), ASSET_6_DECIMALS, spokeA);
    assertFalse(isSlashable);
    assertEq(newDeficit, 0);

    // a second `SlashingConfig` makes the pair unslashable in the current version
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, _createAnotherStakeToken(), 0)
    );

    (isSlashable, newDeficit) = umbrella.isSpokeSlashable(address(hub), ASSET_6_DECIMALS, spokeA);
    assertFalse(isSlashable);
    assertEq(newDeficit, 1_000 * 1e6);
  }

  function test_getTotalsAcrossSpokes() public {
    // each `spoke` is listed while it already reports a deficit, which becomes its offset
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 600 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 100 * 1e6);

    _setUpDefaultCoverage();
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeB);

    // the deficit reported afterwards is the one Umbrella is on the hook for
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 400 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 300 * 1e6);
    // a `spoke` of the same pair which isn't listed contributes nothing
    hub.addSpokeDeficit(ASSET_6_DECIMALS, unlistedSpoke, 900 * 1e6);

    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeA, 200 * 1e6);
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeB, 50 * 1e6);

    assertEq(umbrella.getTotalDeficitOffset(address(hub), ASSET_6_DECIMALS), 700 * 1e6);
    assertEq(umbrella.getTotalPendingDeficit(address(hub), ASSET_6_DECIMALS), 250 * 1e6);
    // (1000 - 600 - 200) + (400 - 100 - 50)
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 450 * 1e6);
  }

  /// @dev A deactivated `spoke` remains known to its pair, but stops contributing to any of its totals
  function test_getTotalsSkipDeactivatedSpokes() public {
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 100 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 200 * 1e6);

    _setUpDefaultCoverage();
    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeB);

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 400 * 1e6);
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeB, 300 * 1e6);
    umbrella.setPendingDeficit(address(hub), ASSET_6_DECIMALS, spokeB, 50 * 1e6);

    vm.prank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(address(hub), ASSET_6_DECIMALS, spokeA));

    address[] memory coveredSpokes = umbrella.getCoveredSpokes(address(hub), ASSET_6_DECIMALS);
    assertEq(coveredSpokes.length, 1);
    assertEq(coveredSpokes[0], spokeB);

    assertEq(umbrella.getTotalDeficitOffset(address(hub), ASSET_6_DECIMALS), 200 * 1e6);
    assertEq(umbrella.getTotalPendingDeficit(address(hub), ASSET_6_DECIMALS), 50 * 1e6);
    // 500 - 200 - 50
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 250 * 1e6);
  }

  function test_getTotalSlashableDeficitRequiresOneSlashingConfig() public {
    // without any `SlashingConfig` a pair has no covered `spoke`s, so nothing can be slashed
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 0);

    _setUpDefaultCoverage();
    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);

    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 1_000 * 1e6);

    // neither can it with a basket of stake tokens
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, _createAnotherStakeToken(), 0)
    );

    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 0);
  }

  function test_coverageIsTrackedPerHubAndAsset() public {
    _setUpDefaultCoverage();

    // a `UmbrellaStakeToken` cannot be shared by two pairs, so the second `hub` gets its own one
    _updateSlashingConfigs(
      _slashingConfigs(address(anotherHub), ASSET_6_DECIMALS, _createAnotherStakeToken(), 0)
    );

    anotherHub.setSpokeListed(ASSET_6_DECIMALS, spokeA, true);
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(address(anotherHub), ASSET_6_DECIMALS, spokeA));

    hub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    anotherHub.addSpokeDeficit(ASSET_6_DECIMALS, spokeA, 500 * 1e6);

    vm.startPrank(defaultAdmin);
    umbrella.setDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA, 1_000 * 1e6);
    vm.stopPrank();

    assertEq(umbrella.getDeficitOffset(address(hub), ASSET_6_DECIMALS, spokeA), 1_000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(anotherHub), ASSET_6_DECIMALS, spokeA), 0);

    assertTrue(umbrella.isSpokeCovered(address(anotherHub), ASSET_6_DECIMALS, spokeA));
    assertFalse(umbrella.isSpokeCovered(address(hub), ASSET_18_DECIMALS, spokeA));

    assertEq(umbrella.getTotalDeficitOffset(address(hub), ASSET_6_DECIMALS), 1_000 * 1e6);
    assertEq(umbrella.getTotalDeficitOffset(address(anotherHub), ASSET_6_DECIMALS), 0);

    // the offset of the first pair makes its deficit unslashable, the second pair is untouched by it
    assertEq(umbrella.getTotalSlashableDeficit(address(hub), ASSET_6_DECIMALS), 0);
    assertEq(umbrella.getTotalSlashableDeficit(address(anotherHub), ASSET_6_DECIMALS), 500 * 1e6);
  }

  function test_InvalidRoles() public {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[]
      memory configs = new IUmbrellaConfigurationV4.SlashingConfigUpdate[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.updateSlashingConfigs(configs);

    IUmbrellaConfigurationV4.SlashingConfigRemoval[]
      memory removals = new IUmbrellaConfigurationV4.SlashingConfigRemoval[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.removeSlashingConfigs(removals);

    IUmbrellaConfigurationV4.SpokeCoverage[]
      memory coverages = new IUmbrellaConfigurationV4.SpokeCoverage[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        SPOKE_COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.addCoveredSpokes(coverages);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        SPOKE_COVERAGE_MANAGER_ROLE
      )
    );
    umbrella.removeCoveredSpokes(coverages);
  }

  function _createAnotherStakeToken() internal returns (address) {
    return _createStakeToken(address(underlying6Decimals), 'v2');
  }
}
