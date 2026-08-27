// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import {AccessControl} from 'openzeppelin-contracts/contracts/access/AccessControl.sol';

import {RescuableBase, IRescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';
import {RescuableACL, IRescuable} from 'solidity-utils/contracts/utils/RescuableACL.sol';

import {IUmbrella} from '../umbrella/interfaces/IUmbrella.sol';

import {IDeficitOffsetClinicSteward} from './interfaces/IDeficitOffsetClinicSteward.sol';

/**
 * @title DeficitOffsetClinicSteward
 * @author BGD Labs
 * @notice This contract covers reserve deficits until the total covered amount exceeds the `deficitOffset` threshold.
 * It is designed to prevent the accumulation of deficits in the pool and to eliminate the need for creating individual proposals for each coverage event.
 *
 * All funds used for coverage are sourced from the Aave Collector.
 * For this contract to work properly, it must have the `COVERAGE_MANAGER_ROLE` role on `Umbrella` and also have the appropriate allowance in the required tokens.
 *
 * Access control:
 *  Deficit offset can be covered by `FINANCE_COMMITTEE_ROLE`
 *  Resque funds can be executed by `DEFAULT_ADMIN_ROLE`
 */
contract DeficitOffsetClinicSteward is AccessControl, RescuableACL, IDeficitOffsetClinicSteward {
  using SafeERC20 for IERC20;

  bytes32 public constant FINANCE_COMMITTEE_ROLE = keccak256('FINANCE_COMITTEE_ROLE');

  IUmbrella public immutable UMBRELLA;
  address public immutable TREASURY;
  IPool public immutable POOL;

  constructor(address umbrella, address treasury, address governance, address financeCommittee) {
    require(
      umbrella != address(0) &&
        treasury != address(0) &&
        governance != address(0) &&
        financeCommittee != address(0),
      ZeroAddress()
    );

    UMBRELLA = IUmbrella(umbrella);
    TREASURY = treasury;

    POOL = IPool(UMBRELLA.POOL());

    _grantRole(DEFAULT_ADMIN_ROLE, governance);
    _grantRole(FINANCE_COMMITTEE_ROLE, financeCommittee);
  }

  function coverDeficitOffset(
    address reserve
  ) external onlyRole(FINANCE_COMMITTEE_ROLE) returns (uint256) {
    uint256 deficitOffsetToCover = getDeficitOffsetToCover(reserve);

    require(deficitOffsetToCover != 0, DeficitOffsetCannotBeCovered());

    IERC20 tokenForCoverage = IERC20(UMBRELLA.tokenForDeficitCoverage(reserve));
    tokenForCoverage.safeTransferFrom(TREASURY, address(this), deficitOffsetToCover);

    uint256 actualBalanceReceived = tokenForCoverage.balanceOf(address(this));
    deficitOffsetToCover = actualBalanceReceived < deficitOffsetToCover
      ? actualBalanceReceived
      : deficitOffsetToCover;

    tokenForCoverage.forceApprove(address(UMBRELLA), deficitOffsetToCover);

    deficitOffsetToCover = UMBRELLA.coverDeficitOffset(reserve, deficitOffsetToCover);

    return deficitOffsetToCover;
  }

  function getRemainingAllowance(address reserve) external view returns (uint256) {
    IERC20 tokenForCoverage = IERC20(UMBRELLA.tokenForDeficitCoverage(reserve));

    return tokenForCoverage.allowance(TREASURY, address(this));
  }

  function getDeficitOffsetToCover(address reserve) public view returns (uint256) {
    uint256 pendingDeficit = getPendingDeficit(reserve);
    uint256 deficitOffset = getDeficitOffset(reserve);
    uint256 poolDeficit = getReserveDeficit(reserve);

    if (pendingDeficit + deficitOffset > poolDeficit) {
      // `deficitOffset` is manually increased and we can't cover it all,
      // because only existing reserve deficit can be covered
      return poolDeficit - pendingDeficit;
    } else {
      // we can cover all `deficitOffset`
      return deficitOffset;
    }
  }

  function getPendingDeficit(address reserve) public view returns (uint256) {
    return UMBRELLA.getPendingDeficit(reserve);
  }

  function getDeficitOffset(address reserve) public view returns (uint256) {
    return UMBRELLA.getDeficitOffset(reserve);
  }

  function getReserveDeficit(address reserve) public view returns (uint256) {
    return POOL.getReserveDeficit(reserve);
  }

  function maxRescue(
    address token
  ) public view override(IRescuableBase, RescuableBase) returns (uint256) {
    return IERC20(token).balanceOf(address(this));
  }

  function _checkRescueGuardian() internal view override {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), IRescuable.OnlyRescueGuardian());
  }
}
