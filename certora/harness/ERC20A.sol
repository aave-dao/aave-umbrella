// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.8.20;

import { ERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract ERC20A is ERC20 {
    constructor() ERC20("ERC20A","ERC20A") {}
}