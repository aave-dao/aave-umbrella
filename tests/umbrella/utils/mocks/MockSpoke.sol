// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

/**
 * @notice Bare `Spoke` exposing the reserve lookup and acting as its own oracle, which is all `UmbrellaSpoke`
 * reads from a covered `spoke` to price its asset.
 */
contract MockSpoke {
  error ReserveNotListed();

  uint8 internal immutable _DECIMALS;
  uint256 internal _price;

  mapping(address hub => mapping(uint256 assetId => bool)) internal _listedReserves;

  constructor(uint256 price, uint8 priceDecimals) {
    _price = price;
    _DECIMALS = priceDecimals;
  }

  function listReserve(address hub, uint256 assetId) external {
    _listedReserves[hub][assetId] = true;
  }

  function setPrice(uint256 price) external {
    _price = price;
  }

  function ORACLE() external view returns (address) {
    return address(this);
  }

  function getReserveId(address hub, uint256 assetId) external view returns (uint256) {
    require(_listedReserves[hub][assetId], ReserveNotListed());
    return assetId;
  }

  function getReservePrice(uint256) external view returns (uint256) {
    return _price;
  }

  function decimals() external view returns (uint8) {
    return _DECIMALS;
  }
}
