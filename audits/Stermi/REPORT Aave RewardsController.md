
<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://raw.githubusercontent.com/aave-dao/aave-brand-kit/refs/heads/main/Logo/Logomark-purple.svg" width="250" height="250" style="padding: 4px;" /></td>
        <td>
            <h1>RewardsController Report</h1>
            <p>Prepared for: Aave DAO</p>
            <p>Code produced by: BGD Labs</p>
            <p>Report prepared by: Emanuele Ricci (StErMi), Independent Security Researcher</p>
        </td>
    </tr>
</table>

# Introduction

A time-boxed security review of the **RewardsController** protocol was done by **StErMi**, with a focus on the security aspects of the application's smart contracts implementation.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise bound effort where I try to find as many vulnerabilities as possible. I can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **RewardsController**

The `RewardsController` is a smart contract to track and allow claiming of rewards, designed exclusively for usage on the `Umbrella` system.

This contract works alongside the Umbrella `StakeTokens` to provide rewards to their holders for securing Aave against bad debt. These rewards can be arbitrary erc-20 tokens, without unexpected functionality (ERC777, fee-on-transfer, and others).

Previous review commit:
- Link: https://github.com/bgd-labs/aave-umbrella-private/tree/main/src/contracts/rewards
- Last commit: `de990c5c7b5c46d52eccab838dabc224adac8b8f`

Latest review commit:
- Link: https://github.com/aave-dao/aave-umbrella/tree/main/src/contracts/umbrella
- Last commit: `62f3850816b257087e92f41a7f37a698f00fa96e`

# About **StErMi**

**StErMi**, is an independent smart contract security researcher. He serves as a Lead Security Researcher at Spearbit and has identified multiple bugs in the wild on Immunefi and on protocol's bounty programs like the Aave Bug Bounty.

Do you want to connect with him?
- [stermi.xyz website](https://stermi.xyz/)
- [@StErMi on Twitter](https://twitter.com/StErMi)

# Summary & Scope

**_review commit hash_ - [5ff579e22d9622d46164c806f8a348954b11baa6](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6)**

# Post Review Update: validating commit `62f3850` AAVE DAO Umbrella repository

AAVE DAO has requested to review the differences between the last commit [5b987d2](https://github.com/bgd-labs/aave-umbrella-private/commit/5b987d222355a1a8fa4b475e7f31968f66dd2394) reviewed in the BGD Labs AAVE Umbrella repository and the commit [`62f3850`](https://github.com/aave-dao/aave-umbrella/commit/62f3850816b257087e92f41a7f37a698f00fa96e) from the AAVE DAO Umbrella repository that will be used as the official reference.

At the end of the report you can find all the details relative to the validation of the differences and the confirmation that, apart from the mentioned differences the code is the same as the one that has been previously reviewed.

# Severity classification

| Severity               | Impact: High | Impact: Medium | Impact: Low |
| ---------------------- | ------------ | -------------- | ----------- |
| **Likelihood: High**   | Critical     | High           | Medium      |
| **Likelihood: Medium** | High         | Medium         | Low         |
| **Likelihood: Low**    | Medium       | Low            | Low         |

**Impact** - the technical, economic and reputation damage of a successful attack
**Likelihood** - the chance that a particular vulnerability gets discovered and exploited
**Severity** - the overall criticality of the risk

---
# Findings Summary
| ID     | Title                                                                                                         | Severity | Status          |
| ------ | ------------------------------------------------------------------------------------------------------------- | -------- | --------------- |
| [I-01] | General informational issues                                                                                  | Info     | Fixed           |
| [I-02] | User could lose accrued reward depending on the balance and reward's index delta                              | Info     | Fixed           |
| [I-03] | `ClaimerSet` event should track the original caller                                                           | Info     | Fixed           |
| [I-04] | Additional sanity checks                                                                                      | Info     | Fixed           |
| [I-05] | Numbers in the `MAX_EMISSION_VALUE_PER_SECOND` natspec are an order of magnitude lower than expected          | Info     | Fixed           |
| [I-06] | `EmissionMath` dev comments should be rewritten to address inaccuracies and provide clearer assumptions       | Info     | Partially Fixed |
| [I-07] | `maxEmissionPerSecond` could be not accurate when distribution has ended but need to perform the last accrual | Info     | Partially Fixed |
| [I-08] | Consider early returning in `updateAsset` and `updateAssetAndUserData` when there's no supply                 | Info     | Fixed           |

# [I-01] General informational issues
## Description

### Natspec typos, errors or improvements

- [x] [IRewardsController.sol#L251](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/interfaces/IRewardsController.sol#L251) + [IRewardsController.sol#L265](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/interfaces/IRewardsController.sol#L265): the natspec of both `getUserDataByAsset` and `getUserDataByReward` should specify and underlying that "last update" refers to the user's reward index and not the asset one. The function's logic does not check if the user's index is "lagging" compared to the reward one. The reward index could have been already up-to-date (because of another user tx or an external call) but the user's index for the `(asset, reward)` could still be lagging.
- [x] [EmissionMath.sol#L37](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L37): the `MAX_EMISSION_VALUE_PER_SECOND` natspec should be rewritten. `1000e18` token per second multiplied by the number of seconds per year is `~31_536_000_000` tokens, which is one order of magnitude more. If the price of rewards is `0.01 USD` then the total reward distributed per year is `315M USD` and not `31M USD` like stated in the comment. BGD should also consider if the new values are still acceptable for every market, or if the `MAX_EMISSION_VALUE_PER_SECOND` upper bound should be reconsidered and lowered.
- [x] [README.md?plain=1#L108](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/README.md?plain=1#L108): the **maximum** upper bound of `~1e35` for `targetLiquidity` could be explicitly explained to make it more clear. The upper bound is indirectly provided by the further validation performed on the minimum value required for the `maxEmissionPerSecond` that must be `<= 1e21` but **also** `>= targetLiquidity * 1e3 / 1e18`
- [x] [EmissionMath.sol#L248](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L248): `decreaseInEmission` should be replaced by `emissionDecrease` in the `_slopeCurve` dev comment
- [x] [EmissionMath.sol#L261](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L261): `constEmission` should be replaced by `flatEmission` in the `_linearDecreaseCurve` dev comment
- [x] [IRewardsDistributor.sol#L134](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/interfaces/IRewardsDistributor.sol#L134): type in the natspec docs. `AArray` should be related with `Array`
- [x] [IRewardsController.sol#L59](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/interfaces/IRewardsController.sol#L59): the natspec should disclose that the `UserDataUpdated` could also be triggered in a permissionless way, without the `user` consent. This happens when `updateAssetAndUserData(address asset, address user)` is executed by a `msg.sender` that is not the `user` itself.
- [x] [IRewardsController.sol#L157](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/interfaces/IRewardsController.sol#L157): the `handleAction` is also called when the `StakeToken.slash` function is executed. The natspec should be updated accordingly.

### Renaming and refactoring

- [x] The codebase widely uses the pattern `require(statement, CustomError)` but there are some places where the revert is thrown inside an `if` statement`. Consider using only the `require` pattern for a better readability of the codebase.
- [x] [RewardsController.sol#L767-L784](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L767-L784): consider refactoring the `_validateOtherRewardEmissions` logic. The gas saving to skip some `EmissionMath.validateMaxEmission` calls (which is just a `pure` function) is not worth the additional complexity of code.

### Code improvement

- [ ] [RewardsController.sol#L296-L312](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L296-L312) + [RewardsController.sol#L270-L294](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L270-L294): consider including in the return data of `getUserDataByAsset` and `getUserDataByReward` the `asset.lastUpdateTimestamp`. The currently returned information is not enough to let the caller know if the `accrued` rewards are up-to-date.
- [ ] [RewardsController.sol#L84-L101](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L84-L101): consider refactoring and simplify the `configureAssetWithRewards` function. This function allows the caller to
	- init asset without rewards
	- init asset with rewards
	- update asset `targetLiquidity` without rewards
	- update asset `targetLiquidity` with rewards as parameters
	- add new rewards to an existing asset
	- update existing rewards of an existing asset
	- ...
The complexity of the logic could be simplified by splitting it into multiple smaller `external` functions that will follow the [KISS](https://en.wikipedia.org/wiki/KISS_principle) principles. This will make the code simpler to read and maintain, and more robust from both a security and role-based access point of view.

## Recommendations

BGD should fix all the suggestions listed in the above section

**StErMi:**

- "Code improvement 1" has been acknowledged and will not be implemented
- "Code improvement 2" has been acknowledged and will not be implemented

The remaining recommendations have been implemented in the [PR 101](https://github.com/bgd-labs/aave-umbrella-private/pull/101)

# [I-02] User could lose accrued reward depending on the balance and reward's index delta
## Context

- [RewardsController.sol#L701-L705](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L701-L705)
- [EmissionMath.sol#L146-L159](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L146-L159)

## Description

The amount of scaled reward accrued by the user depends on two factors:
- the delta between the reward index and the user's index
- the stake token balance of the user

The amount of rewards accrued by the user that need to be accounted into `userData.accrued` is calculated as following

```solidity
  function calculateAccrued(
    uint152 newRewardIndex,
    uint152 oldUserIndex,
    uint256 userBalance
  ) internal pure returns (uint112) {
    return ((userBalance * (newRewardIndex - oldUserIndex)) / SCALING_FACTOR).toUint112();
  }
```

if the user's balance or the reward's delta is small enough that `(userBalance * (newRewardIndex - oldUserIndex)) < SCALING_FACTOR`, the user will **lose** the accrued reward for that timeframe given that, no matter what the `newAccruedAmount` value is, the local user's index for the reward will be updated

```
    userData.accrued += newAccruedAmount;
    userData.index = rewardData.index;
```

While this behavior could be valid when the user is the one that is actively triggering the `_updateUserData` (via `handleAction`), a malicious actor could trigger this worst-case scenario without the user consent via the permissionless function `updateAssetAndUserData`

```solidity


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import {RewardsControllerBaseTest, StakeToken, IRewardsDistributor, IRewardsStructs} from './utils/RewardsControllerBase.t.sol';


contract SRewardUserTest is RewardsControllerBaseTest {

  function setUp() public override {
    super.setUp();

    _dealUnderlying(address(reward18Decimals), rewardsAdmin, 2 * 365 days * 1e12);
    _dealUnderlying(address(reward6Decimals), rewardsAdmin, 2 * 365 days * 1);

    vm.startPrank(rewardsAdmin);
    reward18Decimals.approve(address(rewardsController), 2 * 365 days * 1e12);
    reward6Decimals.approve(address(rewardsController), 2 * 365 days * 1);
    vm.stopPrank();
  }

  function testNoAccrual() public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: 1e12,
      targetLiquidity: 10_000_000 * 1e18
    });

    // user stake 10k tokens
    _dealStakeToken(StakeToken(asset), user, 1000 * 1e18);
    vm.warp(block.timestamp+1);

    uint256 rewardIndexBefore = rewardsController.calculateRewardIndex(asset, reward);
    vm.warp(block.timestamp+1);
    uint256 rewardIndexAfter = rewardsController.calculateRewardIndex(asset, reward);

    // userBalance < SCALING_FACTOR / (newRewardIndex - oldUserIndex)
    uint256 balanceToGainNoReward = 1e18 / (rewardIndexAfter - rewardIndexBefore);
    assertGt(balanceToGainNoReward, 0);

    // setup alice
    address alice = makeAddr('alice');
    _dealStakeToken(StakeToken(asset), alice, balanceToGainNoReward);

    vm.warp(block.timestamp+1);
    uint256 accruedRewardScaled = rewardsController.calculateCurrentUserReward(asset, reward, alice);
    assertEq(accruedRewardScaled, 0);

  }

  function _setupAsset(address asset, address reward, uint256 maxEmission, uint256 targetLiquidity) internal {
    vm.startPrank(defaultAdmin);
    IRewardsStructs.RewardSetupConfig[] memory rewards = new IRewardsStructs.RewardSetupConfig[](1);
    rewards[0] = IRewardsStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: address(rewardsAdmin),
      maxEmissionPerSecond: maxEmission,
      distributionEnd: (block.timestamp + 365 days)
    });

    rewardsController.configureAssetWithRewards(
      asset,
      targetLiquidity,
      rewards
    );
    vm.stopPrank();
  }

}
```

## Recommendation

BGD should:
- document the above edge case scenario where the user could effectively lose the accrual of rewards when the user's balance and index delta is tiny
- change the visibility of `updateAssetAndUserData` from `public` to `private` or restrict it to only the user or authed claimers (of the user)

**StErMi:** The recommendations have been implemented in the [PR 96](https://github.com/bgd-labs/aave-umbrella-private/pull/96). The `updateAssetAndUserData` has been removed, and the edge case has been documented in the `README` file.

# [I-03] `ClaimerSet` event should track the original caller
## Context

- [RewardsDistributor.sol#L168-L172](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsDistributor.sol#L168-L172)

## Description

The internal function `_setClaimer` can be triggered by the user's itself or anyone who has the `DEFAULT_ADMIN_ROLE` role

```solidity
  function _setClaimer(address user, address claimer, bool flag) internal {
    _getRewardsDistributorStorage().authorizedClaimers[user][claimer] = flag;

    emit ClaimerSet(user, claimer, flag);
  }
```

As shown above, the current implementation does only track the `user` address in the `ClaimerSet` event, while it could be beneficial to also track the `msg.sender` that could indeed be not the user itself.

## Recommendation

BGD should add the `initiator` or `caller` information in the `ClaimerSet` event

**StErMi:** The recommendations have been implemented in the [PR 100](https://github.com/bgd-labs/aave-umbrella-private/pull/100)

# [I-04] Additional sanity checks

## Description

- [x] [RewardsDistributor.sol#L169](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsDistributor.sol#L169): `_setClaimer` should revert if `claimer` is `address(0)`
- [x] [RewardsController.sol#L109](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L109): `RewardsController.setClaimer` should revert if `user` is `address(0)`

## Recommendations

BGD should consider implementing the above suggested sanity checks

**StErMi:** The recommendations have been implemented in the [PR 99](https://github.com/bgd-labs/aave-umbrella-private/pull/99)

# [I-05] Numbers in the `MAX_EMISSION_VALUE_PER_SECOND` natspec are an order of magnitude lower than expected

## Context

- [EmissionMath.sol#L36-L38](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L36-L38)

## Description

The `MAX_EMISSION_VALUE_PER_SECOND = 1_000 * 1e18` constant variables is used as an upper bound for the `maxEmissionPerSecondScaled` validation (emission per second, eventually scaled up to 18 decimals).

The current documentation states that

> (~3_150_000_000 tokens per year, if price of reward token is at least 0.01 USD, then it's 32 million USD, which is ok for every market)

But in reality `1000` tokens per second, multiplied by the seconds in a year are `~31_536_000_000` tokens per year, which is an order of magnitude greater than the one stated in the comment. With a reward value of at least `0.01 USD` per token, the contract could distribute around `315 millions USD`

## Recommendations

BGD should update the natspec comment for the `MAX_EMISSION_VALUE_PER_SECOND` variable with the correct value, and consider lowering this upper bound if the updated monetary value is not valid for every market.

**StErMi:** The natspec documentation has been updated in the [PR 98](https://github.com/bgd-labs/aave-umbrella-private/pull/98). BGD has decided to **not** update the value of the upper bound represented by the constant `MAX_EMISSION_VALUE_PER_SECOND`.

# [I-06] `EmissionMath` dev comments should be rewritten to address inaccuracies and provide clearer assumptions
## Description

The dev comments in the `calculateIndexIncrease` function of `EmissionMath` try to prove three points:
1) `indexIncrease` cannot overflow `uint144`
2) `indexIncrease` is always greater than zero even when `timeDelta == 1 second`
3) `maxEmissionPerSecond * SCALING_FACTOR * totalAssets / targetLiquidity < 1` cannot round down to zero

The current comments contain multiple inaccuracies, and both the requirements (enforced by validations) and assumptions (written as comments) could be written in a much more clean and easier way to read.

### Inaccuracy 1

[EmissionMath.sol#L140-L141](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L140-L141): `maxEmissionPerSecond` can't be `1 wei`. The minimum lower bound is `2 wei`, see the `validateMaxEmission` logic. The dev comment in `calculateIndexIncrease` should be rewritten.

### Inaccuracy 2

[EmissionMath.sol#L116-L138](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L116-L138): the math formulas and simplifications used to prove the second point are correct but are not considering the fact that in Solidity divisions could round down (errors) and the order of operations matter. This is not enough to prove that `indexIncrease` will always be greater than zero.

### Inaccuracy 3

[EmissionMath.sol#L102-L114](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L102-L114): the minimum number of years needed to make the `indexIncrease` overflow is wrong.

- `maxEmissionPerSecond` upper bound is `1_000e18` so `currentEmission` can be at most `1_000e18 * SCALING_FACTOR === 1e39` when we reach peak emission when `totalAssets == targetLiquidity`
- the lower possible value for `totalSupply` is equal to `DEAD_SHARES` that is equal to `1e6`

This means that `indexIncrease` will overflow when `timeDelta >= ~2.23e43 * 1e6 / 1e3` which is around `~707 years` and not `70.7 years` as stated by the current docs.

### Inaccuracy 4

[EmissionMath.sol#L127](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L127): `StakeToken` can be any `ERC20` token and not only a `StataToken`

- `ERC20` tokens supply is `uint256`
- `StataToken` supply is `uint256`
- `AToken` supply is `uint256`

It's true that in `StakeToken` the `_totalAssets` is a `uint192` type, but it's also true that is **slashable**. This means that theoretically you **can** keep supplying and mint up to `uint256` shares of the `StakeToken`

### Inaccuracy 5

[EmissionMath.sol#L263](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L263): the dev comment is wrong because the returned emission is in the range of `(constEmission; maxEmission]` and not `(constEmission; maxEmission)`. We can construct cases for which `((maxEmission - flatEmission) * (totalAssets - targetLiquidity))` is smaller than `(targetLiquidityExcess - targetLiquidity)` and the operations will round down to `0`.

When it happens, we have `(maxEmission - 0) * SCALING_FACTOR == maxEmission * SCALING_FACTOR` which is equal to `maxEmission`.

```solidity
  function roundTermToZero(uint256 maxEmission, uint256 totalAssets, uint256 targetLiquidity) public {
    targetLiquidity = bound(targetLiquidity, 1e18, 10_000_000e18);
    uint256 precisionBound = (targetLiquidity * 1000) / 1e18;
    uint256 minBound = precisionBound > 2 ? precisionBound : 2;
    maxEmission = bound(targetLiquidity, minBound, 1000e18);

    uint256 targetLiquidityExcess = _percentMulDiv(targetLiquidity, FLAT_EMISSION_LIQUIDITY_BOUND);

    totalAssets = bound(totalAssets, targetLiquidity+1, targetLiquidityExcess-1);

    assertLe(totalAssets / targetLiquidity, 10);

    uint256 flatEmission = _percentMulDiv(maxEmission, FLAT_EMISSION_BPS);
    uint256 term =
      ((maxEmission - flatEmission) * (totalAssets - targetLiquidity))
        /
        (targetLiquidityExcess - targetLiquidity);

    assertGt(term, 0);
  }
```

### Inaccuracy 6

It's possible to find edge case scenarios where `indexIncrease` can be equal to zero and no rewards are accrued, even if the configuration respects both the "hard requirements" (enforced by logic validation) and "soft requirements" (written assumptions). Even if those are indeed edge scenarios, it means that hard requirements or soft requirements should be improved (more restrictive) and detailed in a more clean way.

All the edge cases can be found in the in-depth discussion "[DISCUSSION] Rounding `indexIncrease` to zero for `timeDelta == 1`"

### Recommendation 1

[EmissionMath.sol#L96](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/libraries/EmissionMath.sol#L96): `totalSupply` should be added to the list of "soft requirements" (written assumptions not enforced by any validation). Currently, we have the following assumptions:

1) `totalAssets/targetLiquidity <= 10`: users are not encouraged to stake (at risk) funds for getting a fraction of rewards
2) `totalSupply/totalAssets <= 1000`: this means that the ration of stakes/after-slash amount must at most be 1000 times. After that you will re-deploy the `StakeToken`

Because there's no "direct" correlation and assumptions between `targetLiquidity` and `totalSupply`, this allows to craft valid (respecting both existing requirements and assumptions) edge configurations to build a "valid" scenario where we can indeed bring the `indexIncrease` down to zero with a sequence of deposit+slash and still respect the above two assumptions.

See case "flat emission" in "[DISCUSSION] Rounding `indexIncrease` to zero for `timeDelta == 1`"

## Recommendation

BGD should consider addressing all the above listed inaccuracies and recommendations

**BGD:** `EmissionMath` comments should be fixed here: [PR 102](https://github.com/bgd-labs/aave-umbrella-private/pull/102)

# [I-07] `maxEmissionPerSecond` could be not accurate when distribution has ended but need to perform the last accrual
## Context

- [RewardsController.sol#L382-L384](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L382-L384)

## Description

An `(asset, reward)` distribution has ended when `block.timestamp > _getRewardsControllerStorage().assetsData[asset].data[reward].rewardData.distributionEnd`. When a distribution has ended, the `maxEmissionPerSecond` will be equal to zero because no more rewards will be distributed and accrued to users.

There is still an edge case to be configured, when the distribution, given `block.timestamp`, has ended, but it has not yet accounted for the very last accrual of rewards.

Here's the `getRewardData` code as an example.

```solidity
  /// @inheritdoc IRewardsController
  function getRewardData(
    address asset,
    address reward
  ) public view returns (RewardDataExternal memory) {
    InternalStructs.RewardData memory rewardData = _getRewardsControllerStorage()
      .assetsData[asset]
      .data[reward]
      .rewardData;
    uint256 maxEmissionPerSecond = block.timestamp < rewardData.distributionEnd
      ? rewardData.maxEmissionPerSecondScaled.scaleDown(rewardData.decimalsScaling)
      : 0;

    return
      RewardDataExternal({
        addr: reward,
        index: rewardData.index,
        maxEmissionPerSecond: maxEmissionPerSecond,
        distributionEnd: rewardData.distributionEnd
      });
  }
```

Let's assume that we have an `(a1, r1)` distribution where:

- `block.timestamp = 1000`
- `a1.lastUpdateTimestamp = 500`
- `r1.distributionEnd = 700`

The above scenario describes a situation where the asset has been updated at `T500` but the distribution has still `200` seconds to accrue rewards toward the users. It's true that the distribution has "ended" already in some way, but those 200 seconds must yet to be accounted for once the next update is triggered.

This issue is present in both `getRewardData`, `getEmissionData` and `getAssetAndRewardsData` (which internally calls `getRewardData`). We could even expand it to `calculateCurrentEmissionScaled` even if the function's name includes the keyword "current".

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import {RewardsControllerBaseTest, StakeToken, IRewardsDistributor, IRewardsStructs} from './utils/RewardsControllerBase.t.sol';


contract SRewardUserTest is RewardsControllerBaseTest {

  function setUp() public override {
    super.setUp();

    _dealUnderlying(address(reward18Decimals), rewardsAdmin, 2 * 365 days * 1e12);

    vm.startPrank(rewardsAdmin);
    reward18Decimals.approve(address(rewardsController), 2 * 365 days * 1e12);
  }

  function testAssetDataWrong() public {
    vm.warp(1000);
    _dealStakeToken(stakeWith18Decimals, user, 10_000_000 * 1e18);

    vm.startPrank(defaultAdmin);
    IRewardsStructs.RewardSetupConfig[] memory rewards = new IRewardsStructs.RewardSetupConfig[](1);
    rewards[0] = IRewardsStructs.RewardSetupConfig({
      reward: address(reward18Decimals),
      rewardPayer: address(rewardsAdmin),
      maxEmissionPerSecond: 1e18, // 1 reward each second
      distributionEnd: (block.timestamp + 10) // 10 seconds
    });

    rewardsController.configureAssetWithRewards(
      address(stakeWith18Decimals),
      10_000_000 * 1e18,
      rewards
    );

    // warp 5 seconds
    vm.warp(block.timestamp + 5);

    // apply the update writing data
    rewardsController.updateAsset(address(stakeWith18Decimals));

    IRewardsStructs.RewardDataExternal memory rdeBefore = rewardsController.getRewardData(address(stakeWith18Decimals), address(reward18Decimals));
    uint userRewardsBefore = rewardsController.calculateCurrentUserReward(address(stakeWith18Decimals), address(reward18Decimals), user);
    assertGt(userRewardsBefore, 0);
    assertGt(rdeBefore.maxEmissionPerSecond, 0);

    vm.warp(block.timestamp+5);
    IRewardsStructs.RewardDataExternal memory rdeAfter_1 = rewardsController.getRewardData(address(stakeWith18Decimals), address(reward18Decimals));
    uint userRewardsAfter = rewardsController.calculateCurrentUserReward(address(stakeWith18Decimals), address(reward18Decimals), user);

    // this prove that user needs to still
    assertGt(userRewardsAfter, userRewardsBefore);
    assertEq(rdeAfter_1.maxEmissionPerSecond, 0);

    // apply the update writing data
    // the index has been updated and is greater than 5 seconds before because even if the distributon, relative to `block.timestamp`
    // was really ended, it still had to accrue some index (and rewards) relative to the asset `lastUpdateTimestamp`
    rewardsController.updateAsset(address(stakeWith18Decimals));
    IRewardsStructs.RewardDataExternal memory rdeAfter_2 = rewardsController.getRewardData(address(stakeWith18Decimals), address(reward18Decimals));
    assertGt(rdeAfter_2.index, rdeBefore.index);

  }
}
```

## Recommendation

Returning `maxEmissionPerSecond` as `zero` is both valid and invalid, depending on the POV and the logic of the caller.

BGD should consider the possible use case of the integrators and include additional data to the returned one to allow the integrators to make proper decision. For example, a boolean value that lets the integrator know if the distribution has ended but still need to perform the last accrual.
Both the code and the natspec of `IRewardsController` for these functions should disclose this edge case scenario.

**StErMi:** BGD, in the [PR 97](https://github.com/bgd-labs/aave-umbrella-private/pull/97), has decided to acknowledge and document this behaviour without any changes in the smart contract logic.

# [I-08] Consider early returning in `updateAsset` and `updateAssetAndUserData` when there's no supply
## Context

- [RewardsController.sol#L159-L170](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L159-L170)
- [RewardsController.sol#L332-L343](https://github.com/bgd-labs/aave-umbrella-private/blob/5ff579e22d9622d46164c806f8a348954b11baa6/src/contracts/rewards/RewardsController.sol#L332-L343)

## Description

The  `updateAsset` and `updateAssetAndUserData` functions allow any external entity to update all the rewards distributions of an asset and the user's `index`.

When there's no supply for the `StakeToken` identified by `asset`, these functions will just perform a no-op (no distribution's index will be updated, nor the user's index for such distribution) that will emit "spammy" and useless events
- the `LastTimestampUpdated` event will be emitted with `newTimestamp == block.timestamp`
- the `RewardIndexUpdated` event will be emitted with `newIndex == 0`

This happens because when `totalSupply` is equal to `0` the `currentEmission` returned by `getEmissionPerSecondScaled` will also be equal to `0`.

## Recommendation

BGD should consider early returning or reverting the `updateAsset` and `updateAssetAndUserData` execution when the `totalSupply` of the `asset` is equal to zero.

The same behavior will happen when a user performs a deposit in an empty staked token and `_updateData` will be triggered by `handleAction`, but we can consider this case as the "normal" behavior that is not triggered **actively** by an external actor.

**StErMi:** The recommendations have been implemented in the [PR 96](https://github.com/bgd-labs/aave-umbrella-private/pull/96). The `updateAssetAndUserData` has been removed and `updateAsset` execute `_updateData` only when `totalSupply > 0`.

# [DISCUSSION] Rounding `indexIncrease` to zero for `timeDelta == 1`

I'm looking for edge cases that would prove that it's possible, even with the current requirements, restrictions and assumptions, to round down the `indexIncrease` to zero.

`uint256 indexIncrease = (currentEmission * timeDelta) / totalSupply;`

To make it happen, the goal here is to find ways to:
- decrease `currentEmission`
- increase `totalSupply`

to reach a point where  `currentEmission < totalSupply` and so the division will round down to `0`

I think that we can start by saying that the `StakeToken` has already some `> 0` deposit to simplify things. On top of that we have the following assumptions (give the existing logic):

- `totalAssets <= totalSupply`: `StakeToken` slashes reduce only the `totalAssets`
- `totalAssets >= 1e6`, even after slashes, this is the bare minimum value enforced by `StakeToken` (when the assets staked were already above that value)
- `totalSupply` is **always** `> 1e6` (see `DEAD_SHARES`)
- `targetLiquidity >= 10 ** STAKE_TOKEN_DECIMALS`
- `maxEmissionPerSecondScaled <= 1000e18` (but we don't care to increase it)
- `maxEmissionPerSecondScaled >= 2 wei` when `targetLiquidity * 1000 / 1e18 <=2 `
- otherwise `maxEmissionPerSecondScaled >= targetLiquidity * 1000 / 1e18`
## Case "flat emission": `totalAssets > targetLiquidityExcess` (120% of `targetLiquidity`)

In this case, we know that `currentEmission == (maxEmissionPerSecondScaled * 80_00 / 100_00) * SCALING_FACTOR` so we need to reach a point where

`(maxEmissionPerSecondScaled * 80_00 / 100_00) * SCALING_FACTOR < totalSupply`

we know that
- `totalAssets >= targetLiquidity * 120_00 / 100_00`
- `totalSupply >= totalAssets`

Let's assume our `StakeToken` is a `18 decimals` token.
- Min value for `targetLiquidity`: `10 ** 18 == 1e18`
- Min value for `maxEmissionPerSecondScaled`: `1e3 == 1000`
- `totalAssets >= 1.2e18`
- `totalSupply >= 1.2e18`

Assuming that at most `totalAssets/targetLiquidity = 10` (as stated in the dev comments of `calculateIndexIncrease`) and that there's no slash (`totalSupply == totalAssets`)

`indexIncrease = 800 * 1e18 / (1e18 * 10) = 80`

In the case we can perform slashes, we can build a sequence of `deposit + slash` actions that will bring down the `indexIncrease` to **zero** but still respecting both the requirements
1) deposit `10e18`
2) slash `10e18`
3) deposit `9.99e18`

at the end we will have
- `totalAssets / targetLiquidity = 10`
- `totalSupply / totalAssets = 999`
- `totalAssets = 10e18`
- `totalSupply = 9999.99999e18`

`indexIncrease = 800 * 1e18 / 9999.99999e18 = 0`
## Case "linear decrease curve": `targetLiquidity < totalAssets < targetLiquidityExcess` (120% of `targetLiquidity`)

In this case the `currentEmission` is provided by the formula

```solidity
(maxEmission -
   (
		((maxEmission - flatEmission) * (totalAssets - targetLiquidity))
		/
        (targetLiquidityExcess - targetLiquidity)
    )
) * SCALING_FACTOR;
```

the minimum possible emission is when `totalAssets` is just below the `targetLiquidityExcess`. We can replace `totalAssets` with `targetLiquidityExcess - 1 wei` which is equal to `(targetLiquidity * 1.2) - 1 wei` and `flatEmission` with `maxEmission * 0.8`

`maxEmission - ( (maxEmission - maxEmission*0.8) * (targetLiquidity*1.2 - 1 - targetLiquidity) / (targetLiquidity*1.2 - targetLiquidity)) * SCALING_FACTOR`

Given that we're tending towards `targetLiquidityExcess` we can approximate the same scenario shown is such case with the very same results. The `indexIncrease` should be greater of just `1 wei` compared to such case.

## Test

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import 'forge-std/console.sol';
import {RewardsControllerBaseTest, StakeToken, IRewardsDistributor, IRewardsStructs} from './utils/RewardsControllerBase.t.sol';
import {EmissionMath} from '../../src/contracts/rewards/libraries/EmissionMath.sol';

contract SCheckEmissionMathTest is RewardsControllerBaseTest {
  address alice = makeAddr('alice');

  function setUp() public override {
    super.setUp();

    _dealUnderlying(address(reward18Decimals), rewardsAdmin, 2 * 365 days * 1e12);
    _dealUnderlying(address(reward6Decimals), rewardsAdmin, 2 * 365 days * 1);

    vm.startPrank(rewardsAdmin);
    reward18Decimals.approve(address(rewardsController), 2 * 365 days * 1e12);
    reward6Decimals.approve(address(rewardsController), 2 * 365 days * 1);
    vm.stopPrank();
  }

  function testSlope_18_noslash(uint256 maxDeposit) public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    uint256 targetLiquidity = 1e18;
    uint256 minViableEmission = _minEmission(targetLiquidity);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: minViableEmission,
      targetLiquidity: targetLiquidity
    });

    // max deposit to still be within the linear decrease curve AND just above the
    maxDeposit = bound(maxDeposit, 1e6, 1e18);

    _dealStakeToken(StakeToken(asset), alice, maxDeposit);

    assertLe(StakeToken(asset).totalAssets() / targetLiquidity, 10);
    assertLe(StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets(), 1000);

    uint256 indexBefore = rewardsController.calculateRewardIndex(asset, reward);

    vm.warp(block.timestamp + 1);
    rewardsController.updateAsset(asset);

    uint256 indexAfter = rewardsController.calculateRewardIndex(asset, reward);

    assertGt(indexAfter - indexBefore, 0);
  }

  function testLinearDecrease_18_noslash() public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    uint256 targetLiquidity = 1e18;
    uint256 minViableEmission = _minEmission(targetLiquidity);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: minViableEmission,
      targetLiquidity: targetLiquidity
    });

    // max deposit to still be within the linear decrease curve AND just above the
    uint256 maxDeposit = ((targetLiquidity * 120_00) / 100_00) - 1;

    _dealStakeToken(StakeToken(asset), alice, maxDeposit);

    assertLe(StakeToken(asset).totalAssets() / targetLiquidity, 10);
    assertLe(StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets(), 1000);

    vm.warp(block.timestamp + 1);
    rewardsController.updateAsset(asset);
  }

  function testLinearDecrease_18_slash() public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    uint256 targetLiquidity = 1e18;
    uint256 minViableEmission = _minEmission(targetLiquidity);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: minViableEmission,
      targetLiquidity: targetLiquidity
    });

    uint256 snapshotId;
    while (true) {
      // try to always be inside the linear decrease curve case. deposited assets must be `>targetLiquidity` but `<targetLiquidityExcess`
      uint256 maxDeposit = (((targetLiquidity * 120_00) / 100_00) - 1) -
        StakeToken(asset).totalAssets();

      // deposit
      _dealStakeToken(StakeToken(asset), alice, maxDeposit);

      snapshotId = vm.snapshot();

      // slash
      uint256 slashAmount = _slashMax(asset);

      if (StakeToken(asset).totalAssets() / targetLiquidity > 10) {
        break;
      }

      if (StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets() > 1000) {
        // revert back to pre-slash to have a "valid" assets/supply ratio
        // I could probably calculate the exact value to be slashed to respect the invariant
        // and keep iterating even more, but this is already enough
        vm.revertTo(snapshotId);
        break;
      }
    }

    assertLe(StakeToken(asset).totalAssets() / targetLiquidity, 10);
    assertLe(StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets(), 1000);

    uint256 indexBefore = rewardsController.calculateRewardIndex(asset, reward);

    vm.warp(block.timestamp + 1);
    rewardsController.updateAsset(asset);

    uint256 indexAfter = rewardsController.calculateRewardIndex(asset, reward);

    assertEq(indexAfter - indexBefore, 0);
  }

  function testFlatEmission_18_noslash() public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    uint256 targetLiquidity = 1e18;
    uint256 minViableEmission = _minEmission(targetLiquidity);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: minViableEmission,
      targetLiquidity: targetLiquidity
    });

    // max deposit to still be within the linear decrease curve AND just above the
    uint256 maxDeposit = ((targetLiquidity * 120_00) / 100_00);

    _dealStakeToken(StakeToken(asset), alice, maxDeposit);

    assertLe(StakeToken(asset).totalAssets() / targetLiquidity, 10);
    assertLe(StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets(), 1000);

    vm.warp(block.timestamp + 1);
    rewardsController.updateAsset(asset);
  }

  function testFlatEmission_18_slash() public {
    address asset = address(stakeWith18Decimals);
    address reward = address(reward18Decimals);

    uint256 targetLiquidity = 1e18;
    uint256 minViableEmission = _minEmission(targetLiquidity);

    _setupAsset({
      asset: asset,
      reward: reward,
      maxEmission: minViableEmission,
      targetLiquidity: targetLiquidity
    });

    uint256 snapshotId;
    while (true) {
      // after the deposit we need to respect `
      uint256 maxDeposit = (10 * targetLiquidity) - StakeToken(asset).totalAssets();

      // deposit
      _dealStakeToken(StakeToken(asset), alice, maxDeposit);

      snapshotId = vm.snapshot();

      // slash
      uint256 slashAmount = _slashMax(asset);

      if (StakeToken(asset).totalAssets() / targetLiquidity > 10) {
        break;
      }


      if (StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets() > 1000) {
        // revert back to pre-slash to have a "valid" assets/supply ratio
        // I could probably calculate the exact value to be slashed to respect the invariant
        // and keep iterating even more, but this is already enough
        vm.revertTo(snapshotId);
        break;
      }

    }

    assertLe(StakeToken(asset).totalAssets() / targetLiquidity, 10);
    assertLe(StakeToken(asset).totalSupply() / StakeToken(asset).totalAssets(), 1000);

    uint256 indexBefore = rewardsController.calculateRewardIndex(asset, reward);

    vm.warp(block.timestamp + 1);
    rewardsController.updateAsset(asset);

    uint256 indexAfter = rewardsController.calculateRewardIndex(asset, reward);

    assertEq(indexAfter - indexBefore, 0);
  }

  function _minEmission(uint256 targetLiquidity) internal returns (uint256) {
    uint256 precisionBound = (targetLiquidity * 1000) / 1e18;
    return precisionBound > 2 ? precisionBound : 2;
  }

  function _slashMax(address asset) internal returns (uint256) {
    uint256 currentDeposit = StakeToken(asset).totalAssets();
    uint256 slashAmount = currentDeposit - (currentDeposit / 1e3);

    // slash
    vm.startPrank(umbrellaController);
    StakeToken(asset).slash(someone, slashAmount);
    // assertEq(StakeToken(stakeToken).totalSupply()/StakeToken(stakeToken).totalAssets(), 1000);
    vm.stopPrank();

    return slashAmount;
  }

  function _setupAsset(
    address asset,
    address reward,
    uint256 maxEmission,
    uint256 targetLiquidity
  ) internal {
    vm.startPrank(defaultAdmin);
    IRewardsStructs.RewardSetupConfig[] memory rewards = new IRewardsStructs.RewardSetupConfig[](1);
    rewards[0] = IRewardsStructs.RewardSetupConfig({
      reward: reward,
      rewardPayer: address(rewardsAdmin),
      maxEmissionPerSecond: maxEmission,
      distributionEnd: (block.timestamp + 365 days)
    });

    rewardsController.configureAssetWithRewards(asset, targetLiquidity, rewards);
    vm.stopPrank();
  }
}
```

# Validation of the commit `62f3850` AAVE DAO Umbrella repository

Note: the following folders and files where considered out of scope of the review:
- `src/contracts/helpers/DataAggregationHelper.sol`
- `src/contracts/automation/*`
- `src/contracts/payloads/*`
- `src/contracts/stewards/*`

Below you can find the differences between the last commit [5b987d2](https://github.com/bgd-labs/aave-umbrella-private/commit/5b987d222355a1a8fa4b475e7f31968f66dd2394) reviewed and the requested commit to be reviewed [`62f3850`](https://github.com/aave-dao/aave-umbrella/tree/62f3850816b257087e92f41a7f37a698f00fa96e) on the final [AAVE DAO Umbrella Repo](https://github.com/aave-dao/aave-umbrella).

The review confirms that these are the only differences, in the in-scope contracts, that have been applied compared to the code already reviewed from the last Security Review reported.
```diff
--- bgd-labs/aave-umbrella-private/src/contracts/helpers/UmbrellaBatchHelper.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/helpers/UmbrellaBatchHelper.sol	2025-06-01 07:50:59
@@ -1,4 +1,4 @@
-// SPDX-License-Identifier: BUSL-1.1
+// SPDX-License-Identifier: MIT
 pragma solidity ^0.8.27;

 import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
--- bgd-labs/aave-umbrella-private/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol	2025-06-01 07:50:59
@@ -1,4 +1,4 @@
-// SPDX-License-Identifier: BUSL-1.1
+// SPDX-License-Identifier: MIT
 pragma solidity ^0.8.0;

 import {IRescuable} from 'solidity-utils/contracts/utils/interfaces/IRescuable.sol';
--- bgd-labs/aave-umbrella-private/src/contracts/helpers/interfaces/IUniversalToken.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/helpers/interfaces/IUniversalToken.sol	2025-06-01 07:50:59
@@ -1,4 +1,4 @@
-// SPDX-License-Identifier: BUSL-1.1
+// SPDX-License-Identifier: MIT
 pragma solidity ^0.8.0;

 import {IStataTokenV2} from 'aave-v3-origin/contracts/extensions/stata-token/interfaces/IStataTokenV2.sol';
--- bgd-labs/aave-umbrella-private/src/contracts/umbrella/UmbrellaStkManager.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/umbrella/UmbrellaStkManager.sol	2025-06-01 07:50:59
@@ -213,14 +213,23 @@
       stakeSetup.unstakeWindow
     );

-    // name and symbol inside creation data is considered as unique, so using different salts is excess
-    // if for some reason we want to create different tokens with the same name and symbol, then we can use different `cooldown` and `unstakeWindow`
-    address umbrellaStakeToken = TRANSPARENT_PROXY_FACTORY().createDeterministic(
+    address umbrellaStakeToken = TRANSPARENT_PROXY_FACTORY().predictCreateDeterministic(
       UMBRELLA_STAKE_TOKEN_IMPL(),
       SUPER_ADMIN(),
       creationData,
       ''
     );
+
+    if (umbrellaStakeToken.code.length == 0) {
+      // name and symbol inside creation data is considered as unique, so using different salts is excess
+      // if for some reason we want to create different tokens with the same name and symbol, then we can use different `cooldown` and `unstakeWindow`
+      TRANSPARENT_PROXY_FACTORY().createDeterministic(
+        UMBRELLA_STAKE_TOKEN_IMPL(),
+        SUPER_ADMIN(),
+        creationData,
+        ''
+      );
+    }

     _getUmbrellaStkManagerStorage().stakeTokens.add(umbrellaStakeToken);

--- bgd-labs/aave-umbrella-private/src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol	2025-06-01 07:51:21
@@ -145,7 +145,9 @@
    * @param reserve Address of the `reserve`
    * @return An array of `SlashingConfig` structs
    */
-  function getReserveSlashingConfigs(address reserve) external returns (SlashingConfig[] memory);
+  function getReserveSlashingConfigs(
+    address reserve
+  ) external view returns (SlashingConfig[] memory);

   /**
    * @notice Returns the slashing configuration for a given `UmbrellaStakeToken` in regards to a specific `reserve`.
@@ -157,7 +159,7 @@
   function getReserveSlashingConfig(
     address reserve,
     address umbrellaStake
-  ) external returns (SlashingConfig memory);
+  ) external view returns (SlashingConfig memory);

   /**
    * @notice Returns if a reserve is currently slashable or not.
@@ -175,14 +177,14 @@
    * @param reserve Address of the `reserve`
    * @return The amount of the `deficitOffset`
    */
-  function getDeficitOffset(address reserve) external returns (uint256);
+  function getDeficitOffset(address reserve) external view returns (uint256);

   /**
    * @notice Returns the amount of already slashed funds that have not yet been used for the deficit elimination.
    * @param reserve Address of the `reserve`
    * @return The amount of funds pending for deficit elimination
    */
-  function getPendingDeficit(address reserve) external returns (uint256);
+  function getPendingDeficit(address reserve) external view returns (uint256);

   /**
    * @notice Returns the `StakeTokenData` of the `umbrellaStake`.
--- bgd-labs/aave-umbrella-private/src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol	2025-06-01 07:51:08
+++ aave-dao/aave-umbrella/src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol	2025-06-01 07:51:21
@@ -49,7 +49,7 @@
   /////////////////////////////////////////////////////////////////////////////////////////

   /**
-   * @notice Creates new `UmbrlleaStakeToken`s.
+   * @notice Creates new `UmbrellaStakeToken`s.
    * @param stakeTokenSetups Array of `UmbrellaStakeToken`s setup configs
    * @return stakeTokens Array of new `UmbrellaStakeToken`s addresses
    */
@@ -146,7 +146,7 @@
   function UMBRELLA_STAKE_TOKEN_IMPL() external view returns (address);

   /**
-   * @notice Returns the `SUPER_ADMIN` address, which has `DEFAULT_ADMIN_ROLE` and is used to manage `UmbrellaStakeToken`s upgreadability.
+   * @notice Returns the `SUPER_ADMIN` address, which has `DEFAULT_ADMIN_ROLE` and is used to manage `UmbrellaStakeToken`s upgradability.
    * @return `SUPER_ADMIN` address
    */
   function SUPER_ADMIN() external view returns (address);
```
