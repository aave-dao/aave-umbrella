// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

contract MockOracleWithDecimals {
  int256 internal _price;
  uint8 internal immutable _DECIMALS;

  constructor(int256 price, uint8 priceDecimals) {
    _price = price;
    _DECIMALS = priceDecimals;
  }

  function setPrice(int256 price) external {
    _price = price;
  }

  function latestAnswer() external view returns (int256) {
    return _price;
  }

  function decimals() external view returns (uint8) {
    return _DECIMALS;
  }
}
