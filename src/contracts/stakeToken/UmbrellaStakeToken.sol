// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {IRewardsController} from '../rewards/interfaces/IRewardsController.sol';
import {IUmbrellaConfigurationBase} from '../umbrella/interfaces/IUmbrellaConfigurationBase.sol';

import {IOracleToken} from './interfaces/IOracleToken.sol';
import {StakeToken} from './StakeToken.sol';

contract UmbrellaStakeToken is StakeToken, IOracleToken {
  constructor(IRewardsController rewardsController) StakeToken(rewardsController) {
    _disableInitializers();
  }

  function initialize(
    IERC20 stakedToken,
    string calldata name,
    string calldata symbol,
    address owner,
    uint256 cooldown_,
    uint256 unstakeWindow_
  ) external override initializer {
    __ERC20_init(name, symbol);
    __ERC20Permit_init(name);

    __Pausable_init();

    __Ownable_init(owner);

    __ERC4626StakeTokenUpgradeable_init(stakedToken, cooldown_, unstakeWindow_);
  }

  /// @inheritdoc IOracleToken
  function latestAnswer() external view returns (int256) {
    // The `underlyingPrice` is obtained from an oracle located in `Umbrella`,
    // and the `StakeToken`'s `Owner` is always `Umbrella`, ensuring the call is routed through it.
    uint256 underlyingPrice = uint256(
      IUmbrellaConfigurationBase(owner()).latestUnderlyingAnswer(address(this))
    );

    // price of `StakeToken` should be always less or equal than price of underlying
    return int256((underlyingPrice * 1e18) / convertToShares(1e18));
  }
}
