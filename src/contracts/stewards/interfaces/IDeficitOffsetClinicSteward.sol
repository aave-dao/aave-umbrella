// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';

import {IUmbrella} from '../../umbrella/interfaces/IUmbrella.sol';

interface IDeficitOffsetClinicSteward {
  /**
   * @dev Attempted to set zero address.
   */
  error ZeroAddress();

  /**
   * @dev Attempted to cover zero deficit.
   */
  error DeficitOffsetCannotBeCovered();

  /**
   * @notice Pulls funds to resolve `deficitOffset` on the maximum possible amount.
   * @dev If current allowance or treasury balance is less than the `deficitOffsetToCover` the function will revert.
   * @param reserve Reserve address
   * @return The amount of `deficitOffset` eliminated
   */
  function coverDeficitOffset(address reserve) external returns (uint256);

  /**
   * @notice Returns the amount of allowance, that can be spent for `deficitOffset` coverage.
   * @param reserve Reserve address
   * @return The amount of allowance
   */
  function getRemainingAllowance(address reserve) external view returns (uint256);

  /**
   * @notice Returns the amount of `deficitOffset` that can be covered.
   * @param reserve Reserve address
   * @return The amount of `deficitOffset` that can be covered
   */
  function getDeficitOffsetToCover(address reserve) external view returns (uint256);

  /**
   * @notice Returns the amount of already slashed funds that have not yet been used for the deficit elimination.
   * @param reserve Address of the `reserve`
   * @return The amount of funds pending for deficit elimination
   */
  function getPendingDeficit(address reserve) external view returns (uint256);

  /**
   * @notice Returns the amount of deficit that can't be slashed using `UmbrellaStakeToken` funds.
   * @param reserve Address of the `reserve`
   * @return The amount of the `deficitOffset`
   */
  function getDeficitOffset(address reserve) external view returns (uint256);

  /**
   * @notice Returns the amount of actual reserve deficit at the moment.
   * @param reserve Address of the `reserve`
   * @return The amount of the `deficitOffset`
   */
  function getReserveDeficit(address reserve) external view returns (uint256);

  /**
   * @notice Returns the `Umbrella` contract for which this steward instance is configured.
   * @return Umbrella address
   */
  function UMBRELLA() external view returns (IUmbrella);

  /**
   * @notice Returns the Aave Collector from where the funds are pulled.
   * @return Treasury address
   */
  function TREASURY() external view returns (address);

  /**
   * @notice Returns the Aave Pool for which `Umbrella` instance is configured.
   * @return Pool address
   */
  function POOL() external view returns (IPool);
}
