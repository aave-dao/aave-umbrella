// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';

import {UmbrellaBaseTest} from './utils/UmbrellaBase.t.sol';

import {IUmbrellaStkManager} from '../../src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol';
import {IUmbrellaConfigurationBase} from '../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationBase.sol';

import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';
import {UmbrellaStakeToken} from '../../src/contracts/stakeToken/UmbrellaStakeToken.sol';

contract Umbrella_StkManager_Test is UmbrellaBaseTest {
  function test_createStakeTokens() public {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'V1'
    });

    vm.startPrank(defaultAdmin);

    address[] memory addresses = umbrella.createStakeTokens(stakeSetups);

    assertEq(StakeToken(addresses[0]).name(), 'Umbrella Stake M6 V1');
    assertEq(StakeToken(addresses[0]).symbol(), 'stkM6.V1');
    assertEq(StakeToken(addresses[0]).decimals(), underlying6Decimals.decimals());

    assertEq(StakeToken(addresses[0]).getCooldown(), defaultCooldown);
    assertEq(StakeToken(addresses[0]).getUnstakeWindow(), defaultUnstakeWindow);

    assertEq(StakeToken(addresses[0]).asset(), address(underlying6Decimals));
  }

  function test_frontrunTokenCreation() public {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'V1'
    });

    (string memory name, string memory symbol) = _getStakeNameAndSymbol(
      stakeSetups[0].underlying,
      stakeSetups[0].suffix
    );

    bytes memory creationData = _getCreationData(
      stakeSetups[0].underlying,
      name,
      symbol,
      stakeSetups[0].cooldown,
      stakeSetups[0].unstakeWindow
    );

    // deploy token by someone manually
    transparentProxyFactory.createDeterministic(
      address(umbrellaStakeTokenImpl),
      address(defaultAdmin),
      creationData,
      ''
    );

    address[] memory addresses = umbrella.predictStakeTokensAddresses(stakeSetups);
    // token already created by someone
    assertNotEq(addresses[0].code.length, 0);

    vm.startPrank(defaultAdmin);
    // should not revert
    addresses = umbrella.createStakeTokens(stakeSetups);
  }

  function test_createStakeTokenWithEmptyUnderlying() public {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(0),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'V1'
    });

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.predictStakeTokensAddresses(stakeSetups);

    vm.startPrank(defaultAdmin);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.ZeroAddress.selector));
    umbrella.createStakeTokens(stakeSetups);
  }

  function test_createStakeTokensWithoutSuffix() public {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: ''
    });

    vm.startPrank(defaultAdmin);

    address[] memory addresses = umbrella.createStakeTokens(stakeSetups);

    assertEq(StakeToken(addresses[0]).name(), 'Umbrella Stake M6');
    assertEq(StakeToken(addresses[0]).symbol(), 'stkM6');
    assertEq(StakeToken(addresses[0]).decimals(), underlying6Decimals.decimals());

    assertEq(StakeToken(addresses[0]).getCooldown(), defaultCooldown);
    assertEq(StakeToken(addresses[0]).getUnstakeWindow(), defaultUnstakeWindow);

    assertEq(StakeToken(addresses[0]).asset(), address(underlying6Decimals));
  }

  function test_setCooldownStk() public {
    assertEq(stakeWith6Decimals.getCooldown(), 2 weeks);

    IUmbrellaStkManager.CooldownConfig[] memory configs = new IUmbrellaStkManager.CooldownConfig[](
      1
    );

    configs[0] = IUmbrellaStkManager.CooldownConfig({
      umbrellaStake: address(stakeWith6Decimals),
      newCooldown: 1 weeks
    });

    vm.startPrank(defaultAdmin);
    umbrella.setCooldownStk(configs);

    assertEq(stakeWith6Decimals.getCooldown(), 1 weeks);

    configs[0] = IUmbrellaStkManager.CooldownConfig({
      umbrellaStake: address(stakeWith6Decimals),
      newCooldown: 3 weeks
    });

    umbrella.setCooldownStk(configs);

    assertEq(stakeWith6Decimals.getCooldown(), 3 weeks);
  }

  function test_setUnstakeWindowStk() public {
    assertEq(stakeWith6Decimals.getUnstakeWindow(), 2 days);

    IUmbrellaStkManager.UnstakeWindowConfig[]
      memory configs = new IUmbrellaStkManager.UnstakeWindowConfig[](1);

    configs[0] = IUmbrellaStkManager.UnstakeWindowConfig({
      umbrellaStake: address(stakeWith6Decimals),
      newUnstakeWindow: 1 days
    });

    vm.startPrank(defaultAdmin);
    umbrella.setUnstakeWindowStk(configs);
    assertEq(stakeWith6Decimals.getUnstakeWindow(), 1 days);

    configs[0] = IUmbrellaStkManager.UnstakeWindowConfig({
      umbrellaStake: address(stakeWith6Decimals),
      newUnstakeWindow: 3 days
    });

    umbrella.setUnstakeWindowStk(configs);
    assertEq(stakeWith6Decimals.getUnstakeWindow(), 3 days);
  }

  function test_pauseStk() public {
    assertEq(stakeWith6Decimals.paused(), false);

    vm.startPrank(defaultAdmin);
    umbrella.pauseStk(address(stakeWith6Decimals));

    assertEq(stakeWith6Decimals.paused(), true);

    umbrella.unpauseStk(address(stakeWith6Decimals));

    assertEq(stakeWith6Decimals.paused(), false);
  }

  function test_getStkTokens() public {
    address[] memory tokens = umbrella.getStkTokens();

    assertEq(tokens.length, 2);
    assertEq(tokens[0], address(stakeWith6Decimals));
    assertEq(tokens[1], address(stakeWith18Decimals));

    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'V1'
    });

    vm.startPrank(defaultAdmin);

    address[] memory newStk = umbrella.createStakeTokens(stakeSetups);
    tokens = umbrella.getStkTokens();

    assertEq(tokens.length, 3);
    assertEq(tokens[0], address(stakeWith6Decimals));
    assertEq(tokens[1], address(stakeWith18Decimals));
    assertEq(tokens[2], newStk[0]);
  }

  function test_isUmbrellaStkToken() public {
    assertEq(umbrella.isUmbrellaStkToken(address(stakeWith6Decimals)), true);
    assertEq(umbrella.isUmbrellaStkToken(address(stakeWith18Decimals)), true);

    assertEq(umbrella.isUmbrellaStkToken(address(unusedStake)), false);

    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);
    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'V1'
    });

    vm.startPrank(defaultAdmin);

    address[] memory addresses = umbrella.createStakeTokens(stakeSetups);

    assertEq(umbrella.isUmbrellaStkToken(addresses[0]), true);
  }

  function test_InvalidRoles() public {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory configs = new IUmbrellaStkManager.StakeTokenSetup[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.createStakeTokens(configs);

    IUmbrellaStkManager.CooldownConfig[]
      memory cooldownConfigs = new IUmbrellaStkManager.CooldownConfig[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.setCooldownStk(cooldownConfigs);

    IUmbrellaStkManager.UnstakeWindowConfig[]
      memory unstakeConfigs = new IUmbrellaStkManager.UnstakeWindowConfig[](0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        DEFAULT_ADMIN_ROLE
      )
    );
    umbrella.setUnstakeWindowStk(unstakeConfigs);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        RESCUE_GUARDIAN_ROLE
      )
    );
    umbrella.emergencyTokenTransferStk(address(0), address(0), address(0), 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        RESCUE_GUARDIAN_ROLE
      )
    );
    umbrella.emergencyEtherTransferStk(address(0), address(0), 0);

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        PAUSE_GUARDIAN_ROLE
      )
    );
    umbrella.pauseStk(address(stakeWith6Decimals));

    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        address(this),
        PAUSE_GUARDIAN_ROLE
      )
    );
    umbrella.unpauseStk(address(stakeWith6Decimals));
  }

  function test_InvalidStakeTokenOnStkFunctions() public {
    IUmbrellaStkManager.CooldownConfig[]
      memory cooldownSetups = new IUmbrellaStkManager.CooldownConfig[](1);

    cooldownSetups[0] = IUmbrellaStkManager.CooldownConfig({
      umbrellaStake: address(unusedStake),
      newCooldown: 3 weeks
    });

    IUmbrellaStkManager.UnstakeWindowConfig[]
      memory unstakeWindowSetups = new IUmbrellaStkManager.UnstakeWindowConfig[](1);

    unstakeWindowSetups[0] = IUmbrellaStkManager.UnstakeWindowConfig({
      umbrellaStake: address(unusedStake),
      newUnstakeWindow: 3 days
    });

    vm.startPrank(defaultAdmin);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.setCooldownStk(cooldownSetups);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.setUnstakeWindowStk(unstakeWindowSetups);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.emergencyTokenTransferStk(
      address(unusedStake),
      address(underlying6Decimals),
      address(this),
      0
    );

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.emergencyEtherTransferStk(address(unusedStake), address(this), 0);

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.pauseStk(address(unusedStake));

    vm.expectRevert(abi.encodeWithSelector(IUmbrellaConfigurationBase.InvalidStakeToken.selector));
    umbrella.unpauseStk(address(unusedStake));
  }

  function _getStakeNameAndSymbol(
    address underlying,
    string memory suffix
  ) internal view returns (string memory, string memory) {
    bool isSuffixNotEmpty = bytes(suffix).length > 0;

    // `Umbrella Stake + name + suffix` or `Umbrella Stake + name`
    string memory name = string(
      abi.encodePacked(
        'Umbrella Stake ',
        IERC20Metadata(underlying).name(),
        isSuffixNotEmpty ? string(abi.encodePacked(' ', suffix)) : ''
      )
    );

    // `stk+symbol+.+suffix` or `stk+symbol`
    string memory symbol = string(
      abi.encodePacked(
        'stk',
        IERC20Metadata(underlying).symbol(),
        isSuffixNotEmpty ? string(abi.encodePacked('.', suffix)) : ''
      )
    );

    return (name, symbol);
  }

  function _getCreationData(
    address underlying,
    string memory name,
    string memory symbol,
    uint256 cooldown,
    uint256 unstakeWindow
  ) internal view returns (bytes memory) {
    return
      abi.encodeWithSelector(
        UmbrellaStakeToken.initialize.selector,
        underlying,
        name,
        symbol,
        address(umbrella),
        cooldown,
        unstakeWindow
      );
  }
}
