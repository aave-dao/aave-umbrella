// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {IHubBase} from 'aave-v4/hub/interfaces/IHubBase.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title TestSpoke
 * @notice Bare `spoke` of a real `Hub`, used to bring the `Hub` into the states `UmbrellaSpoke` covers.
 * @dev A `Hub` only knows its spokes by address, so supplying liquidity, drawing it and reporting the
 * drawn amount as a deficit is all that is needed to produce a genuine `spoke` deficit.
 */
contract TestSpoke {
  using SafeERC20 for IERC20;

  IHub public immutable HUB;

  constructor(IHub hub) {
    HUB = hub;
  }

  function add(uint256 assetId, uint256 amount) external returns (uint256) {
    (address underlying, ) = HUB.getAssetUnderlyingAndDecimals(assetId);
    IERC20(underlying).safeTransfer(address(HUB), amount);

    return HUB.add(assetId, amount);
  }

  function draw(uint256 assetId, uint256 amount, address to) external returns (uint256) {
    return HUB.draw(assetId, amount, to);
  }

  function remove(uint256 assetId, uint256 amount, address to) external returns (uint256) {
    return HUB.remove(assetId, amount, to);
  }

  /// @notice Eliminates a deficit of any `spoke` using the added shares of this one
  function eliminateDeficit(
    uint256 assetId,
    uint256 amount,
    address spoke
  ) external returns (uint256, uint256) {
    return HUB.eliminateDeficit(assetId, amount, spoke);
  }

  /// @notice Writes off the drawn amount, which becomes a deficit of this `spoke`
  function reportDeficit(uint256 assetId, uint256 drawnAmount) external returns (uint256, uint256) {
    return
      HUB.reportDeficit(
        assetId,
        drawnAmount,
        IHubBase.PremiumDelta({sharesDelta: 0, offsetRayDelta: 0, restoredPremiumRay: 0})
      );
  }
}
