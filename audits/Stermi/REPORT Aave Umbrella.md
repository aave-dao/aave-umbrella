<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://raw.githubusercontent.com/aave-dao/aave-brand-kit/refs/heads/main/Logo/Logomark-purple.svg" width="250" height="250" style="padding: 4px;" /></td>
        <td>
            <h1>Umbrella Report</h1>
            <p>Prepared for: Aave DAO</p>
            <p>Code produced by: BGD Labs</p>
            <p>Report prepared by: Emanuele Ricci (StErMi), Independent Security Researcher</p>
        </td>
    </tr>
</table>

# Introduction

A time-boxed security review of the **Umbrella** protocol was done by **StErMi**, with a focus on the security aspects of the application's smart contracts implementation.

# Disclaimer

A smart contract security review can never verify the complete absence of vulnerabilities. This is a time, resource and expertise bound effort where I try to find as many vulnerabilities as possible. I can not guarantee 100% security after the review or even if the review will find any problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-chain monitoring are strongly recommended.

# About **Umbrella**

`Umbrella` is the core smart contract within the broader `Umbrella` project, enabling creation, configuration and slashing of `UmbrellaStakeTokens`, together with coverage of deficit in the associated Aave pool.

Previous review commit:
- Link: https://github.com/bgd-labs/aave-umbrella-private/tree/main/src/contracts/umbrella
- Last commit: `5b987d222355a1a8fa4b475e7f31968f66dd2394`

Latest review commit:
- Link: https://github.com/aave-dao/aave-umbrella/tree/main/src/contracts/umbrella
- Last commit: `62f3850816b257087e92f41a7f37a698f00fa96e`

# About **StErMi**

**StErMi**, is an independent smart contract security researcher. He serves as a Lead Security Researcher at Spearbit and has identified multiple bugs in the wild on Immunefi and on protocol's bounty programs like the Aave Bug Bounty.

Do you want to connect with him?
- [stermi.xyz website](https://stermi.xyz/)
- [@StErMi on Twitter](https://twitter.com/StErMi)

# Summary & Scope

**_review commit hash_ - [5ba619ea38a7ce09204a88319929478465621ea8](https://github.com/bgd-labs/aave-umbrella-private/tree/5ba619ea38a7ce09204a88319929478465621ea8)**
BGD has provided three additional commits to be reviewed:
- [commit diff e3dde13..de990c5](https://github.com/bgd-labs/aave-umbrella-private/compare/e3dde13..de990c5)

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
| ID                 | Title                                                                                                                                                             | Severity | Status          |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------- |
| [H-01]             | `liquidationBonus` included in the `pendingDeficit` will break Umbrella logics after a slash event                                                                | High     | Fixed           |
| [L-01]             | `Pool.eliminateReserveDeficit` should return the deficit eliminated to be then used as the actual value to be decreased from the `pendingDeficit`/`deficitOffset` | Low      | Ack             |
| [L-02]             | `Umbrella` should revert when it interacts with a not-whitelisted `stakeToken`                                                                                    | Low      | Fixed           |
| [L-03]             | `_updateSlashingConfig` additional sanity checks                                                                                                                  | Low      | Fixed           |
| [L-04]             | Using a "common" `mapping` stakeToken → stakeTokenUnderlyingOracle will create overriding issues                                                                  | Low      | Fixed           |
| [I-01]             | General informational issues                                                                                                                                      | Info     | Fixed           |
| [I-02]             | The same `stakeToken` can be configured to cover deficits of multiple `reserve`                                                                                   | Info     | Fixed           |
| [I-03]             | Consider aligning the oracle getters function to the current Chainlink                                                                                            | Info     | Ack             |
| [I-04]             | Considerations relative to the risk exposure of the `stakeToken` stakers compared to their reward                                                                 | Info     | Ack             |
| [I-05]             | `removeSlashingConfigs` will modify the order of configurations returned by `getReserveSlashingConfigs`                                                           | Info     | Ack             |
| [POST-REVIEW I-01] | discussion about commit diff `e3dde13..de990c5`                                                                                                                   | Info     | Partially Fixed |

# [H-01] `liquidationBonus` included in the `pendingDeficit` will break Umbrella logics after a slash event

## Context

- [Umbrella.sol#L169-L202](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/Umbrella.sol#L169-L202)

## Description

The `liquidationBonus` is a mechanism used by Umbrella to over-slash the `stakeToken` holders to repay for additional costs, and **should not** be used to cover any deficit. The current implementation of `_slashAsset` is instead incorporating the whole `liquidationBonus` inside the `pendingDeficit`. This could easily end up breaking one core invariant of Umbrella: `pendingDeficit <= poolDeficit`.

By breaking such invariant and over-accounting (compared to the actual deficit needed to cover by the slash) the slashed amount into `pendingDeficit` these main problems will arise:
- some of the `Umbrella` core functions will revert because of underflow errors
- some of the `Umbrella` logics will not work as expected
- the DAO will not receive the deserved part of the slash to cover the fees, incurring in a loss

Let's make an example to review all the above side effects. This is the initial context:

- USDC pool has a 100 USDC deficit
- `stkUSDC` has an "infinite" supply to cover any possible deficit
- there's no slashing config for the `USDC` in Umbrella and everything is at the "default" value state

The admin calls `updateSlashingConfigs` to add the `(USDC, stkUSDC)` slashing config with `liquidationBonus = 50%`. We now have

- `reserveDefitcit = 100 USDC`
- `deficitOffset = 100 USDC`
- `pendingDeficit = 0 USDC`

The `USDC` reserve generates `500 USDC` of additional bad debt, bringing the total `reserveDeficit` to 600 USDC.

Anyone calls `slashReserveDeficit(USDC)` that will execute `_slashAsset(USDC, stkUSDC_config, 500 USDC)`. Because of the `50% liquidationBonus` the final amount of `USDC` slashed by Umbrella will be `750 USDC` that will be fully added to the current value of the existing `pendingDeficit`. We now have:

- `reserveDefitcit = 600 USDC`
- `deficitOffset = 100 USDC`
- `pendingDeficit = 750 USDC`

With the above state, we have broken the core invariant `pendingDeficit <= reserveDeficit`. We can now look at all the parts of the code where the `pendingDeficit` is used to look for possible side effects:

1) `UmbrellaConfiguration.updateSlashingConfigs`

If the `DEFAULT_ADMIN_ROLE` role tries to remove the existing config and replace with a new one, the operation will revert for underflow when the following code is executed

```solidity
if (reserveData.configurationMap.length() == 0) {
  // if `pendingDeficit` is not zero for some reason, e.g. reinitialize occurs without previous full coverage `pendingDeficit`,
  // than we need to take this value into account to set new `deficitOffset` here.
  uint256 poolDeficit = POOL().getReserveDeficit(slashConfig.reserve);
  uint256 pendingDeficit = getPendingDeficit(slashConfig.reserve);

  _setDeficitOffset(slashConfig.reserve, poolDeficit - pendingDeficit);
}
```

`poolDeficit - pendingDeficit` will revert given that `poolDeficit = 600` but `pendingDeficit = 750`

2) `Umbrella.setDeficitOffset`

The `pendingDeficit` has been "inflated" and now the minimum `newDeficitOffset` that will satisfy the requirement

```solidity
require(
  newDeficitOffset + getPendingDeficit(reserve) >= POOL().getReserveDeficit(reserve),
  TooMuchDeficitOffsetReduction()
);
```

has been decreased by the `liquidationBonus` that has been included in the new `pendingDeficit` value. We can see this case not critical because at the end the `pendingDeficit` should be seen as an already slashed amount that will be used at some point to eliminate the deficit. We still need to consider that, because of the implementation of `_coverDeficit`, it won't correctly account the "surplus" of tokens sent to the `POOL` to eliminate the deficit (see detail on `coverPendingDeficit`)


3) `Umbrella.coverDeficitOffset`

- `poolDeficit = 600 USDC`
- `deficitOffset = 100 USDC`
- `pendingDeficit = 750 USDC`

The function will try to enter the `if (deficitOffset + pendingDeficit > poolDeficit)` but will revert when `poolDeficit - pendingDeficit` is calculated to execute `amount = _coverDeficit(reserve, amount, poolDeficit - pendingDeficit);`

4) `Umbrella.coverDeficitOffset`

- `poolDeficit = 600 USDC`
- `deficitOffset = 100 USDC`
- `pendingDeficit = 750 USDC`

The function will execute

```solidity
amount = _coverDeficit(reserve, amount, pendingDeficit);
_setPendingDeficit(reserve, pendingDeficit - amount);
```

Let's assume that it has been called as `coverDeficitOffset(USDC, 750 USDC)` to cover the full `pendingDeficit` value.
Internally, `_coverDeficit` will pull `750 aUSDC` (let's assume it's 1:1 with USDC for the sake of the example) from the `msg.sender` and execute `POOL().eliminateReserveDeficit(USDC, 750 aUSDC);`

The problem in this case is that `LiquidationLogic.executeEliminateDeficit` (called by the `POOL`) will pull from `msg.sender` (Umbrella in this part of the call's context) only what's needed to cover the real deficit

```solidity
uint256 balanceWriteOff = params.amount;

if (params.amount > currentDeficit) {
  balanceWriteOff = currentDeficit;
}
```

without letting the caller known which was the actual amount used to cover the deficit. `_coverDeficit` at this point assume that the whole `amount` (`750 aUSDC`) has been consumed to cover the deficit while only `600 aUSDC` has been used, `150 aUSDC` will remain inside the `Umbrella` contract and `coverDeficitOffset` will end up "resetting" to zero the `pendingDeficit` instead of reducing it by the real amount of tokens burned by the `LiquidationLogic` to reduce the actual deficit.

## Recommendations

BGD should:

1) Fix the behavior `_slashAsset`: it's correct to slash the `stakeToken` for the needed amount plus the configured `liquidationBonus` but the `liquidationBonus` must **not** be accounted in the final value that will be added to the existing `pendingDeficit`
2) Create unit and fuzzing tests around the core invariants to ensure that they are always held

**StErMi:** The recommendations have been implemented in the [commit `946a220`](https://github.com/bgd-labs/aave-umbrella-private/commit/946a220a57b4ae0ad11d088335f9bcbb0e34dcef)

# [L-01] `Pool.eliminateReserveDeficit` should return the deficit eliminated to be then used as the actual value to be decreased from the `pendingDeficit`/`deficitOffset`

## Context

- [Umbrella.sol#L137-L167](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/Umbrella.sol#L137-L167)

## Description

The current implementation of `_coverDeficit`, used by both `coverDeficitOffset` and `coverPendingDeficit` to reduce respectively the `deficitOffset` and `pendingDeficit` state variables of the `reserve`, does not return the **actual** value of deficit eliminated by the AAVE Pool when the `Pool.eliminateReserveDeficit` call is executed.

The current `Pool.eliminateReserveDeficit` implementation will eliminate up-to the current deficit, pulling from `msg.sender` (Umbrella) only what is needed. This could lead (on top of possible rounding errors during the transfer), as mentioned by the dev comment in dust, that will remain in the Umbrella contract, and less deficit removed Pool.

## Recommendations

BGD should consider performing the following changes:
1) `Pool.eliminateReserveDeficit` should return the actual deficit eliminated from the reserve
2) `_coverDeficit` should return the amount of deficit eliminated by `Pool.eliminateReserveDeficit`

**BGD:** We agree with this issue and we will definitely fix it in the future as it should simplify some code, so we don't want to set acknowledged status for this issue. So, "freeze" until v3.4.0 is optimal solution I think.

# [L-02] `Umbrella` should revert when it interacts with a not-whitelisted `stakeToken`
## Context

- [UmbrellaStkManager.sol#L104-L106](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L104-L106)
- [UmbrellaStkManager.sol#L115-L117](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L115-L117)
- [UmbrellaStkManager.sol#L128](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L128)
- [UmbrellaStkManager.sol#L137](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L137)
- [UmbrellaStkManager.sol#L142](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L142)
- [UmbrellaStkManager.sol#L147](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaStkManager.sol#L147)

## Description

The Umbrella system is responsible to creating, configure, and deploying all the `UmbrellaStakeToken` that will be later on used to configure the slashing configurations for a `reserve`.

Only the `stakeToken`s deployed via the `createStakeTokens` function via `Umbrella` can be used as inputs of the `updateSlashingConfigs` function; otherwise they would revert when `require(_isUmbrellaStkToken(slashConfig.umbrellaStake), InvalidStakeToken());` sanity check is executed.

For such reason, the same sanity check should be applied to every `stakeToken` passed as a parameter of the following functions offered by the `UmbrellaStkManager` contract:
- `setCooldownStk`
- `setUnstakeWindowStk`
- `emergencyTokenTransferStk`
- `emergencyEtherTransferStk`
- `pauseStk`
- `unpauseStk`

## Recommendations

BGD should revert the execution of the above functions if the `stakeToken` passed as input has not been deployed directly by the `Umbrella` instance.

**StErMi:** The recommendations have been implemented in the [PR 110](https://github.com/bgd-labs/aave-umbrella-private/pull/110)

# [L-03] `_updateSlashingConfig` additional sanity checks

## Context

- [UmbrellaConfiguration.sol#L239](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L239)
- [UmbrellaConfiguration.sol#L256](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L256)

## Description

The `_updateSlashingConfig` function executed to create or update a `(reserve, stakeToken)` slashing configuration should perform these additional sanity checks:
- The function should revert if the `slashConfig.reserve` token is not a valid or active `reserve` in the AAVE `$.pool`
- The function should revert if the `slashConfig.umbrellaStakeUnderlyingOracle` has not been properly configured or return an invalid price

## Recommendations

BGD should consider implementing the above sanity checks

**StErMi:** The recommendations have been implemented in the [PR 111](https://github.com/bgd-labs/aave-umbrella-private/pull/111).
Note: the current sanity check for the `reserve` checks that the `reserve` exists and has been configured on the pool without further checks on the `LT`, `LTV` or status flags values (active, paused and so on).

# [L-04] Using a "common" `mapping` stakeToken → stakeTokenUnderlyingOracle will create overriding issues

## Context

- [UmbrellaConfiguration.sol#L53](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L53)

## Description

Using a "common" `mapping` stakeToken → stakeTokenUnderlyingOracle that is not bound to the `reserve` will create problems when the `(reserve, stakeToken)` config is updated and when the `(reserve, stakeToken)` config is removed.

Scenario 1) overriding the oracle:
- Call `umbrella.updateSlashingConfigs` to setup the `(reserve1, stakeToken1)` config with oracle `oracle1`
- Call `umbrella.updateSlashingConfigs` to setup the `(reserve2, stakeToken1)` config with oracle `oracle2`

If we now call `umbrella.getReserveSlashingConfig(reserve1, stakeToken1)` the `umbrellaStakeUnderlyingOracle` is `oracle2` instead of `oracle1`

Scenario 2) Removing a configuration will "reset" the oracle of the other one:
- Call `umbrella.updateSlashingConfigs` to setup the `(reserve1, stakeToken1)` config with oracle `oracle1`
- Call `umbrella.updateSlashingConfigs` to setup the `(reserve2, stakeToken1)` config with oracle `oracle1`
- Call `umbrella.removeSlashingConfigs` to remove the `(reserve1, stakeToken1)` config

If we now call `umbrella.getReserveSlashingConfig(reserve2, stakeToken1)` the `umbrellaStakeUnderlyingOracle` will be equal to `address(0)` (because of `delete _getUmbrellaConfigurationStorage().underlyingOracles[removalPairs[i].umbrellaStake];`)

## Recommendations

Given how [`UmbrellaStakeToken.latestAnswer()`](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/stakeToken/UmbrellaStakeToken.sol#L35-L45) works, it's not possible to move the stake token oracle information into the `configurationMap`.

The only viable solution, without modifying the `UmbrellaStakeToken.latestAnswer()` behavior, is to prevent the `DEFAULT_ADMIN_ROLE` role to being able to configure a `stakeToken`, already bound to `reserve_1`, to another `reserve_2`.

**StErMi:** The recommendations have been implemented in the [PR 112](https://github.com/bgd-labs/aave-umbrella-private/pull/112)

# [L-01] General informational issues

## Description

### Natspec typos, errors or improvements

- [x] [README.md?plain=1#L14](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/README.md?plain=1#L14): the documentation relative to the "Deficit Offset" should be rewritten. The second part, relative to a practical example, it states the opposite of the explanation written in the first part.
- [x] [README.md?plain=1#L61](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/README.md?plain=1#L61): The "to Umbrella contracts" part relative to the `RESCUE_GUARDIAN_ROLE` role explanation should be more detailed. The `RESCUE_GUARDIAN_ROLE` can rescue `ERC20` tokens and the "native" blockchain token sent directly to
	- The `Umbrella` contract itself
	- All the `StakeToken` to which the `Umbrella` contract is the owner of (`stakeToken.owner() == UMBRELLA`). Relative to this, the documentation should be even more specific (see issue "`Umbrella` should revert when it interacts with a not-whitelisted `stakeToken`"), specifying that the `stakeToken` will be a token deployed through the `UmbrellaStkManager` factory.
- [x] [README.md?plain=1#L153](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/README.md?plain=1#L153): the correct name of the `slashAsset()` internal function is `_slashAsset(...)`
- [x] [README.md?plain=1#L153-L159](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/README.md?plain=1#L153-L159): the documentation of the `slashAsset()` should be re-written, specifying the behavior relative to the `liquidationBonus` concept. There are scenarios where, even if the `StakeContract` could fill the whole `deficitToCover`, because of the `liquidationBonus` less deficit will be covered.
- [ ] BGD should explain the concept and behavior of `liquidationBonus` in a separate section, providing practical example to cover all the possible scenarios.
- [x] [README.md?plain=1#L181](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/README.md?plain=1#L181): If the underlying of the `StakeToken` is the `waUSDC` token, the correct symbol for the `StakeToken` is `stkwaUSDC` (if the suffix passed to `createStakeTokens` is empty)
- [x] [IUmbrellaConfiguration.sol#L119](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol#L119): typo in the `@dev` comment. "isn't exist" should be replaced by "doesn't exist"

### Renaming and refactoring

- [x] [UmbrellaConfiguration.sol#L253](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L253): the sanity check on `liquidationBonus` should be placed at the very beginning of the flow to revert as early as possible

### Code improvement

- [x] Consider emitting specific events when the following functions are executed
	- [x] `coverDeficitOffset`
	- [x] `coverPendingDeficit`
	- [x] `slashReserveDeficit`. In this case, consider tracking also the "premium" (given by the `liquidationBonus`) removed from the slashed amount that is not going to "directly" cover the pending deficit
- [x] [Umbrella.sol#L174-L177](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/Umbrella.sol#L174-L177): If the common scenario will be to have `liquidationBonus == 0` (see `README`), consider skipping the calculation made in `_slashAsset`
- [x] [UmbrellaConfiguration.sol#L123-L124](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L123-L124): `map.remove(removalPairs[i].umbrellaStake)` returns `true` if it was able to remove the record with the key `removalPairs[i].umbrellaStake`. The `removeSlashingConfigs` could be refactored in the following way

```diff
-if (map.contains(removalPairs[i].umbrellaStake)) {
-	map.remove(removalPairs[i].umbrellaStake);

+bool configRemoved = map.remove(removalPairs[i].umbrellaStake);
+if( configRemoved ) {
	delete _getUmbrellaConfigurationStorage().underlyingOracles[removalPairs[i].umbrellaStake];
	emit SlashingConfigurationRemoved(removalPairs[i].reserve, removalPairs[i].umbrellaStake);
}
```
- [x] [UmbrellaConfiguration.sol#L144](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L144): consider using the `map.tryGet` flavor of the getter when `$.reservesData[reserve].configurationMap.get(umbrellaStake)` is executed in `getReserveSlashingConfig`. If the record does not exist, revert with a "custom" and more meaningful error
- [x] [UmbrellaConfiguration.sol#L148-L153](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L148-L153): consider checking the existence of the `stakeToken` oracle and revering with a "custom" and more meaningful error when `latestUnderlyingAnswer` is executed
- [x] [UmbrellaConfiguration.sol#L248](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L248): `_updateSlashingConfig` can directly use `reserveData.pendingDeficit` instead of re-fetching it via calling `getPendingDeficit(...)`

## Recommendations

BGD should fix all the suggestions listed in the above section

**StErMi:** BGD has acknowledged the request to further document the `liquidationFee` (formerly `liquidationBonus`) with this statement:

> This will be ignored for now, cause we don't plan to set different from 0 `LiquidationFee` during start of `Umbrella` system.

The remaining recommendations have been implemented in the [PR 111](https://github.com/bgd-labs/aave-umbrella-private/pull/111) and [PR 113](https://github.com/bgd-labs/aave-umbrella-private/pull/113)

# [I-02] The same `stakeToken` can be configured to cover deficits of multiple `reserve`
## Context

- [UmbrellaConfiguration.sol#L110](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L110)

## Description

In the current implementation of the `Umbrella` protocol, nothing prevents the `DEFAULT_ADMIN_ROLE` to configure the same `stakeToken` to eventually cover the deficit of multiple reserves.
When the same `stakeToken` is bound to multiple reserves, the risk exposure of the staker increases without increasing the reward that is bound to the amount of token staked in `stakeToken` (and the relative rewards bound to them).

## Recommendations

BGD should carefully explain and disclose this possibility in their documentation and website, warning the stakers about the possible increase in risk without an appropriate and correlated increase in rewards.

Note: if BGD will pursue the recommendation described in the issue "Using a "common" mapping stakeToken → stakeTokenUnderlyingOracle will create overriding issues", this informational finding can be considered as solved automatically.

**StErMi:** The recommendations have been implemented in the [PR 112](https://github.com/bgd-labs/aave-umbrella-private/pull/112)

# [I-03] Consider aligning the oracle getters function to the current Chainlink
## Context

- [IOracleToken.sol#L11](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/stakeToken/interfaces/IOracleToken.sol#L11)
- [IUmbrellaConfiguration.sol#L159-L161](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol#L159-L161)

## Description

Chainlink has officially deprecated the `latestAnswer` function from both their [documentation](https://docs.chain.link/data-feeds/api-reference#latestanswer) and their [`AggregatorV3`'s interface contract](https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol).

To align with Chainlink, the same deprecation should also be performed on Umbrella and the relevant contracts, replacing the `latestAnswer` functions with the corresponding `latestRoundData` function.

## Recommendations

BGD should consider replacing in the whole Umbrella, `StataToken` and `StakeToken` codebases the "old" and deprecated `latestAnswer` function with the new adopted one `latestRoundData`.

**StErMi:** BGD has acknowledged the issue.

**BGD:** For now, this change makes little sense, since almost all oracles used within our system have some modifications and work exclusively when calling `latestAnswer`. Changing this function and replacing it entirely with `latestRoundData` currently requires updating too many contracts for no significant benefit to the system.

So the final status is acknowledged.

# [I-04] Considerations relative to the risk exposure of the `stakeToken` stakers compared to their reward
## Description

Stakers of the `stakeToken`, stakes for rewards that are bound to the amount of token staked (and time locked for an amount of time before being able to be withdrawn).

At any point in time, the `DEFAULT_ADMIN_ROLE` could change the risk exposure of the staker by:
- increasing the `liquidationBonus` of the `(reserve, stakeToken)` configuration
- "moving" the `stakeToken` to cover a more "risky" `reserve`
- covering multiple reserves with the same `stakeToken` (see the "The same `stakeToken` can be configured to cover deficits of multiple reserve" issue)

## Recommendations

BGD should extensively and carefully document this behavior and build a UX that allows the staker to monitor and be aware of the possible changes in his risk exposure.

**StErMi:** BGD has acknowledged the issue.

**BGD:** At the moment there are no plans to install assets that have different mechanics (for example `StakeToken - GHO`, `reserve - WETH`). This coverage mechanism is suboptimal and it was this that we tried to eliminate first by updating the `SafetyModule` to the new `Umbrella` system. Therefore, cases of reinstalling `UmbrellaStakeToken` from one asset to another “more” risky one are not considered in the first version. The goal is to link similar (in terms of pricing) assets with each other. We cannot fully guarantee this condition on-chain due to the highly suboptimal checks that are required. However, on our part, we will do everything possible to explain why such use of the system is irrational.

An increase of `LiquidationBonus` (especially a significant one) should also not occur in the current version, since setting such a parameter should be explained by some problems: for example, the inability to convert one asset into another directly, only through exchanges with slippage, and etc. However, this problem boils down to the above.

Covering several reserves with one `StakeToken` will be commented separately.

Status - acknowledged.

# [I-05] `removeSlashingConfigs` will modify the order of configurations returned by `getReserveSlashingConfigs`

## Context

- [UmbrellaConfiguration.sol#L124](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L124)
- [UmbrellaConfiguration.sol#L156-L174](https://github.com/bgd-labs/aave-umbrella-private/blob/5ba619ea38a7ce09204a88319929478465621ea8/src/contracts/umbrella/UmbrellaConfiguration.sol#L156-L174)

## Description

This is not a security issue per se, but it's still important to be documented and known.

When `map.remove` is executed by `removeSlashingConfigs` and the `key` (`stakeToken` address) removed from the configuration mapping was the key relative to an item that was not the latest one in the internal array representation, the order of the stake token configurations returned by `getReserveSlashingConfigs` will change.

Let's say that we start with this configuration for `reserve_1`:
1) `stakeToken1` with `LB 1`
2) `stakeToken2` with `LB 2`
3) `stakeToken3` with `LB 3`
4) `stakeToken4` with `LB 4`

and then we remove `stakeToken2`

When we call `getReserveSlashingConfigs` again, the returned array will be:
1) `stakeToken1` with `LB 1`
2) `stakeToken4` with `LB 4`
3) `stakeToken3` with `LB 3`

The `getReserveSlashingConfigs` is not currently used internally but only off chain or by other contracts in the ecosystem, and the Umbrella slashing logic will not work when there are zero or more than one slashing configuration for a reserve.

When in the future the protocol will support multiple slashing configuration per reserve, this behavior could create problems if not known or handled accordingly.

## Recommendations

BGD should be aware of the behavior and keep it in mind for future developments of the Umbrella contract.

**StErMi:** BGD has acknowledged the issue.

**BGD:** Yes, we will take this into account, but even with the current drafts with multiple `StakeToken`s, everything worked regardless of the order of the tokens and their `LiquidationBonus`es.

Therefore, in the current version it should be acknowledged.

# [POST-REVIEW I-01] discussion about commit diff `e3dde13..de990c5`

## Context

- [diff e3dde13..de990c5](https://github.com/bgd-labs/aave-umbrella-private/compare/e3dde13..de990c5)

## Description

1) There's no way to reset/clean the `stakeToken` `underlyingOracle`. What if you want to fully remove the support for the `stakeToken` (maybe because the ratio now is broken, and you simply want to re-deploy a new `stakeToken`) and the correct behavior from now on is to simply revert/return 0 when the `latestUnderlyingAnswer` is called?

2) `latestUnderlyingAnswer` revert

With the fact that now you still maintain the `_getUmbrellaConfigurationStorage().stakesData[stakeToken].underlyingOracle` even when the configuration has been removed, I don't know how much sense the revert error name is correct when `require(underlyingOracle != address(0), ConfigurationNotExist());` is executed in `latestUnderlyingAnswer`

when `underlyingOracle != address(0)` it DOES NOT mean that the slashing configuration exists because we could be in this scenario

	1) The configuration exists
	2) The configuration does not exist anymore because it has been removed, but the oracle has not been cleaned (new logic).


3) Further document `struct StakeTokenData` attribute `underlyingOracle`.  I think it makes sense to add more context to the natspec specifying that even if `reserve == address(0)` the `underlyingOracle` could be `!= address(0)` because of the new logic in `removeSlashingConfigs`

4) Further document the `function latestUnderlyingAnswer` natspec in `IUmbrellaConfiguration`. It could make sense to also enhance the function's natspec describing the "weird" behavior that oracle/price will return even if the configuration has been removed.

## Recommendations

BGD Should consider applying the above suggestions

**StErMi:** BGD has acknowledged the first point with the following statement

> Regarding point 1, we are unable to completely stop supporting `StakeToken` (not taking into account the `pause`, which is not an optimal solution).
>
>In any case, some intermediate values ​​will remain relative to the created `StakeToken`s. Information about them will remain in `Umbrella.getStkTokens()`, in `RewardsController` (`targetLiquidity`, `lastUpdateTimestamp`, etc cannot and shouldn't be fully zeroed).
>
>Therefore, in any case, there will be some "garbage" left, which would be optimal to clean up, but we cannot guarantee this for technical reasons.
>
>We also don't expect the ratio to be broken to the point where it will overflow when trying to calculate the exchange rate, it could happen, we don't deny it, but in theory we shouldn't limit ourselves because of this case. If the ratio is completely broken, then `latestAnswer` won't work correctly either, so this problem doesn't interfere with the current solution.
>
>Redeploying the token also does not affect the `latestAnswer` function in any way; it will result in two different values, for different tokens, which is normal.

Recommendations 2, 3 and 4 have been implemented in the [PR 130](https://github.com/bgd-labs/aave-umbrella-private/pull/130)

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

Relative to the above code the following Informational issue has been reported

## `UmbrellaStkManager._createStakeToken` is not reverting anymore when a proposal tries to deploy and configure the same `UmbrellaStakeToken`

### Context

- [UmbrellaStkManager.sol#L216-L232](https://github.com/aave-dao/aave-umbrella/blob/62f3850816b257087e92f41a7f37a698f00fa96e/src/contracts/umbrella/UmbrellaStkManager.sol#L216-L232)

### Description

The `_createStakeToken` function will be called by the `createStakeTokens` function during the creation, deployment and configuration of new `UmbreallaStakeToken` to be later on used for the Umbrella system.

The following changes have been applied:

```diff
-address umbrellaStakeToken = TRANSPARENT_PROXY_FACTORY().createDeterministic(
-  UMBRELLA_STAKE_TOKEN_IMPL(),
-  SUPER_ADMIN(),
-  creationData,
-  ''
-);

+address umbrellaStakeToken = TRANSPARENT_PROXY_FACTORY().predictCreateDeterministic(
+  UMBRELLA_STAKE_TOKEN_IMPL(),
+  SUPER_ADMIN(),
+  creationData,
+  ''
+);

+if (umbrellaStakeToken.code.length == 0) {
+  // name and symbol inside creation data is considered as unique, so using different salts is excess
+  // if for some reason we want to create different tokens with the same name and symbol, then we can use different `cooldown` and +`unstakeWindow`
+  TRANSPARENT_PROXY_FACTORY().createDeterministic(
+    UMBRELLA_STAKE_TOKEN_IMPL(),
+    SUPER_ADMIN(),
+    creationData,
+    ''
+  );
+}
```

With the previous implementation, deploying an `UmbrellaStakeToken` using the same inputs parameter `StakeTokenSetup` would have resulted in a "native" revert (re-deployment of the same contract). This was useful to prevent possible deployment errors during the execution of a proposal that would have deployed an already existing `UmbrellaStakeToken`.

The new code instead explicitly check if the `UmbrellaStakeToken` with those `StakeTokenSetup` parameters have been already deployed and avoid reverting returning the existing token address.

This change allows possible misconfigured proposal execution that should **never** deploy, configure and use the same `UmbrellaStakeToken` twice in the Umbrella system.

### Recommendations

BGD should revert the code to the previous logic implementation or detail why such a change was needed and which new sanity checks will be placed at the creation or execution of the proposal to avoid possible misconfiguration errors that will "silently" succeed and won't revert as expected.

**StErMi:** BGD has acknowledged the finding.

**BGD:** Yes, indeed, reverting when creating a token with identical parameters would be convenient to prevent old tokens from being used as new ones, but it potentially led to more unpleasant consequences in the form of the fact that the payload that included the creation of the token could be canceled (due to the lack of restrictions on creating proxies through the factory).

This problem would not be solved by recreating the payload, as such an attack could be re-executed, which would result in the inability to create and add a token to the `EnumerableSet` and further use it.

At the moment, token creation is only possible through proposals, which are checked by several people at the same time, so we will specifically monitor this issue separately. In a future Umbrella update, we will introduce the necessary check to avoid this problem.
