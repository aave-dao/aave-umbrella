<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://raw.githubusercontent.com/aave-dao/aave-brand-kit/refs/heads/main/Logo/Logomark-purple.svg" width="250" height="250" style="padding: 4px;" /></td>
        <td>
            <h1>UmbrellaBatchHelper Report</h1>
            <p>Prepared for: Aave DAO</p>
            <p>Code produced by: BGD Labs</p>
            <p>Report prepared by: Emanuele Ricci (StErMi), Independent Security Researcher</p>
        </td>
    </tr>
</table>

# Introduction

A time-boxed security review of the **UmbrellaBatchHelper** protocol was done by **StErMi**, with a focus on the security aspects of the application's smart contracts implementation.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise bound effort where I try to find as many vulnerabilities as possible. I can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **UmbrellaBatchHelper**

`UmbrellaBatchHelper` is a smart contract designed to optimize user interactions with the `Umbrella` system and its periphery, consolidating multiple transactions into a single one, via signatures.

Previous review commit:
- Link: https://github.com/bgd-labs/aave-umbrella-private/tree/main/src/contracts/helpers
- Last commit: `e3dced60030a0b3d9fd469a333d25517c718edad`

Latest review commit:
- Link: https://github.com/aave-dao/aave-umbrella/tree/main/src/contracts/umbrella
- Last commit: `62f3850816b257087e92f41a7f37a698f00fa96e`

# About **StErMi**

**StErMi**, is an independent smart contract security researcher. He serves as a Lead Security Researcher at Spearbit and has identified multiple bugs in the wild on Immunefi and on protocol's bounty programs like the Aave Bug Bounty.

Do you want to connect with him?
- [stermi.xyz website](https://stermi.xyz/)
- [@StErMi on Twitter](https://twitter.com/StErMi)

# Summary & Scope

**_review commit hash_ - [441b519a51787b59e0f6f137ecb90c8fffc8a07b](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b)**
**_POST REVIEW_ - [PR 124](https://github.com/bgd-labs/aave-umbrella-private/pull/124)**

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
| ID                 | Title                                                                                                                     | Severity | Status          |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- | -------- | --------------- |
| [L-01]             | `cooldownPermit` is not validating the `stakeToken`                                                                       | Low      | Fixed           |
| [L-02]             | User could end up earning less reward than deserved or losing all of them when transfer and deposit `StataTokenV2` tokens | Low      | Ack             |
| [I-01]             | General informational issues                                                                                              | Info     | Partially Fixed |
| [I-02]             | `claimRewardsPermit` should also skip the iteration when the actual reward balance is zero                                | Info     | Fixed           |
| [I-03]             | `_checkAndInitializePath` should revert when the `stakeToken` is paused                                                   | Info     | Ack             |
| [POST REVIEW I-01] | `_checkAndInitializePath` should further validate the `data` returned by the `staticcall`                                 | Info     | Ack             |

# [L-01] `cooldownPermit` is not validating the `stakeToken`

## Context

- [UmbrellaBatchHelper.sol#L89](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L89)

## Description

Every external function exposed by the `UmbrellaBatchHelper` contract is **always** executing `_checkAndInitializePath` as the very first instruction. This not only configures the needed information to later on interact with the `stakeToken` via the `UmbrellaBatchHelper` but it also performs some required sanity check on the `stakeToken` itself.

The `cooldownPermit` function is the only function that does not perform this check, calling directly the `cooldownWithPermit` function on the `StakeToken`.

## Recommendations

While it's true that the `p.stakeToken.cooldownWithPermit` call made inside `cooldownPermit` should not transfer any tokens, it's still recommended to execute ` _checkAndInitializePath(p.stakeToken);` to ensure that `stakeToken` is indeed a valid `StakeToken` configured and whitelisted in the AAVE ecosystem.

**StErMi:** The recommendations have been implemented in the [PR 125](https://github.com/bgd-labs/aave-umbrella-private/pull/125)

# [L-02] User could end up earning less reward than deserved or losing all of them when transfer and deposit `StataTokenV2` tokens
## Context

- [ERC20AaveLMUpgradeable.sol#L159-L177](https://github.com/bgd-labs/aave-v3-origin/blob/aa774ee3d10c9353e837df06e67a56ad47e7b0f2/src/contracts/extensions/stata-token/ERC20AaveLMUpgradeable.sol#L159-L177)
- [UmbrellaBatchHelper.sol#L185](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L185)

## Description

**👉 Note:** this issue has been already reported during the `StakeToken` review

**🚨 Impact:** when the user transfers their `StataTokenV2` during a `deposit` operation and the `$._rewardTokens` on the `StataTokenV2` has not been refreshed with the new reward, the user could end up accruing less rewards or losing all of them.

The mechanism of tracking rewards for the `AToken` and `stataToken` (wrapped version of the `aToken`) works quite differently between those two contracts.

When a user `mint/burn/transfer` `AToken` or `VariableDebtToken` the contract will call `rewardController.handleAction(caller, supplyBeforeAction, callerBalanceBeforeAction)` and the `RewardController` will calculate the accrued rewards for **every** reward enabled for the `aToken` inside the `RewardController`. At any point, the user will be able to claim those rewards directly on the `RewardController` because those rewards are associated **directly** to their address.

When the user wraps their `aToken` in `stataToken` the reward mechanism is quite different. Now the holder of the `aToken` is the `StataTokenV2` contract itself and the users receive `stataToken` shares which, by default, do not have any reward distribution associated directly to it. The one that is "directly" accruing rewards for holding the `aToken` is the `stataToken` contract itself that will calculate, claim and distribute them "indirectly" internally to the `stataToken` holders.

When the user performs a `mint/burn/transfer` (associated to `wrap`, `unwrap` and `transfer/transferFrom` operations) of `stataToken` the system will indeed update and track the user's accrued rewards but will use a "cached" list of rewards to iterate on:

```solidity
  function _update(address from, address to, uint256 amount) internal virtual override {
    ERC20AaveLMStorage storage $ = _getERC20AaveLMStorage();
    for (uint256 i = 0; i < $._rewardTokens.length; i++) {
      address rewardToken = address($._rewardTokens[i]);
      uint256 rewardsIndex = getCurrentRewardsIndex(rewardToken);

      if (from != address(0)) {
        _updateUser(from, rewardsIndex, rewardToken);
      }

      if (to != address(0) && from != to) {
        _updateUser(to, rewardsIndex, rewardToken);
      }
    }
    super._update(from, to, amount);
  }
```

The `$._rewardTokens` list is updated only by the `__ERC20AaveLM_init_unchained` function (called during initialization) or when the public `refreshRewardTokens` function is called.

Let's assume that `alice` owns at `T0` some `stataTokenUSDC` and at `T1` time `DAI` is added to the `aUSDC` asset as a reward inside the `RewardController`.

The `refreshRewardTokens()` function is never called, and `DAI` is not included in the `$._rewardTokens` list.
At the time `T2` `alice` unwraps (burn) or transfers her `stataTokenUSDC` but the `StataTokenV2` will not record the amount of accrued rewards owed to `alice` and she will **never** be able to claim them, losing them forever.

## Recommendations

BGD should ensure that once a new `reward` distribution has been configured for the `aToken` associated to the `stataToken`, the `StataTokenV2.refreshRewardTokens()` function is immediately called by an automated system.

BDG should also consider enforcing the execution of the `StataTokenV2.refreshRewardTokens()` function when `stataToken` are `minted/burned/transferred`.

**BGD:** This is from the docs:

> The stataToken is not natively integrated into the aave protocol and therefore cannot hook into the emissionManager. This means a reward added after statToken creation needs to be registered manually on the token via the permissionless refreshRewardTokens() method. **As this process is not currently automated users might be missing out on rewards until the method is called.**

While the docs are a bit outdated and there is now a bot doing it, it clearly states the behavior you describe here.

# [I-01] General informational issues
## Description

### Natspec typos, errors or improvements

- [ ] [README.md](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/README.md): consider replacing the term "Route" with something more appropriate. Usually, the term Route implies that the user has a choice, but in this case, there's no choice for the user. If the `StakeToken` has an `ERC20` as the underlying, these's only one possible path.
- [x] [UmbrellaBatchHelper.sol#L87](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L87): the dev comment is incorrect, the `StakeToken.cooldownWithPermit` does not directly use `msg.sender` but `_msgSender()`
- [x] [IUmbrellaBatchHelper.sol#L34](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L34): the `@dev` comment in the `ClaimPermit` struct for the `restake` attribute should be corrected: "the actual one" → "the `msg.sender`". The suggested form is more precise, without any possible confusion.
- [x] [IUmbrellaBatchHelper.sol#L41](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L41): move the `@dev` comment relative to the `DAI` special scenario for the `Permit.value` attribute to the root of the `Permit` struct. The `DAI` token uses a custom permit signature that is incompatible with the [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) standard.
- [x] [IUmbrellaBatchHelper.sol#L56-L57](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L56-L57): consider further improving the documentation for the `IOData.value` attribute in the context of a `redeem` operation. Such attribute represents the amount of `StakeToken` shares that will be burned and not the amount of token to be received when the `redeem` operation is performed.
- [x] [IUmbrellaBatchHelper.sol#L116-L117](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L116-L117): rewrite the `function permit` natspec `@dev` comment. It's currently using the `transit` function name, which does not exist anymore in the `IUmbrellaBatchHelper` or `UmbrellaBatchHelper` context.
- [x] [IUmbrellaBatchHelper.sol#L128](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L128): the "withdrawing funds" part of the natspec documentation in the `deposit` function is unclear and could be better explained (or fully removed)

### Renaming and refactoring

- [x] [UmbrellaBatchHelper.sol#L168](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L168): consider replacing `io.value` with `value` when `if (io.value > balanceInCurrentBlock)` is executed inside the `deposit` function to be coherent with the function's logic that has already initialized the value of the `value` variable with `io.value` outside the branch.
- [ ] [IUmbrellaBatchHelper.sol#L64](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L64): consider enhancing the `AssetPathInitialized` event with additional inputs to be logged to map the result of the `_checkAndInitializePath` operation
- [x] [IUmbrellaBatchHelper.sol#L64](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/interfaces/IUmbrellaBatchHelper.sol#L64): consider declaring as `indexed` the `stakeToken` input of the `AssetPathInitialized` event
- [ ] [UmbrellaBatchHelper.sol#L312-L343](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L312-L343): consider adding some dev comments relative to the `aToken()` and `asset()` values of a `StataToken` in the context of the `_checkAndInitializePath` function. The `aToken()` returns the `A/V` AAVE Token, while `asset()` returns the `AToken` underlying and not the `AToken` itself.

### Code improvement

- [x] [UmbrellaBatchHelper.sol](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol): This contract is adopting both the revert pattern `if( somethingWrong ) revert XYZ()` and `require(toBeTrue, XYZ())`. Replace all the instances of `if -> revert` with the easier and understand `require` statements.
- [ ] [UmbrellaBatchHelper.sol](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol): Consider emitting specific events when the contract external functions like `cooldownPermit`, `claimRewardsPermit`, etc., are executed. This could later on help the team to monitor the contract usage and adoption.
- [ ] [UmbrellaBatchHelper.sol#L67](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L67): The `_configs` variable is `internal` and there are not `view` methods that expose the supported `StakeToken`, the configuration of the existing one and the possible `Path`'s supported by a `StakeToken`. Consider implementing and exposing `external view` functions that allow users, integrators and dApps to fetch data relative to the `stakeToken` configuration before interacting with the `UmbrellaBatchHelper` contract
- [x] [UmbrellaBatchHelper.sol#L72](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L72): consider renaming the constructor input parameters to use the `_` affix or suffix and avoid clashing with the name of internal state variables or functions like the `onwer()` getter exposed by the `Ownable` OZ contract
- [x] [UmbrellaBatchHelper.sol#L72](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L73): the `owner != address(0)` check performed in the `UmbrellaBatchHelper` constructor could be avoided, given that such check is already performed by the `Ownable` constructor
- [ ] [UmbrellaBatchHelper.sol#L192](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L192): consider enhancing the `redeem` function to return the amount of `edgeToken` transferred to the user after the redeem process.
- [ ] [UmbrellaBatchHelper.sol#L233-L245](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L233-L245): consider inlining the `_claimRewardsPermit` function's code directly into `claimRewardsPermit` function, given that the internal function is only called there.
- [ ] [UmbrellaBatchHelper.sol#L285-L305](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L285-L305): consider inlining the `_redeemFromStake` function's code directly into `redeem` function, given that the internal function is only called there.
- [ ] [UmbrellaBatchHelper.sol#L97](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L97): consider enhanching the `claimRewardsPermit` function to return the total amount (or the single one, depending on the context) of `StakeToken` restaked as the result of the operation when `restake == true`

## Recommendations

BGD should fix all the suggestions listed in the above section

**BGD:** N2-7, R1, R3, C1, C4, C5 fixed. Fixes should be here: [PR 127](https://github.com/bgd-labs/aave-umbrella-private/pull/127). Acknowledged others.

**StErMi:** confirmed.

# [I-02] `claimRewardsPermit` should also skip the iteration when the actual reward balance is zero
## Context

- [UmbrellaBatchHelper.sol#L119](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L119)

## Description

The current logic of `claimRewardsPermit` is already skipping the restake iteration if the amount of reward is equal to zero

```solidity
if (amounts[i] == 0) {
	continue;
}
```

but is not skipping the iteration if the **actual** number of rewards received is equal to zero. The actual amount is calculated later on by fetching the actual balance of rewards that has been transferred to the `UmbrellaBatchHelper` contract, and that could be lower compared to `amounts[i]` because of possible wei loss during the transfer.

## Recommendations

BGD should consider skipping the iteration if `actualAmountReceived == 0`. This precaution could avoid possible unexpected behaviours (possible reverts) or the emission of useless events when the amount of minted token on the `StakeToken` is equal to zero (ERC4626 **does not revert**  when the deposit amount is equal to zero).

**StErMi:** The recommendations have been implemented in the [PR 126](https://github.com/bgd-labs/aave-umbrella-private/pull/126)

# [I-03] `_checkAndInitializePath` should revert when the `stakeToken` is paused
## Context

- [UmbrellaBatchHelper.sol#L312](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/helpers/UmbrellaBatchHelper.sol#L312)
- [StakeToken.sol#L122-L125](https://github.com/bgd-labs/aave-umbrella-private/blob/441b519a51787b59e0f6f137ecb90c8fffc8a07b/src/contracts/stakeToken/StakeToken.sol#L122-L125)

## Description

The `_checkAndInitializePath` implementation is not validating the `pause` state of the `stakeToken` contract that is being "whitelisted" in the `UmbrellaBatchHelper` configs.

## Recommendations

BGD should consider reverting the transaction that has executed `_checkAndInitializePath` if the `StakeToken` contract is paused.

**BGD:** We do not want to add this check to the path initialization process because we do not expect tokens to be paused in the future for any reason. This functionality is introduced only as a last resort for the most difficult situations.

# [POST REVIEW I-01] `_checkAndInitializePath` should further validate the `data` returned by the `staticcall`

## Context

- [UmbrellaBatchHelper.sol#L327-L332](https://github.com/bgd-labs/aave-umbrella-private/pull/124/files#diff-7f292e517bdbdf1d2087637402a2b91544e1c80ad4743272e992ae12be82c748R327-R332)

## Description

The new implementation of `_checkAndInitializePath` (see [PR 124 "Fixed issue with try-catch"](https://github.com/bgd-labs/aave-umbrella-private/pull/124)) has switched from try-catching the call to `IUniversalToken(underlyingOfStakeToken).aToken()` to manually handling the result of `address(underlyingOfStakeToken).staticcall(abi.encodeWithSelector(IERC4626StataToken.aToken.selector))`.

The `bytes memory data` returned by the `staticcall`, when `success == true` is currently blindly trusted and not further validated.
There are scenarios where the `abi.decode` call will **not** revert even if `data` contains more than just the `address` value or the value has been tainted by other encoded data encoded via `abi.encodePacked`.

Below are some examples of the possible scenarios:

```solidity
  function testMoreToDecode() public {
    address tokenAddress = address(1);
    uint256 moreData = 123;
    bytes memory data = abi.encode(tokenAddress, moreData);
    (address aToken) = abi.decode(data, (address));

    assertEq(data.length, 64);
    assertEq(aToken, tokenAddress);
  }

    function testMoreToDecode2() public {
    address tokenAddress = address(1);
    uint256 moreData = 123;
    bytes memory data = abi.encodePacked(tokenAddress, moreData);
    (address aToken) = abi.decode(data, (address));

    assertEq(data.length, 52);
    assertTrue(aToken != tokenAddress);
  }
```

## Recommendations

BGD should further validate the `data` returned by the `staticcall` execution, ensuring, at least, that the `length` is equal to `32`

**BGD:** We do not plan to use stata tokens other than `StataTokenV2` version as `StakeToken` underlying in the near future.

Acknowledged.

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
