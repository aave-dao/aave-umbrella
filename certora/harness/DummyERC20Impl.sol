// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

contract DummyERC20Impl is IERC20 {


    address internal _owner;

    constructor(address owner_){
        _owner = owner_;
    }

    modifier onlyOwner()
    {
        require (msg.sender == _owner, "only owner can access");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    uint256 t;
    mapping (address => uint256) b;
    mapping (address => mapping (address => uint256)) a;

    string public name;
    string public symbol;
    uint public decimals;

    function myAddress() public returns (address) {
        return address(this);
    }

    function add(uint a, uint b) internal pure returns (uint256) {
        uint c = a +b;
        require (c >= a);
        return c;
    }
    function sub(uint a, uint b) internal pure returns (uint256) {
        require (a>=b);
        return a-b;
    }

    function totalSupply() public override view returns (uint256) {
        return t;
    }
    function balanceOf(address account) public view override returns (uint256) {
        return b[account];
    }
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        b[msg.sender] = sub(b[msg.sender], amount);
        b[recipient] = add(b[recipient], amount);
        return true;
    }
    function safeTransfer(address recipient, uint256 amount) external returns (bool) {
        b[msg.sender] = sub(b[msg.sender], amount);
        b[recipient] = add(b[recipient], amount);
        return true;
    }
    function allowance(address owner, address spender) external override view returns (uint256) {
        return a[owner][spender];
    }
    function approve(address spender, uint256 amount) external override returns (bool) {
        a[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        b[sender] = sub(b[sender], amount);
        b[recipient] = add(b[recipient], amount);
        if (sender != recipient)
            a[sender][msg.sender] = sub(a[sender][msg.sender], amount);
        return true;
    }
    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        b[sender] = sub(b[sender], amount);
        b[recipient] = add(b[recipient], amount);
        if (sender != recipient)
            a[sender][msg.sender] = sub(a[sender][msg.sender], amount);
        return true;
    }
}
