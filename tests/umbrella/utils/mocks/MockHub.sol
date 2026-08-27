// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SharesMath} from 'aave-v4/hub/libraries/SharesMath.sol';
import {WadRayMath} from 'aave-v4/libraries/math/WadRayMath.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from 'openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title MockHub
 * @notice Replica of the part of the Aave V4 `Hub` that `UmbrellaSpoke` interacts with.
 * @dev Share and deficit conversions are delegated to the `Hub` libraries, so that the rounding
 * of `add`, `remove` and `eliminateDeficit` matches the real one.
 */
contract MockHub {
  using SafeERC20 for IERC20;
  using SharesMath for uint256;
  using WadRayMath for uint256;

  struct Asset {
    address underlying;
    uint8 decimals;
    uint256 liquidity;
    /// @notice Extra assets backing the added shares, mimics the growth of their value over time
    uint256 interest;
    uint256 addedShares;
    uint256 deficitRay;
  }

  error SpokeNotActive();
  error NotAuthorized();
  error InvalidAmount();
  error InvalidShares();
  error InsufficientTransferred();
  error InsufficientLiquidity();

  mapping(uint256 assetId => Asset) internal _assetsData;
  mapping(uint256 assetId => mapping(address spoke => uint256 shares)) internal _spokeAddedShares;
  mapping(uint256 assetId => mapping(address spoke => uint256 deficitRay))
    internal _spokeDeficitRay;
  mapping(uint256 assetId => mapping(address spoke => bool listed)) internal _listedSpokes;

  /// @notice Spokes for which every action is rejected, mimics a not active or halted spoke
  mapping(address spoke => bool) public spokeDeactivated;
  /// @notice Spokes without the deficit eliminator role, `eliminateDeficit` is `restricted` on the `Hub`
  mapping(address spoke => bool) public deficitEliminatorRevoked;

  function listAsset(uint256 assetId, address underlying, uint8 assetDecimals) external {
    _assetsData[assetId].underlying = underlying;
    _assetsData[assetId].decimals = assetDecimals;
  }

  function setSpokeListed(uint256 assetId, address spoke, bool listed) external {
    _listedSpokes[assetId][spoke] = listed;
  }

  function setSpokeDeactivated(address spoke, bool deactivated) external {
    spokeDeactivated[spoke] = deactivated;
  }

  function setDeficitEliminatorRevoked(address spoke, bool revoked) external {
    deficitEliminatorRevoked[spoke] = revoked;
  }

  /// @dev A deficit arises from liquidity which was drawn and never restored, so it is carved out of the
  /// liquidity of the asset. The total value of the added shares is left untouched by that move.
  function addSpokeDeficit(uint256 assetId, address spoke, uint256 amount) external {
    _addSpokeDeficitRay(assetId, spoke, amount.toRay(), amount);
  }

  function addSpokeDeficitRay(uint256 assetId, address spoke, uint256 amountRay) external {
    _addSpokeDeficitRay(assetId, spoke, amountRay, amountRay.fromRayUp());
  }

  /// @dev Credits added shares for liquidity already sitting inside this `Hub`
  function seedSpokeShares(uint256 assetId, address spoke, uint256 amount) external {
    Asset storage asset = _assetsData[assetId];
    uint256 shares = amount.toSharesDown(_totalAddedAssets(asset), asset.addedShares);

    asset.addedShares += shares;
    asset.liquidity += amount;
    _spokeAddedShares[assetId][spoke] += shares;
  }

  /// @dev Grows the value of the added shares, so that the shares to assets rate is no longer 1:1
  function accrueInterest(uint256 assetId, uint256 amount) external {
    _assetsData[assetId].interest += amount;
  }

  function add(uint256 assetId, uint256 amount) external returns (uint256) {
    Asset storage asset = _assetsData[assetId];

    require(!spokeDeactivated[msg.sender], SpokeNotActive());
    require(amount != 0, InvalidAmount());

    uint256 liquidity = asset.liquidity + amount;
    require(
      IERC20(asset.underlying).balanceOf(address(this)) >= liquidity,
      InsufficientTransferred()
    );

    uint256 shares = amount.toSharesDown(_totalAddedAssets(asset), asset.addedShares);
    require(shares != 0, InvalidShares());

    asset.addedShares += shares;
    asset.liquidity = liquidity;
    _spokeAddedShares[assetId][msg.sender] += shares;

    return shares;
  }

  function remove(uint256 assetId, uint256 amount, address to) external returns (uint256) {
    Asset storage asset = _assetsData[assetId];

    require(!spokeDeactivated[msg.sender], SpokeNotActive());
    require(amount != 0, InvalidAmount());
    require(amount <= asset.liquidity, InsufficientLiquidity());

    uint256 shares = amount.toSharesUp(_totalAddedAssets(asset), asset.addedShares);

    asset.addedShares -= shares;
    asset.liquidity -= amount;
    _spokeAddedShares[assetId][msg.sender] -= shares;

    IERC20(asset.underlying).safeTransfer(to, amount);

    return shares;
  }

  function eliminateDeficit(
    uint256 assetId,
    uint256 amount,
    address spoke
  ) external returns (uint256, uint256) {
    Asset storage asset = _assetsData[assetId];

    require(!deficitEliminatorRevoked[msg.sender], NotAuthorized());
    require(!spokeDeactivated[msg.sender], SpokeNotActive());

    uint256 deficitRay = _spokeDeficitRay[assetId][spoke];
    uint256 deficitAmountRay = amount < deficitRay.fromRayUp() ? amount.toRay() : deficitRay;
    require(deficitAmountRay != 0, InvalidAmount());

    uint256 deficitToEliminate = deficitAmountRay.fromRayUp();
    uint256 shares = deficitToEliminate.toSharesUp(_totalAddedAssets(asset), asset.addedShares);

    asset.addedShares -= shares;
    asset.deficitRay -= deficitAmountRay;
    _spokeAddedShares[assetId][msg.sender] -= shares;
    _spokeDeficitRay[assetId][spoke] -= deficitAmountRay;

    return (shares, deficitToEliminate);
  }

  function getAssetUnderlyingAndDecimals(uint256 assetId) external view returns (address, uint8) {
    return (_assetsData[assetId].underlying, _assetsData[assetId].decimals);
  }

  function getAssetLiquidity(uint256 assetId) external view returns (uint256) {
    return _assetsData[assetId].liquidity;
  }

  function getAssetDeficitRay(uint256 assetId) external view returns (uint256) {
    return _assetsData[assetId].deficitRay;
  }

  function getSpokeDeficitRay(uint256 assetId, address spoke) external view returns (uint256) {
    return _spokeDeficitRay[assetId][spoke];
  }

  function getSpokeDeficit(uint256 assetId, address spoke) external view returns (uint256) {
    return _spokeDeficitRay[assetId][spoke].fromRayUp();
  }

  function getSpokeAddedShares(uint256 assetId, address spoke) external view returns (uint256) {
    return _spokeAddedShares[assetId][spoke];
  }

  function isSpokeListed(uint256 assetId, address spoke) external view returns (bool) {
    return _listedSpokes[assetId][spoke];
  }

  function previewRemoveByShares(uint256 assetId, uint256 shares) external view returns (uint256) {
    Asset storage asset = _assetsData[assetId];

    return shares.toAssetsDown(_totalAddedAssets(asset), asset.addedShares);
  }

  function _addSpokeDeficitRay(
    uint256 assetId,
    address spoke,
    uint256 amountRay,
    uint256 amount
  ) internal {
    Asset storage asset = _assetsData[assetId];

    require(amount <= asset.liquidity, InsufficientLiquidity());

    asset.liquidity -= amount;
    asset.deficitRay += amountRay;
    _spokeDeficitRay[assetId][spoke] += amountRay;
  }

  /// @dev The deficit is still owed to the suppliers, so it keeps counting towards the value of the added
  /// shares until it is eliminated, exactly as it does inside the `Hub`
  function _totalAddedAssets(Asset storage asset) internal view returns (uint256) {
    return asset.liquidity + asset.interest + asset.deficitRay.fromRayUp();
  }
}
