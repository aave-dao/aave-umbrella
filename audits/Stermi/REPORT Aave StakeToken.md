<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://raw.githubusercontent.com/aave-dao/aave-brand-kit/refs/heads/main/Logo/Logomark-purple.svg" width="250" height="250" style="padding: 4px;" /></td>
        <td>
            <h1>StakeToken</h1>
            <p>Prepared for: Aave DAO</p>
            <p>Code produced by: BGD Labs</p>
            <p>Report prepared by: Emanuele Ricci (StErMi), Independent Security Researcher</p>
        </td>
    </tr>
</table>

# Introduction

A time-boxed security review of the **StakeToken** protocol was done by **StErMi**, with a focus on the security aspects of the application's smart contracts implementation.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise bound effort where I try to find as many vulnerabilities as possible. I can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **StakeToken**

The `StakeToken` is a new version of the Aave Safety Module stk tokens, to be used on `Umbrella`.

Previous review commit:
- Link: https://github.com/bgd-labs/aave-umbrella-private/tree/main/src/contracts/stakeToken
- Last commit: b06e3fda7f958d499dde9aabb14bad01d873935d

Latest review commit:
- Link: https://github.com/aave-dao/aave-umbrella/tree/main/src/contracts/umbrella
- Last commit: `62f3850816b257087e92f41a7f37a698f00fa96e`

# About **StErMi**

**StErMi**, is an independent smart contract security researcher. He serves as a Lead Security Researcher at Spearbit and has identified multiple bugs in the wild on Immunefi and on protocol's bounty programs like the Aave Bug Bounty.

Do you want to connect with him?
- [stermi.xyz website](https://stermi.xyz/)
- [@StErMi on Twitter](https://twitter.com/StErMi)

# Summary & Scope

**_review commit hash_ - [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/tree/dfa6a5449ac4680afd26f814bef945564fea402a)**
**_fix-review commit hash_ - [e0cbabc9df79b793afb81112ad9112079a996b0f](https://github.com/bgd-labs/aave-umbrella-private/commit/e0cbabc9df79b793afb81112ad9112079a996b0f)**

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
| ID                | Title                                                                                                                                                | Severity | Status          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------- |
| [L-01]            | `StakeToken` vault is not compliant with the `ERC4626` standard                                                                                      | Low      | Fixed           |
| [L-02]            | Missing sanity checks                                                                                                                                | Low      | Partially Fixed |
| [L-03]            | Consider adding a safe lower bound to the `_unstakeWindow` configuration parameter                                                                   | Low      | Ack             |
| [L-04]            | `StakeToken` could lose `StataTokenV2` accruable rewards if `$._rewardTokens` is not updated                                                         | Low      | Ack             |
| [I-01]            | General informational issues                                                                                                                         | Info     | Partially Fixed |
| [I-02]            | The `StakerCooldownUpdated` event is not tracking the caller, which could be different from the owner of the shares                                  | Info     | Ack             |
| [I-03]            | `getMaxSlashableAssets` should return `0` when the Vault is paused                                                                                   | Info     | Fixed           |
| [I-04]            | Considerations on the consequences on the user's operation after the exchange rate change because of a slash event                                   | Info     | Partially Fixed |
| [I-05]            | The `StakeToken` should better explain and document how the user will be compensated for the loss of rewards from not holding `StataTokenV2` anymore | Info     | Ack             |
| [I-06]            | Considerations on additional information to be tracked by the existing events and early return for unchanged values                                  | Info     | Partially Fixed |
| [FIX REVIEW I-01] | `StakeToken` `permit` and `cooldownPermit` using the same nonce could create nonces overlap issues                                                   | Info     | Fixed           |
| [FIX REVIEW I-02] | `cooldownWithPermit` should be removed or made not permissionless                                                                                    | Info     | Fixed           |

# [L-01] `StakeToken` vault is not compliant with the `ERC4626` standard
## Context

- [ERC4626StakeTokenUpgradeable.sol#L111-L134](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L111-L134)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

The `IERC4626` interface documents the requirements of the `ERC4626` standard. Following the natspec documentation of the functions `maxDeposit`, `maxMint`, `maxRedeem` and `maxWithdraw` we know that those function **MUST** return a value that could be limited by the restriction applied to the user depending on the action executed.

When the `StakeToken` vault is paused, **any** action performed by the user will revert because of the execution of the `whenNotPaused` modifier

```solidity
  function _update(
    address from,
    address to,
    uint256 value
  ) internal override(ERC20Upgradeable, ERC4626StakeTokenUpgradeable) whenNotPaused {
    super._update(from, to, value);
  }
```

But the current implementation of `maxRedeem` and `maxWithdraw` are not checking the `_paused` flag and the `maxDeposit` and `maxMint` function are not overridden, meaning that they will always return `type(uint256).max`

## Recommendations

To be compliant with the `ERC4626` standard, BGS should

- Update the current implementation of `maxRedeem` and `maxWithdraw`, returning `0` if the vault is paused
- Implement and override the `maxDeposit` and `maxMint` functions returning `0` if the vault is paused

**StErMi:** The recommendations have been implemented in the fix-review snapshot [e0b9f86bf77ac719dc13d5936f0ef866bab03661](https://github.com/bgd-labs/aave-umbrella-private/commit/e0b9f86bf77ac719dc13d5936f0ef866bab03661).

Now `maxRedeem`, `maxWithdraw`, `maxDeposit` and `maxMint` returns `0` if the contract is paused.

# [L-02] Missing sanity checks
## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

1) [x] [ERC4626StakeTokenUpgradeable.sol#L63](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L63): revert if `rewardsController` is equal to `address(0)`. One of the main purposes of the contract is to reward stakers with a reward, many of the core logics will revert if the reward controller is not configured.
2) [ ] [ERC4626StakeTokenUpgradeable.sol#L71](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L71): consider reverting the contract initialization logic if the `REWARDS_CONTROLLER` is not configured yet to have at least a configured and active reward distribution. From the staker POV, the only reason to stake tokens is to receive rewards. When the user stakes their `stataToken`, they will stop accruing rewards (on that side) and it's fair to require that at least a distribution for the `stakedToken` should be already configured and active.
3) [x] [ERC4626StakeTokenUpgradeable.sol#L286](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L286): revert the `_slash` logic if `destination` is equal to `address(0)`. The ERC20 `asset()` could be using a non-standard OZ implementation that does not sanity-check the `receiver` of the token.
4) [ ] [RescuableBase.sol#L14-L31](https://github.com/bgd-labs/solidity-utils/blob/a842c36308e76b8202a46962a6c2d59daceb640a/src/contracts/utils/RescuableBase.sol#L14-L31): consider updating also both the `_emergencyTokenTransfer` and `_emergencyEtherTransfer` to sanity check the `amount` and `to` parameters. Those functions should revert or at least early return if `to == address(0)` or `amount == 0`

## Recommendations

BGD should consider following and implementing the suggestions listed above

**BGD:**

1, 3 agree will be fixed.
2 - At the moment it is unclear what such a check should look like, so acknowledged.
4 - acknowledged, cause as I understand only DAO or strong multisig like 5-9 should be able to call these functions, no eoa. So calldata should be check by at least 5 people/orgs before action.

**StErMi:** The first and third recommendations have been implemented in the fix-review snapshots [5728ddf9d4d1269ad0243edadec9e100acbd487a](https://github.com/bgd-labs/aave-umbrella-private/commit/5728ddf9d4d1269ad0243edadec9e100acbd487a) + [f8583e8199a669c07ee651498841aa9aac5d6e17](https://github.com/bgd-labs/aave-umbrella-private/commit/f8583e8199a669c07ee651498841aa9aac5d6e17).

- `ERC4626StakeTokenUpgradeable.constructor` reverts if `rewardsController` is equal to `address(0)`
- `ERC4626StakeTokenUpgradeable._slash` function reverts if `destination` is equal to `address(0)`

# [L-03] Consider adding a safe lower bound to the `_unstakeWindow` configuration parameter
## Context

- [ERC4626StakeTokenUpgradeable.sol#L294](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L294)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

The `_unstakeWindow` configuration parameter represents the window of seconds, after the cooldown deadline has been reached, for which the `owner` (or the `spender` with allowance) of the tokens can execute a `withdraw` or `redeem` action.

Once the window has ended, the `owner` won't be able to `withdraw` or `redeem` anymore from the snapshot taken and needs to recreate a new one.

Given that the `_cooldown` configuration parameter could be high and given that both the `_cooldown` and `_unstakeWindow` values are used only when the snapshot is taken (changes to their value do not influence existing snapshots) it would be beneficial to have a safe lower bound applied when `_unstakeWindow` is configured.

For example, having a snapshot created with `_cooldown > 0` and `_unstakeWindow == 0` means that the `owner` will be required to execute the `withdraw` or `redeem` request at the **specific timestamp** that the cooldown ends; otherwise the snapshot will be considered outside the unstake window.

## Recommendations

BGD should consider adding a lower bound sanity check to the `newUnstakeWindow` input parameter when the internal function `_setUnstakeWindow` is executed.

**BGD:** There is some confusion that we haven't added to the documentation yet, but the `setCooldown` function and `setUnstakeWindow` should only be called by DAO. Owner of `stakeToken` must be a contract, which will contain an ACL mechanism under the hood.

We did not add such checks, since the role responsible for assigning these parameters is the most responsible and should not set strange parameters without compromising the voting process.

# [L-04] `StakeToken` could lose `StataTokenV2` accruable rewards if `$._rewardTokens` is not updated

## Context

- `slash`: [ERC4626StakeTokenUpgradeable.sol#L286](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L286)
- `redeem`/`withdraw` (unstake): [ERC4626StakeTokenUpgradeable.sol#L180](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L180)
- `emergencyTokenTransfer`: [RescuableBase.sol#L21](https://github.com/bgd-labs/solidity-utils/blob/a842c36308e76b8202a46962a6c2d59daceb640a/src/contracts/utils/RescuableBase.sol#L21)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

The "Considerations on the consequences on the user's operation after the exchange rate change because of a slash event" finding describe a low-likelihood issue that could miss the `reward` accrual of a EOA/contract if the `StataTokenV2`  are transferred or unwrapped when the `reward` have not been added to the `$._rewardTokens` reward list. When this happens, the EOA/Contract won't be able to claim the lost accrual.

A `StataTokenV2` token can be the underlying `asset` of a `StakeToken` vault and as explained by the discussion "RESEARCH: Token flows and Reward accrual mechanism", when users stake their token into the vault, the vault itself starts accruing the rewards assigned to the `StataTokenV2` asset in the `RewardController` distributions.

Given the above cited issue, it's possible that the `StakeToken` contract could lose part of the deserved accrued rewards (the one not added to the `$._rewardTokens` reward list) when the `StataTokenV2` underlying tokens leave the contact during the execution of these flows:
- users that unstake their assets via a `withdraw` or `redeem` operation
- the vault's owner that slashes part of the underlying `StataTokenV2` tokens in `slash` operation
- the vault's owner that rescue the rescuable amount of `StataTokenV2` tokens in a `Rescuable.emergencyTokenTransfer` operation

## Recommendations

BDG should consider one of the following actions:
- document the issue in the codebase and create an automation that refreshes the `StataTokenV2` `$._rewardTokens` list as soon as a new reward is configured for the `StataTokenV2` underlying `asset` in the `RewardController`
- enforce the update of the `$._rewardTokens` reward list by calling the `StataTokenV2.refreshRewardTokens()` function during all the flows listed in the "Description" section

**StErMi:** BGD has acknowledged the issue

**BGD:** By design, we didn't want to include refreshing of rewards on all flows, given that the addition of new reward tokens is pretty rare compared with the frequency of those flows.
So our decision is assuming refresh of reward tokens will be done in a relatively short time after a new reward token is added, and we have configured automation of the Aave DAO for it (Aave Robot infrastructure). For example, in the current production version of StataToken (v1), we have said automation, triggering in the range of 1-5 blocks after a new reward is enabled, depending on the network.

# [I-01] General informational issues
## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

### Natspec typos, errors or improvements

- [x] [README.md#L13](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/README.md?plain=1#L13): "slashing can happen up to the `getMaxSlashableAssets()` configuration" seems to imply that the upper bound limit can be configured, but in reality `MIN_ASSETS_REMAINING` is declared as a `constant`. Update the README to be less confusing and be coherent with the code.
- [x] [README.md#L38](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/README.md?plain=1#L38): the `rescueAssets` does not exist, replace it with the `emergencyTokenTransfer` function name from the `Rescuable` contract inherited by `StakeToken`
- [x] [README.md#L49](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/README.md?plain=1#L49): "The amount of `shares` available for withdrawal" could be rephrased to be more clear. Given the slash mechanism, it seems like it would influence the amount of shares the user can request to withdraw during cooldown. Instead, the `cooldown()` execution will always snapshot the current user share balance, which is unaffected by the slash mechanism.
- [x] [README.md#L51](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/README.md?plain=1#L51): replace the name `assets` with `shares`. The `amount` stored in the user's snapshot is about `shares` and not the `assets` (`underlying`)
- [x] [README.md#L51-L55](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/README.md?plain=1#L51-L55): consider being more specific using `shares` instead of `funds` and use the action `redeem` instead of `withdraw`. The snapshot amount is about `shares` that will be then `redeemed` and not withdrawn.
- [x] [ERC4626StakeTokenUpgradeable.sol#L111-L112](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L111-L112): consider enhancing the current natspec documentation explaining that the max withdrawable amount is limited by the current cooldown snapshot status
- [x] [ERC4626StakeTokenUpgradeable.sol#L118-L119](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L118-L119): consider enhancing the current natspec documentation explaining that the max redeemable amount is limited by the current cooldown snapshot status
- [x] The `StakeToken` contract will accept not only `StataTokenV2` as the underlying `asset` but any `ERC20` compatible token. As we know, not all the `ERC20` tokens respect the `ERC20` standard in full and some of them could have behaviors that are incompatible with the current `StakeToken` logic (fee on transfer, for example). BGD must extend the current documentation explicitly static which type of `ERC20` token will be supported and accepted as the underlying `asset` of a `StakeToken` vault.
- [x] [StakeToken.sol#L126-L134](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/StakeToken.sol#L126-L134) Nitpick: consider adding a natspec documentation for the `maxRescue` function that explicitly states that tokens should be rescuable even if the `StakeToken` contract has been paused.
- [x] Consider better documenting the relationship between cooldown and spender's allowance. The `$._allowances[owner][spender]` value (of the `ERC20` token) is used to both allow the spender to trigger a new and override an existing `cooldown` snapshot, or to transfer/withdraw tokens. The `snapshot` of a user is **not** bound to a `spender`, meaning that `spender_1` could create a cooldown, wait for the cooldown to reach maturity, but then a `spender_2` could "consume" the whole snapshot's amount and "steal" the opportunity of unstaking.
- [x] [IERC4626StakeToken.sol#L7-L14](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/interfaces/IERC4626StakeToken.sol#L7-L14): consider rewriting the natspec documentation of the `CooldownSnapshot` struct. Specify that the `amount` is redeemable only after the `endOfCooldown` timestamp within `withdrawalWindow` seconds. Specify that `endOfCooldown` is a timestamp and that `withdrawalWindow` is a number of seconds. Currently, they are both defined as "Time" but they represent different units.
- [x] [IERC4626StakeToken.sol#L22-L32](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/interfaces/IERC4626StakeToken.sol#L22-L32): add natspec documentation to every `Event` defined in the `IERC4626StakeToken` interface.
- [x] [IERC4626StakeToken.sol](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/interfaces/IERC4626StakeToken.sol): there are multiple instances of the following issues:
	- Use the `@notice` term instead of `@dev` when you explain the function's behavior and meaning
	- If the function returns values, document them with a `@return` statement
	- If the function has input parameters, document them with a `@param` statement

### Renaming

- [ ] [ERC4626StakeTokenUpgradeable.sol#L45](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L45): consider renaming the `ERC4626StakeTokenStorageLocation` variable in **uppercase**, given that it's a `constant`. See the [Solidity Style Guide for Constants](https://docs.soliditylang.org/en/latest/style-guide.html#constants) documentation.
- [ ] [ERC4626StakeTokenUpgradeable.sol#L36-L37](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L36-L37) + [ERC4626StakeTokenUpgradeable.sol#L147-L150](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L147-L150): consider renaming both the struct's attribute name and the getter/setter function to something like `cooldownDuration`, `getCooldownDuration` and `setCooldownDuration`. The current names create confusion with the existence of the `cooldown()` function that is the action name performed by the user.
- [ ] [ERC4626StakeTokenUpgradeable.sol#L84-L87](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L84-L87): consider renaming the `cooldown()` function to something more meaningful and clear (similar to LIDO) like `startWithdrawRequest` or `requestWithdrawal`
- [ ] [ERC4626StakeTokenUpgradeable.sol#L157-L160](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L157-L160): consider renaming `getStakerCooldown` to `getStakerCooldownSnapshot` to be clear and differentiate by the `cooldown` struct attribute that is a **duration**.

## Recommendations

BGD should fix all the suggestions listed in the above section

**StErMi:** Some of the recommendations have been implemented in the fix-review snapshot [e2449ca573168f365f3b2e51d548768ee4a02401](https://github.com/bgd-labs/aave-umbrella-private/commit/e2449ca573168f365f3b2e51d548768ee4a02401). Another part of the recommendations and fixes have been implemented in the [PR 73](https://github.com/bgd-labs/aave-umbrella-private/pull/73).

The "renaming" part of the suggestions won't be implemented.

The `spender` allowance of the `ERC20` contract is not used anymore in the `cooldown` logic and has been replaced by a separate logic that uses a new state variable.

# [I-02] The `StakerCooldownUpdated` event is not tracking the caller, which could be different from the owner of the shares
## Context

- [ERC4626StakeTokenUpgradeable.sol#L202-L207](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L202-L207)
- [ERC4626StakeTokenUpgradeable.sol#L254-L259](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L254-L259)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

The cooldown snapshot can be created by both the owner of the `StakeToken` tokens or by a "spender" that has been enabled by the owner. Both the `cooldown()` and `cooldownOnBehalfOf(address owner)` will call the private function `_cooldown(owner)` that will create or override the cooldown snapshot for `owner`.

Internally, the function will emit the `StakerCooldownUpdated` that is not tracking the caller of the `_cooldown` execution that could be different from the owner of the shares.

Given that the owner of the tokens could enable multiple spenders and given that each spender could override the owner snapshot, it would be a good idea to keep track of the caller to allow the owner to monitor the situation.

The same logic should be applied for the emission of the `StakerCooldownUpdated` where the `_update` function could be triggered by a `transferFrom`. In this case, it's even more interesting to track the caller that could be a `spender` different from the spender (or the owner) that has originally generated the snapshot.

## Recommendations

BGD should consider tracking inside the `StakerCooldownUpdated` event the `_msgSender()` that has triggered the execution of the `_cooldown(...)` or `_update` function.

**BGD:** We have reworked the mechanics related to `cooldownOnBehalf`. Initially, it was useful to include this information, but during the process, @kyzia551 insisted that we remove `msg.sender` from this event.

The reason for this is that the signature we issue for `cooldownOnBehalfPermit` does not check `msg.sender` inside. Since this is a meta-function, analyzing who can call it provides little relevant information.

So, for today the status is acknowledged.

# [I-03] `getMaxSlashableAssets` should return `0` when the Vault is paused
## Context

- [StakeToken.sol#L147](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/StakeToken.sol#L147)
- [ERC4626StakeTokenUpgradeable.sol#L141-L145](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L141-L145)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

Even if the `slash` function can be called only by the Vault's owner, the execution will anyway revert if the Vault has been paused.
The `getMaxSlashableAssets` function implemented in the `ERC4626StakeTokenUpgradeable` contract should return the "maximum slashable assets available for now" (see `IERC4626StakeToken` natspec) but the current code does not consider the `_paused` status flag of the Vault

```solidity
  function getMaxSlashableAssets() public view returns (uint256) {
    uint256 currentAssets = totalAssets();
    return currentAssets <= MIN_ASSETS_REMAINING ? 0 : currentAssets - MIN_ASSETS_REMAINING;
  }
```

## Recommendations

Even if this is not a security issue, given that the execution of `slash` reverts anyway if the vault is paused, the getter of the max slashable amount of asset should consider the paused state flag to be coherent.

BGD should consider to early return zero if `paused()` is `true`

**StErMi:** The recommendations have been implemented in the fix-review snapshot [13eff9a6104be654a2c77a5f604295d7f5034bdd](https://github.com/bgd-labs/aave-umbrella-private/commit/13eff9a6104be654a2c77a5f604295d7f5034bdd).

Now, the `_getMaxSlashableAssets` function used by `getMaxSlashableAssets` and `_slash` returns `0` if the contract is paused.

# [I-04] Considerations on the consequences on the user's operation after the exchange rate change because of a slash event

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

The `StakeToken` contracts is a `ERC4626` vault with a cooldown (delay) mechanism on the `redeem`/`withdraw` functionalities.
The `owner` of the contract, in case of need, could execute a `slash` operation that will reduce the amount of `underlying` assets deposited by the users up to `maxSlashableAmount`.

When a `slash` operation, that as we said, will **decrease** the `_getERC4626StakeTokenStorage()._totalAssets` value, the exchange rate of the vault will automatically change and won't be `1:1` anymore.

The change in exchange rate could influence the outcome of the core `ERC4626` operations that are not protected by slippage mechanism or rounding errors.
#### `deposit`

In this case, we have no problem, the number of shares received **after** the slash will be higher (assets are more valuable) compared to the amount received **before** the slash.

See the `testDepositSlash` test case.
#### `mint`

Because of the rounding error after the `slash`, the user could end up transferring the same amount of asset and receive fewer shares than deserved if he does not calculate correctly the number of shares that he wants to receive.
In this case, the user (or BGD) should calculate the max number of shares that the user can mint by providing `X amount` of asset to be deposited and avoid as much as possible rounding error.

See the `testMintSlash` test case.

#### `withdraw`

After the `slash` the user will be required to burn more share than anticipated. This is a normal consequence of the exchange rate change.

See the `testWithdrawSlash` test case.

#### `redeem`

Like for the `mint` operation, before of rounding error, if the user does not calculate correct the min number of shares to be burned to receive `X` asset, he could end up burning **more** shares than needed and receive the same number of assets.

In the worst-case scenario (edge case) the user could end up burning a number of shares greater than zero without receiving **any** amount of asset back.

See the `testRedeemSlash` test case.

### Test

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {console} from 'forge-std/console.sol';
import {StakeTestBase} from './utils/StakeTestBase.t.sol';

contract QERC4626SlashingTest is StakeTestBase {
  address u1 = makeAddr('u1');
  address u2 = makeAddr('u2');

  function testDepositSlash() public {
    _prepare();

    uint256 snapshot = vm.snapshot();

    // deposit 1000 assets WITHOUT slash influence
    vm.prank(u1);
    uint256 beforeSlash = stakeToken.deposit(1000, u1);

    // revert and slash max
    vm.revertTo(snapshot);
    _maxSlash();

    // deposit 1000 assets WITH slash influence
    vm.prank(u1);
    uint256 afterSlash = stakeToken.deposit(1000, u1);

    // user gets more shares by providing the same amount of asset
    assertGt(afterSlash, beforeSlash);
  }

  function testMintlash() public {
    _prepare();

    _maxSlash();

    vm.startPrank(u1);

    uint256 underlyingBalanceBefore = IERC20Metadata(stakeToken.asset()).balanceOf(u1);

    uint256 snapshotId = vm.snapshot();

    uint256 assetRequired1 = stakeToken.mint(1, u1);
    uint256 shareBalance1 = stakeToken.balanceOf(u1);
    uint256 underlyingBalance1 = IERC20Metadata(stakeToken.asset()).balanceOf(u1);

    // only 1 wei of underlying is pulled
    assertEq(underlyingBalance1, underlyingBalanceBefore - 1);
    assertEq(assetRequired1, 1);
    // only 1 shares have been received
    assertEq(shareBalance1, 1);

    vm.revertTo(snapshotId);

    uint256 assetRequired2 = stakeToken.mint(1e12, u1);
    uint256 shareBalance2 = stakeToken.balanceOf(u1);
    uint256 underlyingBalance2 = IERC20Metadata(stakeToken.asset()).balanceOf(u1);

    // only 1 wei of underlying is pulled
    assertEq(underlyingBalance2, underlyingBalanceBefore - 1);
    assertEq(assetRequired2, 1);
    // only 1e12 shares have been received
    assertEq(shareBalance2, 1e12);
  }

  function testWithdrawSlash() public {
    _prepare();

    vm.prank(u1);
    stakeToken.deposit(1 ether, u1);
    _cooldown();

    uint256 snapshot = vm.snapshot();

    // withdraw 1wei of asset WITHOUT slash influence
    vm.prank(u1);
    uint256 beforeSlash = stakeToken.withdraw(1, u1, u1);

    // revert and slash max
    vm.revertTo(snapshot);
    _maxSlash();

    // withdraw 1wei of asset WITH slash influence
    vm.prank(u1);
    uint256 afterSlash = stakeToken.withdraw(1, u1, u1);

    // to withdraw the same amount (1 wei) of assets, more share needs to be burned after the slash
    assertGt(afterSlash, beforeSlash);
  }

  function testRedeemSlash() public {
    _prepare();

    vm.prank(u1);
    stakeToken.deposit(1 ether, u1);
    _cooldown();

    uint256 snapshot = vm.snapshot();

    // redeen 1wei of shares WITHOUT slash influence
    vm.prank(u1);
    uint256 beforeSlash = stakeToken.redeem(1, u1, u1);

    // revert and slash max
    vm.revertTo(snapshot);
    _maxSlash();

    // redeem 1e12 wei of shares WITH slash influence
    vm.prank(u1);
    uint256 afterSlash = stakeToken.redeem(1e12, u1, u1);

    // redeemig 1wei of shares before the slash would have withdrawn 1wei of asset
    assertEq(beforeSlash, 1);

    // after the slash burning 1e12 wei of shares will withdraw ZERO assets
    assertEq(afterSlash, 0);
  }

  function _prepare() public {
    address stakeUnderlying = stakeToken.asset();

    vm.prank(u1);
    IERC20Metadata(stakeUnderlying).approve(address(stakeToken), type(uint256).max);

    vm.prank(u2);
    IERC20Metadata(stakeUnderlying).approve(address(stakeToken), type(uint256).max);

    _dealUnderlying(10 ether, u1);
    _dealUnderlying(10 ether, u2);

    vm.prank(u2);
    _deposit(10 ether, u2, u2);
  }

  function _cooldown() public {
    // create a cooldown to withdraw
    vm.prank(u1);
    stakeToken.cooldown();

    // warp to the moment we can withdraw
    vm.warp(stakeToken.getStakerCooldown(u1).endOfCooldown);
  }

  function _maxSlash() public {
    // slash the max slashable
    uint256 assetsToSlash = stakeToken.totalAssets() - stakeToken.MIN_ASSETS_REMAINING();
    vm.prank(admin);
    stakeToken.slash(someone, assetsToSlash);
  }
}
```

## Recommendations

BGD should consider to
1) Improve the documentation about the consequences of the slash events and how it can influence the `deposit`, `mint`, `withdraw` and `redeem` operations
2) Provide, at least for the `mint` and `redeem` function, a slippage protection mechanism that will revert if the
	- the amount of asset required to `mint` the specified shares is **above** an input threshold
	- the amount of asset received by redeeming the specified shares is **below** an input threshold
3) Provide a safe UI/UX interaction on the frontend site to minimize the user loss and inform him/her about the outcome of the operations

**StErMi:** The first recommendation has been implemented in the fix-review snapshot [c3c50501b885bfd7d221a784f1523528a842a641](https://github.com/bgd-labs/aave-umbrella-private/commit/c3c50501b885bfd7d221a784f1523528a842a641).

In the `README` file, the documentation relative to the `slash` consequences on the user operation has been improved.

The second recommendation has been acknowledged by BGD.
BGD mentioned that the third one will be implemented in the web application.

# [I-05] The `StakeToken` should better explain and document how the user will be compensated for the loss of rewards from not holding `StataTokenV2` anymore
## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

When a `StataTokenV2` holder stake their tokens into the `StakeToken` contract, they stop accruing all the tokens rewarded "indirectly" by holding the `aToken` wrapped by the `StataTokenV2` token. From that point on, those rewards will be accounted and accrued by the `StakeToken` contract itself. For more information about the "flow" of tokens and rewards, you can read a detailed explanation by looking at "[RESEARCH] Token flows and Reward accrual mechanism".

The current natspec documentation of the `StakeToken` contract states:

> Stakers will be rewarded through `REWARDS_CONTROLLER` for providing underlying assets. The `slash` function can be called by the owner. It reduces the amount of assets in this vault and transfers them to the recipient. Thus, in exchange for rewards, users' underlying assets may decrease over time.

While it's easy to understand the risk and consequences of staking those tokens when a `slash` operation is executed, the documentation fails to explain how the staker will be rewarded for the service provided and the risk taken and how it will compensate for the loss of rewards by not holding the staked `StataTokenV2` anymore.

## Recommendations

BGD should carefully plan and document how the `StataTokenV2` holders will be compensated for the "loss" of rewards accrual when they will stake their `StataTokenV2` tokens into the `StakeToken` contract.

**BGD:** The limitations section already includes information stating that rewards associated with `StataTokens` will not be awarded when depositing in `StakeToken`. While we aim to clarify this point further, it's important to note that `StataTokens` are not the only tokens stored in `StakeToken`. Therefore, we believe it may not be necessary to add this detail to the already extensive documentation.

# [I-06] Considerations on additional information to be tracked by the existing events and early return for unchanged values
## Context

- [ERC4626StakeTokenUpgradeable.sol#L288](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/extension/ERC4626StakeTokenUpgradeable.sol#L288)
- [ERC4626StakeTokenUpgradeable.sol#L296](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L296)
- [ERC4626StakeTokenUpgradeable.sol#L302](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a/src/contracts/stakeToken/extension/ERC4626StakeTokenUpgradeable.sol#L302)

## Description

**Note:** the snapshot for the security review is [dfa6a5449ac4680afd26f814bef945564fea402a](https://github.com/bgd-labs/aave-umbrella-private/blob/dfa6a5449ac4680afd26f814bef945564fea402a)

Some of the existing events could be enhanced with additional information that could provide more context and useful value to be later on used when consumed or tracked by dApps and monitoring system.

1) The `Slashed` event could track the `msg.sender` value that should represent the `owner` of the contract. Such value could change during the time and could be useful to track who has triggered a `slash` operation that is critical inside the system.
2) The `Slashed` event could track the "original" `amount` value that could be lowered by the internal logic if it's greater than the `maxSlashable` upper bound.
3) The `UnstakeWindowChanged` event could track the `msg.sender` value that should represent the `owner` of the contract.
4) The `UnstakeWindowChanged` event could track the previous value replaced by `newUnstakeWindow`
5) The `CooldownChanged` event could track the `msg.sender` value that should represent the `owner` of the contract.
6) The `CooldownChanged` event could track the previous value replaced by `newCooldown`

The behavior of tracking the "previous" value when the event is emitted, is a best practice that has been already adopted by the AAVE protocol in general and could be useful to apply it also in this contract.

An additional improvement could also be to early return or revert if the new value provided to `_setUnstakeWindow` and `_setCooldown` is equal to the existing one. This would avoid the emission of "useless" events.

## Recommendations

Note: see also the recommendations suggested in the finding  "The `StakerCooldownUpdated` event is not tracking the caller, which could be different from the owner of the shares".

BGD should consider:
1) enhancing the existing events with the additional information suggested in the "Description" section.
2) avoid emitting the event if the new value of the contact's configuration has not been changed.

**BGD:**
1. The owner of the contract will install another contract (like `UmbrellaController`), which will have an ACL behavior model under it. Several different roles will call slash or other actions with the `onlyOwner` modifier through this controller. Therefore `msg.sender` will not be useful in this situation.
2. The `amount` value will require the exact amount needed to pay off the bad debt. The `maxSlashable` value is set solely so that unexpected overflow cannot occur as a result of `totalAssets` being reset.
3. Same as 1. `msg.sender` will always return some kind of controller, inside of which there will already be an ACL model.
4. Fixed.
5. Same as 1 and 3.
6. Fixed.

Changing `cooldown` or `unstakeWindow` will happen as a result of voting in the DAO or via multisig, so we do not have safety checks in case of null or identical values. Because addresses capable of changing these parameters through the controller will require multiple checks of all parameters from at least several persons.

**StErMi:** The fourth and sixth recommendations have been implemented in the fix-review snapshot [a65133fdc87cd60857ea905e4d03679e1efccaba](https://github.com/bgd-labs/aave-umbrella-private/commit/a65133fdc87cd60857ea905e4d03679e1efccaba). The rest of the recommendations have been acknowledged by BGD.

Now both the `CooldownChanged` and `UnstakeWindowChanged` events track the previous value that has been replaced by the setter function.

# [RESEARCH] Token flows and Reward accrual mechanism

**Reward mechanism:**

In the `RewardController` (also called `IncentivesController`) each `asset` can be configured with a `reward` distribution defined as `(asset, reward)`. Example: `asset = aUSDC`, `reward = DAI`. An asset can have multiple reward distribution active at the same time. The same `reward` can be used for distributions of different `asset`s.

This mechanism is used to incentivize users to mint and hold specific assets.
The amount of rewards accrued by a user for an asset can be triggered in two different ways
- **automatically**: when the user performs an action that modifies the asset total supply or their balance: `mint`/`burn`/`transfer`. In this case, all the rewards distribution for the specific `asset` **must** be updated to the latest index and the user's accrued rewards should be updated too.
- **manually**: when the user claims some `reward`s for an asset. In this case, the system can limit itself to just updating the values of the subset of `rewards` specified by the user

**Legend:**

- `underlying`: `USDC`
- `aToken`: `aUSDC`
- `stataToken`: `stataUSDC`
- `stakeToken`: `stkStataUSDC` (but maybe naming will change)

## User flow of tokens and rewards accrual system

Let's assume:
- `RewardController` is configured to have a configured `(aUSDC, REWARD_TOKEN_1)` distribution
- `RewardController` is configured to have a configured `(stkStata, REWARD_TOKEN_2)` distribution
- `alice` owns `1000 USDC`
- for the sake of the example, let's assume that every rate is `1:1`

Given the above assumptions, these are the consequences when `alice` performs the following actions:
1) `alice` deposit `1000 USDC` into `AAVE` and receives `1000 aUSDC`
	- Balance changes:
		- `alice` has a balance of `1000 aUSDC`
		- `aUSDC` contract has a balance of `1000 USDC`
	- Accrual changes:
		- `alice` **START** accruing `REWARD_TOKEN_1` rewards
2) `alice` **transfer (wrap)** `aUSDC` to the `stataUSDC` contract and receives `1000 stataUSDC`
	- Balance changes:
		- `alice` has a balance of `1000 stataUSDC` and `0 aUSDC`
		- `stataUSDC` contract has a balance of `1000 aUSDC`
	- Accrual changes:
		- `alice` **STOP** accruing `REWARD_TOKEN_1` rewards "directly"
		- `stataUSDC` contract **START** accruing `REWARD_TOKEN_1` rewards (it's the new holder of the `aUSDC` tokens)
		- `alice` **START** accruing `REWARD_TOKEN_1` rewards "indirectly" via the `stataUSDC` contract
3) `alice` **transfer (stake)** `stataUSDC` to the `stkStataUSDC` contract
	- Balance changes:
		- `alice` has a balance of `1000 stkStataUSDC`, `0 stataUSDC` and `0 aUSDC`
		- `stataUSDC` contract has a balance of `1000 aUSDC` (unchanged)
		- `stkStataUSDC` contract has a balance of `1000 stataUSDC`
	- Accrual changes:
		- `alice` **STOP** accruing  `REWARD_TOKEN_1` rewards at all
		- `stataUSDC` contract **KEEP** (unchanged) accruing `REWARD_TOKEN_1`
		- `stkStataUSDC` contract **START** accruing `REWARD_TOKEN_1` rewards "indirectly" via the `stataUSDC` contract
		- `alice` **START** accruing `REWARD_TOKEN_2` rewards

**⚠️ Note:** the same flow and behavior (with the same problems described below) happens in complete reverse when `alice` will try to unstake the `stkStataUSDC` for `stataUSDC` and unwrap the `stataUSDC` for `aUSDC`
### Minting `aUSDC`

`alice` deposit `1000 USDC` into the AAVE market and receive `1000 aUSDC`. When the `AToken.mint` function is executed, it will call `IncentivesController.handleAction(alice, beforeMintTotalSupply, 0)` (I'm assuming this is the very first deposit of `alice`). On the `IncentivesController` all the reward distribution associated to `aUSDC` (the `AToken`) are updated given the configuration and the new values and the user's accrued amount is updated too. From now on, `alice` will start accruing rewards based on the time passed, the distribution configuration and the distribution state.

Every time that any user perform a `mint/burn/transfer` both **all** the rewards distributions associated to the `asset` and the users (`from` and `to` if there's any) state will be updated.

Note that this works the same as well for the `VariableDebtToken` excluding the transfer event, given that debt cannot be transferred.

## Wrapping `aUSDC` into `stataUSDC`

**⚠️ NOTE:** The `StataTokenV2` never calls `rewardController.handleAction(...)` meaning that the user does not accrue any rewards "directly" by owning the `StataTokenV2`

`alice` "wrap" those `1000 USDC` interacting with the `StataTokenV2` contract by calling `StataTokenV2.depositATokens(1000 aUSDC, alice)`.

This operation will execute the following sub operations:
- `aUSDC.transferFrom(alice, address(stataUSDC), 1000)`: `alice` transfer `1000 aUSDC` to the `stataUSDC` contract
- `IncentivizedERC20._transfer(alice, address(stataUSDC), 1000)` is executed as part of the `transferFrom` flow and will execute
	- `incentivesControllerLocal.handleAction(alice, currentTotalSupply, aliceOldBalance)`
	- `incentivesControllerLocal.handleAction(address(stataUSDC), currentTotalSupply, stataUSDCOldBalance);`
- `stataUSDC.mint(alice, 1000 stataUSDC)`: `alice` receive `1000 stataUSDC` wrapped token
- `stataUSDC._update(address(0), alice, 1000 stataUSDC)` is executed and will update `alice` accrued rewards on the `stataUSDC` data structure for all the "local rewards" `$._rewardTokens` registered by the `stataUSDC` contract. In this case, given that it's the very first deposit of `alice` (`balance === 0`) it will just update `$._userRewardsData[user][rewardToken].rewardsIndexOnLastInteraction` for every token to the `currentRewardsIndex` of the token (fetched from the `RewardController`)

The result of this operation is that:

1) The `stataUSDC` contract is the new "owner" of the `aUSDC` tokens
2) The `stataUSDC` contract has started accruing rewards **"directly"** for the `aUSDC` token distributions
3) `alice` has stopped accruing rewards **"directly"** for the `aUSDC` token distributions
4) `alice` has started accruing rewards **"indirectly"** for the `aUSDC` token distributions via the  `stataUSDC` balance

Theoretically, nothing should have changed for `alice`, she was accruing rewards for the `aUSDC` reward distributions directly, and now she should still accrue the very same rewards but in an "indirect" way through the `stataUSDC` contract that works like a centralized "reward hub holder" for all the `stataUSDC` token holders.

### [☠️ ISSUE] Not updated `$._rewardTokens` list will make `stataToken` holders earn fewer rewards or lose them forever

Unfortunately, there's a big difference in how the accrual and claiming process works compared between the holding `aUSDC` and `stataUSDC`.

When `alice` was holding the `aUSDC`, any operation (`mint/burn/transfer`) would have automatically updated the accrued amount of rewards for **EVERY** `reward` distribution associated to the `aUSDC` asset on the `RewardController`.

But once she has wrapped those `aUSDC` tokens for `stataUSDC` things have changed and now the holder and the one that is directly accruing those rewards is the `stataUSDC` contract itself.
The `stataUSDC` contract tries to mimic the same behavior of `aUSDC` but there is a main issue and difference: the contract is **not always** fetching the list of `reward` distributions associated to the `aUSDC` asset but is using a "cached" version stored in `$._rewardTokens` array.

The `$._rewardTokens` is updated **only** when the contract is initialized or when someone calls the `public` function `refreshRewardTokens()`

```solidity
function refreshRewardTokens() public override {
	ERC20AaveLMStorage storage $ = _getERC20AaveLMStorage();
	address[] memory rewards = INCENTIVES_CONTROLLER.getRewardsByAsset($._referenceAsset);
	for (uint256 i = 0; i < rewards.length; i++) {
		_registerRewardToken(rewards[i]);
	}
}

function _registerRewardToken(address reward) internal {
	if (isRegisteredRewardToken(reward)) return;
	uint256 startIndex = getCurrentRewardsIndex(reward);

	ERC20AaveLMStorage storage $ = _getERC20AaveLMStorage();
	$._rewardTokens.push(reward);
	$._startIndex[reward] = RewardIndexCache(true, startIndex.toUint240());

	emit RewardTokenRegistered(reward, startIndex);
}
```

If the `RewardController` adds and configures a new `(aUSDC, newReward)` reward distribution and no one calls the `stataUSDC.refreshRewardTokens()` function, `alice` (and all the other users) will **earn** fewer rewards than they should and, in the very worst scenario, **lose forever** those rewards if they perform a `withdraw` or `transfer` operation.

The rewards will be lost because when a `stataUSDC._burn` (called from a `withdraw` or `redeem` operation) or `stataUSDC.transfer/transferFrom` operation is executed, it will execute the `aUSDC.update(...)` function that should (like in the `aUSDC` contract) be responsible to automatically track the accrued rewards up to that point for the users involved in the operation.

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

But because it is using `$._rewardTokens` to iterate over the rewards associated to the `aUSDC` asset, it could end up skipping the recording of some of the rewards that should be awarded to the `from` and `to` users.

## Staking `stataUSDC` into `stkStataUSDC`

`alice` now stake her `1000 stataUSDC` for `1000 stkStataUSDC` in the `StakeToken` contract by executing `stkStataUSDC.deposit(1000 stataUSDC, alice)`. This operation will perform these sub-operations:
- `stataUSDC.transferFrom(alice, address(stkStataUSDC)`
- `stataUSDC._update(alice, address(stkStataUSDC), 1000 stataUSDC)` is executed and will update `alice` and `stkStataUSDC` `$._userRewardsData` accrual struct for **every** `reward` address cached in the `$._rewardTokens` list
- `stkStataUSDC._update(address(0), alice, 1000 stkStataUSDC)` is executed, which will trigger `REWARDS_CONTROLLER.handleAction(alice, totalSupplyBeforeStake, balanceOfAliceBeforeStake)` where `balanceOfAliceBeforeStake` is equal to zero given that it's her fist stake operation. In general, like for the `AToken` contract, when a `mint/burn/transfer` operation is executed, the contract will call `REWARDS_CONTROLLER.handleAction(...)` for `from` and `to` updating their reward distributions position for the `stkStataToken` token.

The result of this operation is that:

1) The `stkStataUSDC` contract is the new "owner" of the `stataUSDC` tokens
2) The `stkStataUSDC` contract has started accruing rewards **"indirectly"** for the `aUSDC` token distributions (via the `stataUSDC` contract)
3) `alice` has stopped accruing rewards for the `aUSDC` token distribution (via the `stataUSDC` contract)
4) `alice` has started accruing rewards for the `stkStataUSDC` token distributions because she now holds `stkStataUSDC`

# [FIX REVIEW I-01] `StakeToken` `permit` and `cooldownPermit` using the same nonce could create nonces overlap issues
## Context

- [StakeToken.sol#L90-L112](https://github.com/bgd-labs/aave-umbrella-private/blob/e0cbabc9df79b793afb81112ad9112079a996b0f/src/contracts/stakeToken/StakeToken.sol#L90-L112)

## Description

The `StakeToken` contract inherit from the `ERC20PermitUpgradeable` OZ contract that implements the `permit` feature to allow anyone (it's permissionless) to set the allowance of a `spender` on behalf of an `owner` via a `signature`.

The `ERC20PermitUpgradeable` contract inherit from the `NoncesUpgradeable` that uses a "common" `mapping(address account => uint256) _nonces;` state variable to manage users' nonces.

With the new implementation of `StakeToken` the same `_nonces[user]` will be used for both the `permit` and the `cooldownPermit` functions, meaning that the user must be aware and plan strictly the execution order of each "permit" style operation; otherwise they will revert with a `ERC2612InvalidSigner` error because the nonce, even if used for a different scope (operation), has been already consumed.

### Test

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {StakeTestBase} from './utils/StakeTestBase.t.sol';
import {IERC4626StakeToken} from '../../src/contracts/stakeToken/interfaces/IERC4626StakeToken.sol';
import {StakeToken} from '../../src/contracts/stakeToken/StakeToken.sol';

contract QPermitTest is StakeTestBase {
  bytes32 private constant COOLDOWN_WITH_PERMIT_TYPEHASH =
    keccak256('CooldownWithPermit(address user,uint256 nonce,uint256 deadline)');

  bytes32 private constant PERMIT_TYPEHASH =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  bytes32 private constant TYPE_HASH =
    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');

  bytes32 _hashedName;
  bytes32 _hashedVersion = keccak256(bytes('1'));

  address alice = makeAddr('alice');
  address randomUser = makeAddr('randomUser');
  uint256 amountToStake = 1 ether;
  uint256 deadline = block.timestamp + 1e6;

  function setUp() public override {
    super.setUp();

    _hashedName = keccak256(bytes(stakeToken.name()));
  }

  function testCommonNonce() public {
    // NONCE = 0 because it has never be used
    uint256 USER_NONCE = stakeToken.nonces(user);

    // deposit and get `StakeToken` shares
    _deposit(amountToStake, user, user);

    // create a `permit` sig for ALICE as a spender to execute `stakeToken.permit(...)`
    bytes32 permitDigest = keccak256(
      abi.encode(PERMIT_TYPEHASH, user, alice, amountToStake, USER_NONCE, deadline)
    );
    bytes32 permitHash = toTypedDataHash(_domainSeparator(address(stakeToken)), permitDigest);
    (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

    // create a `cooldownWithPermit` sig
    bytes32 cooldownDigest = keccak256(
      abi.encode(COOLDOWN_WITH_PERMIT_TYPEHASH, user, USER_NONCE, deadline)
    );
    bytes32 cooldownHash = toTypedDataHash(_domainSeparator(address(stakeToken)), cooldownDigest);
    (uint8 cooldownV, bytes32 cooldownR, bytes32 cooldownS) = vm.sign(userPrivateKey, cooldownHash);
    IERC4626StakeToken.SignatureParams memory cooldownSig = IERC4626StakeToken.SignatureParams(
      cooldownV,
      cooldownR,
      cooldownS
    );

    // create a snapshot
    uint256 snapshotId = vm.snapshot();

    // SCENARIO 1) execute `permit` -> `cooldownWithPermit`
    stakeToken.permit(user, alice, amountToStake, deadline, permitV, permitR, permitS);
    // it will revert with the `ERC2612InvalidSigner` error because the nonce used by `cooldownWithPermit` has been already "consumed"
    vm.expectRevert();
    stakeToken.cooldownWithPermit(user, deadline, cooldownSig);

    // SCENARIO 2) execute `cooldownWithPermit` -> `permit`
    vm.revertTo(snapshotId);
    stakeToken.cooldownWithPermit(user, deadline, cooldownSig);
    // it will revert with the `ERC2612InvalidSigner` error because the nonce used by `permit` has been already "consumed"
    vm.expectRevert();
    stakeToken.permit(user, alice, amountToStake, deadline, permitV, permitR, permitS);
  }

  // copy from OZ
  function _domainSeparator(address token) private view returns (bytes32) {
    return
      keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(token)));
  }

  function toTypedDataHash(
    bytes32 domainSeparator,
    bytes32 structHash
  ) private pure returns (bytes32 digest) {
    /// @solidity memory-safe-assembly
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, hex'19_01')
      mstore(add(ptr, 0x02), domainSeparator)
      mstore(add(ptr, 0x22), structHash)
      digest := keccak256(ptr, 0x42)
    }
  }
}
```

## Recommendations

BGD should consider using a separate `nonceCooldown` mapping struct for the `cooldownPermit` feature to avoid the above problem.

If the above suggestion is not implemented, BGD should at least document this behavior, explaining to the users that they should consider creating signature for "permit" operations one at a time to avoid the above issue.

**StErMi:** The recommendations have been implemented in the [PR 71](https://github.com/bgd-labs/aave-umbrella-private/pull/71).

# [FIX REVIEW I-02] `cooldownWithPermit` should be removed or made not permissionless
## Context

- [StakeToken.sol#L90-L112](https://github.com/bgd-labs/aave-umbrella-private/blob/e0cbabc9df79b793afb81112ad9112079a996b0f/src/contracts/stakeToken/StakeToken.sol#L90-L112)

## Description

The `cooldownWithPermit` function allows **anyone** (in a permissionless fashion) who has the `sig` value to execute the `cooldown` operation on behalf of the `user` specified in the signature.

Unlike the `permit` function (which is also permissionless) that could at most change the `spender` allowance (so not directly the `owner` itself), the `cooldownWithPermit` could indeed something that is directly tied to the final user and reset the existing cooldown snapshot.

Given how core and important the cooldown snapshot is and the fact that there's already a "cooldown operator" mechanism, this function could be at least refactored to be not permissionless, allowing only a specific EOA/contract (designated by the owner during the signature generation) to execute it.

## Recommendation

BGD should consider removing the feature, given that there's already an existing mechanism to delegate the `cooldown` execution to external EOA or contracts (see the new "cooldown operators" mechanism).

BGD should consider otherwise at least to remove the permissionless flavour from the execution, allowing only a specific EOA or contract to execute the `cooldownWithPermit`. This can be enabled by adding an `address executor` data into the signature and checking that the `msg.sender` matches it during the execution.

**StErMi:** The recommendation has been implemented in the [PR 74](https://github.com/bgd-labs/aave-umbrella-private/pull/74), only the `caller` specified by the `user` in the signature will be able to execute the `cooldownWithPermit` function.

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
