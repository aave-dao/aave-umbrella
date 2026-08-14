// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Initializable} from 'openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol';

import {RescuableBase, IRescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';
import {RescuableACL} from 'solidity-utils/contracts/utils/RescuableACL.sol';

import {IUmbrellaConfiguration} from './interfaces/IUmbrellaConfiguration.sol';

/**
 * @title UmbrellaBase
 * @notice This abstract contract provides the access control, roles and rescue mechanics shared by every
 * `Umbrella` version. It holds no storage of its own, so the version specific contracts inheriting it
 * remain free to lay out their own namespaced storage.
 * @author BGD labs
 */
abstract contract UmbrellaBase is
  RescuableACL,
  Initializable,
  AccessControlUpgradeable,
  IUmbrellaConfiguration
{
  bytes32 public constant COVERAGE_MANAGER_ROLE = keccak256('COVERAGE_MANAGER_ROLE');
  bytes32 public constant RESCUE_GUARDIAN_ROLE = keccak256('RESCUE_GUARDIAN_ROLE');
  bytes32 public constant PAUSE_GUARDIAN_ROLE = keccak256('PAUSE_GUARDIAN_ROLE');

  uint256 internal constant ONE_HUNDRED_PERCENT = 1e4;

  function __UmbrellaBase_init(address superAdmin) internal onlyInitializing {
    require(superAdmin != address(0), ZeroAddress());

    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, superAdmin);
    _grantRole(COVERAGE_MANAGER_ROLE, superAdmin);
    _grantRole(RESCUE_GUARDIAN_ROLE, superAdmin);
    _grantRole(PAUSE_GUARDIAN_ROLE, superAdmin);
  }

  function maxRescue(
    address
  ) public pure override(IRescuableBase, RescuableBase) returns (uint256) {
    return type(uint256).max;
  }

  function _checkRescueGuardian() internal view override {
    _checkRole(RESCUE_GUARDIAN_ROLE, _msgSender());
  }

  function _isUmbrellaStkToken(address stakeToken) internal view virtual returns (bool);
}
