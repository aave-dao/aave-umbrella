// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import {UmbrellaStakeTokenHarness, IRewardsController} from './UmbrellaStakeTokenHarness.sol';

contract UmbrellaStakeTokenA is UmbrellaStakeTokenHarness {
    constructor(IRewardsController rewardsController) UmbrellaStakeTokenHarness (rewardsController) {}
}
