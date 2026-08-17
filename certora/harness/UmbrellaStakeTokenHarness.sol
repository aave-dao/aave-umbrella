// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {UmbrellaStakeToken} from 'src/contracts/stakeToken/UmbrellaStakeToken.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {ECDSA} from 'openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol';
import {IRewardsController} from 'src/contracts/rewards/interfaces/IRewardsController.sol';
//import {IRewardsController} from 'src/contracts/stakeToken/interfaces/IRewardsController.sol';

contract UmbrellaStakeTokenHarness is UmbrellaStakeToken {
    constructor(IRewardsController rewardsController) UmbrellaStakeToken (rewardsController) {}

    // Returns amount of the cooldown initiated by the user.
    function cooldownAmount(address user) public view returns (uint192) {
        return getStakerCooldown(user).amount;
    }

    // Returns timestamp of the end-of-cooldown-period initiated by the user.
    function cooldownEndOfCooldown(address user) public view returns (uint32) {
        return getStakerCooldown(user).endOfCooldown;
    }

    function cooldownWithdrawalWindow(address user) public view returns (uint32) {
        return getStakerCooldown(user).withdrawalWindow;
    }

    function get_maxSlashable() external view returns (uint256) {
      return _getMaxSlashableAssets();
    }
}
