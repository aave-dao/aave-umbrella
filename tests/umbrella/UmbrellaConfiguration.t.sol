// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

import {UmbrellaBaseTest} from './utils/UmbrellaBase.t.sol';

import {IUmbrellaConfigurationBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationBase.sol';
import {IUmbrellaConfiguration} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol';
import {Umbrella, IPool} from '../../src/contracts/umbrella/Umbrella.sol';

import {MockOracle} from './utils/mocks/MockOracle.sol';

contract Umbrella_Configuration_Test is UmbrellaBaseTest {
  function test_getStakeTokenData() public {
    IUmbrellaConfiguration.StakeTokenData memory stakeData = umbrella.getStakeTokenData(
      address(stakeWith6Decimals)
    );

    assertEq(stakeData.underlyingOracle, address(0));
    assertEq(stakeData.reserve, address(0));

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

    stakeData = umbrella.getStakeTokenData(address(stakeWith6Decimals));

    assertEq(stakeData.underlyingOracle, oracle);
    assertEq(stakeData.reserve, address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory stakeRemoval = new IUmbrellaConfiguration.SlashingConfigRemoval[](1);

    stakeRemoval[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    umbrella.removeSlashingConfigs(stakeRemoval);

    stakeData = umbrella.getStakeTokenData(address(stakeWith6Decimals));

    assertEq(stakeData.underlyingOracle, oracle);
    assertEq(stakeData.reserve, address(0));
  }

  function test_updateSlashingConfigsOkSetup() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });
    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying18Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    IUmbrellaConfigurationBase.SlashingConfig memory config6Decimals = umbrella
      .getReserveSlashingConfig(address(underlying6Decimals), address(stakeWith6Decimals));

    IUmbrellaConfigurationBase.SlashingConfig memory config18Decimals = umbrella
      .getReserveSlashingConfig(address(underlying18Decimals), address(stakeWith18Decimals));

    assertEq(config6Decimals.umbrellaStake, address(stakeWith6Decimals));
    assertEq(config6Decimals.umbrellaStakeUnderlyingOracle, oracle);
    assertEq(config6Decimals.liquidationFee, 0);

    assertEq(config18Decimals.umbrellaStake, address(stakeWith18Decimals));
    assertEq(config18Decimals.umbrellaStakeUnderlyingOracle, oracle);
    assertEq(config18Decimals.liquidationFee, 0);

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs6Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying6Decimals));

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs18Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying18Decimals));

    assertEq(configs6Decimals[0].umbrellaStake, config6Decimals.umbrellaStake);
    assertEq(
      configs6Decimals[0].umbrellaStakeUnderlyingOracle,
      config6Decimals.umbrellaStakeUnderlyingOracle
    );
    assertEq(configs6Decimals[0].liquidationFee, config6Decimals.liquidationFee);

    assertEq(configs18Decimals[0].umbrellaStake, config18Decimals.umbrellaStake);
    assertEq(
      configs18Decimals[0].umbrellaStakeUnderlyingOracle,
      config18Decimals.umbrellaStakeUnderlyingOracle
    );
    assertEq(configs18Decimals[0].liquidationFee, config18Decimals.liquidationFee);
  }

  function test_updateSlashingConfigsInitDeficit() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    pool.addReserveDeficit(address(underlying6Decimals), 1000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);
  }

  function test_updateSlashingConfigsInvalidStake() public {
    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(unusedStake),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: address(0xDEAD)
    });

    vm.startPrank(defaultAdmin);
    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function test_updateSlashingConfigsLBGreaterThan100() public {
    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 1e4 + 1,
      umbrellaStakeUnderlyingOracle: address(0xDEAD)
    });

    vm.startPrank(defaultAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidLiquidationFee.selector)
    );
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function test_updateSlashingConfigsDifferentDecimals() public {
    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: address(0xDEAD)
    });

    vm.startPrank(defaultAdmin);
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidNumberOfDecimals.selector)
    );
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function test_updateSlashingConfigsZeroAddresses() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    vm.startPrank(defaultAdmin);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(0),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(stakeSetups);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(0),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(stakeSetups);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: address(0)
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function test_updateSlashingConfigsInvalidOracleAndReserve(uint128 amount) public {
    address oracle = address(new MockOracle(-int256(uint256(amount))));

    vm.startPrank(defaultAdmin);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidOraclePrice.selector));
    umbrella.updateSlashingConfigs(stakeSetups);

    pool.switchReserve();

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfiguration.InvalidReserve.selector));
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function test_removeSlashingConfigs() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    pool.addReserveDeficit(address(underlying6Decimals), 1000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });
    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying18Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory removalPairs = new IUmbrellaConfiguration.SlashingConfigRemoval[](2);

    removalPairs[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    removalPairs[1] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying18Decimals),
      umbrellaStake: address(stakeWith18Decimals)
    });

    umbrella.removeSlashingConfigs(removalPairs);

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs6Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying6Decimals));

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs18Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying18Decimals));

    assertEq(configs6Decimals.length, 0);
    assertEq(configs18Decimals.length, 0);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1000 * 1e6);
    assertEq(umbrella.getDeficitOffset(address(underlying18Decimals)), 0);

    // shouldn't revert
    stakeWith18Decimals.latestAnswer();
  }

  function test_shouldRevertLatestAnswerBeforeConfig() public {
    vm.expectRevert();
    stakeWith18Decimals.latestAnswer();
  }

  function test_removeSlashingConfigsUnexestingConfig() public {
    IUmbrellaConfigurationBase.SlashingConfig[] memory configs6Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying6Decimals));

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs18Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying18Decimals));

    assertEq(configs6Decimals.length, 0);
    assertEq(configs18Decimals.length, 0);

    vm.startPrank(defaultAdmin);

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory removalPairs = new IUmbrellaConfiguration.SlashingConfigRemoval[](2);

    removalPairs[0] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    removalPairs[1] = IUmbrellaConfiguration.SlashingConfigRemoval({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals)
    });

    // shouldn't revert
    umbrella.removeSlashingConfigs(removalPairs);

    configs6Decimals = umbrella.getReserveSlashingConfigs(address(underlying6Decimals));

    configs18Decimals = umbrella.getReserveSlashingConfigs(address(underlying18Decimals));

    assertEq(configs6Decimals.length, 0);
    assertEq(configs18Decimals.length, 0);
  }

  function test_latestUnderlyingAnswer() public {
    MockOracle oracle = new MockOracle(1 * 1e8);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: address(oracle)
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);

    assertEq(umbrella.latestUnderlyingAnswer(address(stakeWith6Decimals)), 1 * 1e8);

    vm.expectRevert();
    umbrella.latestUnderlyingAnswer(address(stakeWith18Decimals));
  }

  function test_isReserveSlashable() public {
    address oracle = _setUpOracles(address(underlying6Decimals));

    (bool isSlashable, uint256 newDeficit) = umbrella.isReserveSlashable(
      address(underlying6Decimals)
    );

    assertEq(isSlashable, false);
    assertEq(newDeficit, 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1000 * 1e6);

    (isSlashable, newDeficit) = umbrella.isReserveSlashable(address(underlying6Decimals));

    assertEq(isSlashable, false);
    assertEq(newDeficit, 1000 * 1e6);

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](1);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 0);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    umbrella.updateSlashingConfigs(stakeSetups);

    (isSlashable, newDeficit) = umbrella.isReserveSlashable(address(underlying6Decimals));

    assertEq(isSlashable, false);
    assertEq(newDeficit, 0);

    assertEq(umbrella.getDeficitOffset(address(underlying6Decimals)), 1000 * 1e6);
    assertEq(umbrella.getPendingDeficit(address(underlying6Decimals)), 0);

    pool.addReserveDeficit(address(underlying6Decimals), 1000 * 1e6);

    (isSlashable, newDeficit) = umbrella.isReserveSlashable(address(underlying6Decimals));

    assertEq(isSlashable, true);
    assertEq(newDeficit, 1000 * 1e6);
  }

  function test_setup() public view {
    assertEq(address(umbrella.TRANSPARENT_PROXY_FACTORY()), address(transparentProxyFactory));
    assertEq(address(umbrella.POOL_ADDRESSES_PROVIDER()), address(poolAddressesProvider));
    assertEq(address(umbrella.POOL()), address(pool));

    assertEq(umbrella.UMBRELLA_STAKE_TOKEN_IMPL(), address(umbrellaStakeTokenImpl));
    assertEq(umbrella.SLASHED_FUNDS_RECIPIENT(), collector);
    assertEq(umbrella.SUPER_ADMIN(), defaultAdmin);
  }

  function test_invalidInit() public {
    Umbrella umbrellaImpl = new Umbrella();

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella = Umbrella(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          Umbrella.initialize.selector,
          IPool(address(pool)),
          defaultAdmin,
          collector,
          umbrellaStakeTokenImpl,
          address(0)
        )
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella = Umbrella(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          Umbrella.initialize.selector,
          IPool(address(pool)),
          defaultAdmin,
          collector,
          address(0),
          address(transparentProxyFactory)
        )
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella = Umbrella(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          Umbrella.initialize.selector,
          IPool(address(pool)),
          defaultAdmin,
          address(0),
          umbrellaStakeTokenImpl,
          address(transparentProxyFactory)
        )
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella = Umbrella(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          Umbrella.initialize.selector,
          IPool(address(pool)),
          address(0),
          collector,
          umbrellaStakeTokenImpl,
          address(transparentProxyFactory)
        )
      )
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella = Umbrella(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          Umbrella.initialize.selector,
          IPool(address(0)),
          defaultAdmin,
          collector,
          umbrellaStakeTokenImpl,
          address(transparentProxyFactory)
        )
      )
    );
  }

  function test_getSlashingConfigsOrPrice() public {
    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.ConfigurationDoesNotExist.selector)
    );
    umbrella.getReserveSlashingConfig(address(underlying6Decimals), address(stakeWith6Decimals));

    vm.expectRevert(
      abi.encodeWithSelector(IUmbrellaConfigurationBase.ConfigurationHasNotBeenSet.selector)
    );
    umbrella.latestUnderlyingAnswer(address(stakeWith18Decimals));
  }

  function test_InvalidRoles() public {
    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory configs = new IUmbrellaConfiguration.SlashingConfigUpdate[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.updateSlashingConfigs(configs);

    IUmbrellaConfiguration.SlashingConfigRemoval[]
      memory removalConfigs = new IUmbrellaConfiguration.SlashingConfigRemoval[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.removeSlashingConfigs(removalConfigs);
  }

  function test_updateSlashingConfigTwoTimes() public {
    address oracle = address(new MockOracle(1 * 1e8));

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

    IUmbrellaConfigurationBase.SlashingConfig memory config6Decimals = umbrella
      .getReserveSlashingConfig(address(underlying6Decimals), address(stakeWith6Decimals));

    assertEq(config6Decimals.umbrellaStake, address(stakeWith6Decimals));
    assertEq(config6Decimals.umbrellaStakeUnderlyingOracle, oracle);
    assertEq(config6Decimals.liquidationFee, 0);

    IUmbrellaConfigurationBase.SlashingConfig[] memory configs6Decimals = umbrella
      .getReserveSlashingConfigs(address(underlying6Decimals));

    assertEq(configs6Decimals[0].umbrellaStake, config6Decimals.umbrellaStake);
    assertEq(
      configs6Decimals[0].umbrellaStakeUnderlyingOracle,
      config6Decimals.umbrellaStakeUnderlyingOracle
    );
    assertEq(configs6Decimals[0].liquidationFee, config6Decimals.liquidationFee);

    address newOracle = address(new MockOracle(1.1 * 1e8));

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 10,
      umbrellaStakeUnderlyingOracle: newOracle
    });

    umbrella.updateSlashingConfigs(stakeSetups);

    config6Decimals = umbrella.getReserveSlashingConfig(
      address(underlying6Decimals),
      address(stakeWith6Decimals)
    );

    assertEq(config6Decimals.umbrellaStake, address(stakeWith6Decimals));
    assertEq(config6Decimals.umbrellaStakeUnderlyingOracle, newOracle);
    assertEq(config6Decimals.liquidationFee, 10);

    configs6Decimals = umbrella.getReserveSlashingConfigs(address(underlying6Decimals));

    assertEq(configs6Decimals[0].umbrellaStake, config6Decimals.umbrellaStake);
    assertEq(
      configs6Decimals[0].umbrellaStakeUnderlyingOracle,
      config6Decimals.umbrellaStakeUnderlyingOracle
    );
    assertEq(configs6Decimals[0].liquidationFee, config6Decimals.liquidationFee);
  }

  function test_updateSlashingConfigsMultipleSetupOfOneStakeToken() public {
    address oracle = address(new MockOracle(1 * 1e8));

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });
    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(anotherUnderlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: oracle
    });

    vm.startPrank(defaultAdmin);

    vm.expectRevert(
      abi.encodeWithSelector(
        IUmbrellaConfiguration.UmbrellaStakeAlreadySetForAnotherReserve.selector
      )
    );
    umbrella.updateSlashingConfigs(stakeSetups);
  }

  function _setUpOracles(address reserve) internal returns (address oracle) {
    aaveOracle.setAssetPrice(reserve, 1e8);

    return address(new MockOracle(1e8));
  }
}
