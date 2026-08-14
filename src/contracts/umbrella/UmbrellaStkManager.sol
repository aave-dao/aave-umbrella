// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {EnumerableSet} from 'openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol';

import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';

import {IUmbrellaStkManager} from './interfaces/IUmbrellaStkManager.sol';

import {UmbrellaBase} from './UmbrellaBase.sol';

import {UmbrellaStakeToken} from '../stakeToken/UmbrellaStakeToken.sol';

/**
 * @title UmbrellaStkManager
 * @notice An abstract contract for creating and managing `UmbrellaStakeToken`s, including changing `cooldown` and `unstakeWindow` parameters,
 * pausing or unpausing token and rescuing funds.
 * @dev Version agnostic, it is shared by every `Umbrella` version.
 * @author BGD labs
 */
abstract contract UmbrellaStkManager is UmbrellaBase, IUmbrellaStkManager {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @custom:storage-location erc7201:umbrella.storage.UmbrellaStkManager
  struct UmbrellaStkManagerStorage {
    /// @notice Enumerable set of all `UmbrellaStakeToken` created by this `Umbrella`
    EnumerableSet.AddressSet stakeTokens;
    /// @notice Address of the transparent proxy factory
    ITransparentProxyFactory transparentProxyFactory;
    /// @notice Address of the `UmbrellaStakeToken` implementation
    address umbrellaStakeTokenImpl;
    /// @notice Address of the `DEFAULT_ADMIN_ROLE` and `UmbrellaStakeToken` proxy admin.
    address superAdmin;
  }

  // keccak256(abi.encode(uint256(keccak256("umbrella.storage.UmbrellaStkManager")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant UmbrellaStkManagerStorageLocation =
    0xd011775bc1b3856f5856f18e492250d014048d48314b150d415c75e06d3c4200;

  function _getUmbrellaStkManagerStorage()
    private
    pure
    returns (UmbrellaStkManagerStorage storage $)
  {
    assembly {
      $.slot := UmbrellaStkManagerStorageLocation
    }
  }

  function __UmbrellaStkManager_init(
    address superAdmin,
    address umbrellaStakeTokenImpl,
    address transparentProxyFactory
  ) internal onlyInitializing {
    require(
      transparentProxyFactory != address(0) &&
        umbrellaStakeTokenImpl != address(0) &&
        superAdmin != address(0),
      ZeroAddress()
    );

    UmbrellaStkManagerStorage storage $ = _getUmbrellaStkManagerStorage();
    $.transparentProxyFactory = ITransparentProxyFactory(transparentProxyFactory);
    $.umbrellaStakeTokenImpl = umbrellaStakeTokenImpl;
    $.superAdmin = superAdmin;
  }

  /// @inheritdoc IUmbrellaStkManager
  function createStakeTokens(
    StakeTokenSetup[] calldata stakeSetups
  ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address[] memory) {
    address[] memory stakeTokens = new address[](stakeSetups.length);

    for (uint256 i; i < stakeSetups.length; ++i) {
      stakeTokens[i] = _createStakeToken(stakeSetups[i]);
    }

    return stakeTokens;
  }

  /// @inheritdoc IUmbrellaStkManager
  function setCooldownStk(
    CooldownConfig[] calldata cooldownConfigs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i; i < cooldownConfigs.length; ++i) {
      require(_isUmbrellaStkToken(cooldownConfigs[i].umbrellaStake), InvalidStakeToken());

      UmbrellaStakeToken(cooldownConfigs[i].umbrellaStake).setCooldown(
        cooldownConfigs[i].newCooldown
      );
    }
  }

  /// @inheritdoc IUmbrellaStkManager
  function setUnstakeWindowStk(
    UnstakeWindowConfig[] calldata unstakeWindowConfigs
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    for (uint256 i; i < unstakeWindowConfigs.length; ++i) {
      require(_isUmbrellaStkToken(unstakeWindowConfigs[i].umbrellaStake), InvalidStakeToken());

      UmbrellaStakeToken(unstakeWindowConfigs[i].umbrellaStake).setUnstakeWindow(
        unstakeWindowConfigs[i].newUnstakeWindow
      );
    }
  }

  /// @inheritdoc IUmbrellaStkManager
  function emergencyTokenTransferStk(
    address umbrellaStake,
    address erc20Token,
    address to,
    uint256 amount
  ) external onlyRole(RESCUE_GUARDIAN_ROLE) {
    require(_isUmbrellaStkToken(umbrellaStake), InvalidStakeToken());

    UmbrellaStakeToken(umbrellaStake).emergencyTokenTransfer(erc20Token, to, amount);
  }

  /// @inheritdoc IUmbrellaStkManager
  function emergencyEtherTransferStk(
    address umbrellaStake,
    address to,
    uint256 amount
  ) external onlyRole(RESCUE_GUARDIAN_ROLE) {
    require(_isUmbrellaStkToken(umbrellaStake), InvalidStakeToken());

    UmbrellaStakeToken(umbrellaStake).emergencyEtherTransfer(to, amount);
  }

  /// @inheritdoc IUmbrellaStkManager
  function pauseStk(address umbrellaStake) external onlyRole(PAUSE_GUARDIAN_ROLE) {
    require(_isUmbrellaStkToken(umbrellaStake), InvalidStakeToken());

    UmbrellaStakeToken(umbrellaStake).pause();
  }

  /// @inheritdoc IUmbrellaStkManager
  function unpauseStk(address umbrellaStake) external onlyRole(PAUSE_GUARDIAN_ROLE) {
    require(_isUmbrellaStkToken(umbrellaStake), InvalidStakeToken());

    UmbrellaStakeToken(umbrellaStake).unpause();
  }

  /// @inheritdoc IUmbrellaStkManager
  function predictStakeTokensAddresses(
    StakeTokenSetup[] calldata stakeSetups
  ) external view returns (address[] memory) {
    address[] memory stakeTokens = new address[](stakeSetups.length);

    for (uint256 i; i < stakeSetups.length; ++i) {
      stakeTokens[i] = _predictStakeTokenAddress(stakeSetups[i]);
    }

    return stakeTokens;
  }

  /// @inheritdoc IUmbrellaStkManager
  function getStkTokens() external view returns (address[] memory) {
    return _getUmbrellaStkManagerStorage().stakeTokens.values();
  }

  /// @inheritdoc IUmbrellaStkManager
  function isUmbrellaStkToken(address umbrellaStake) public view returns (bool) {
    return _isUmbrellaStkToken(umbrellaStake);
  }

  /// @inheritdoc IUmbrellaStkManager
  function TRANSPARENT_PROXY_FACTORY() public view returns (ITransparentProxyFactory) {
    return _getUmbrellaStkManagerStorage().transparentProxyFactory;
  }

  /// @inheritdoc IUmbrellaStkManager
  function UMBRELLA_STAKE_TOKEN_IMPL() public view returns (address) {
    return _getUmbrellaStkManagerStorage().umbrellaStakeTokenImpl;
  }

  /// @inheritdoc IUmbrellaStkManager
  function SUPER_ADMIN() public view returns (address) {
    return _getUmbrellaStkManagerStorage().superAdmin;
  }

  function _createStakeToken(StakeTokenSetup calldata stakeSetup) internal returns (address) {
    require(stakeSetup.underlying != address(0), ZeroAddress());

    (string memory name, string memory symbol) = _getStakeNameAndSymbol(
      stakeSetup.underlying,
      stakeSetup.suffix
    );

    bytes memory creationData = _getCreationData(
      stakeSetup.underlying,
      name,
      symbol,
      stakeSetup.cooldown,
      stakeSetup.unstakeWindow
    );

    address umbrellaStakeToken = TRANSPARENT_PROXY_FACTORY().predictCreateDeterministic(
      UMBRELLA_STAKE_TOKEN_IMPL(),
      SUPER_ADMIN(),
      creationData,
      ''
    );

    if (umbrellaStakeToken.code.length == 0) {
      // name and symbol inside creation data is considered as unique, so using different salts is excess
      // if for some reason we want to create different tokens with the same name and symbol, then we can use different `cooldown` and `unstakeWindow`
      TRANSPARENT_PROXY_FACTORY().createDeterministic(
        UMBRELLA_STAKE_TOKEN_IMPL(),
        SUPER_ADMIN(),
        creationData,
        ''
      );
    }

    _getUmbrellaStkManagerStorage().stakeTokens.add(umbrellaStakeToken);

    emit UmbrellaStakeTokenCreated(umbrellaStakeToken, stakeSetup.underlying, name, symbol);

    return umbrellaStakeToken;
  }

  function _predictStakeTokenAddress(
    StakeTokenSetup calldata stakeSetup
  ) internal view returns (address) {
    require(stakeSetup.underlying != address(0), ZeroAddress());

    (string memory name, string memory symbol) = _getStakeNameAndSymbol(
      stakeSetup.underlying,
      stakeSetup.suffix
    );

    bytes memory creationData = _getCreationData(
      stakeSetup.underlying,
      name,
      symbol,
      stakeSetup.cooldown,
      stakeSetup.unstakeWindow
    );

    return
      TRANSPARENT_PROXY_FACTORY().predictCreateDeterministic(
        UMBRELLA_STAKE_TOKEN_IMPL(),
        SUPER_ADMIN(),
        creationData,
        ''
      );
  }

  function _getStakeNameAndSymbol(
    address underlying,
    string calldata suffix
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
        address(this),
        cooldown,
        unstakeWindow
      );
  }

  function _isUmbrellaStkToken(address umbrellaStake) internal view override returns (bool) {
    return _getUmbrellaStkManagerStorage().stakeTokens.contains(umbrellaStake);
  }
}
