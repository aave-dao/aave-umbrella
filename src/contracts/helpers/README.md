# Umbrella Batch Helper

`UmbrellaBatchHelper` is a smart contract designed to optimize user interactions with the [Umbrella](https://governance.aave.com/t/bgd-aave-safety-module-umbrella/18366) system and its periphery, consolidating multiple transactions into a single one, via signatures.

Currently, `UmbrellaBatchHelper`covers the following:
- Deposit/withdraw funds between the different available routes. This is powered by a simple "smart" router, capable of handling different input/output token types such as `Token` (`Gho` or "standard" tokens), `aToken`, `StataTokenV2` and `StakeToken`.
- Claim accrued rewards on Umbrella, with optional restaking.
- Activate cooldowns for specified `StakeToken`s.

<br>

## Supported routes

The helper converts tokens through two routes:

1. `StakeToken` <-> `StataTokenV2` (`StakeToken` underlying) <-> `aToken` <-> `Token` (`StataTokenV2` underlying). Example with `USDC`:

    - `StakeToken`: `stkwaUSDC`
    - `StataTokenV2`: `waUSDC`
    - `aToken`: `aUSDC`
    - `Token`: `USDC`

2. `StakeToken` <-> `Token`. Example with `USDC`:

    - `StakeToken`: `stkUSDC`
    - `Token`: `USDC`

For these routes, it is possible to redeem any token specified in the route from `StakeToken` or make a deposit, starting from any one except stake.

Example:

- Route 1. `Token/aToken/StataTokenV2` can be deposited into or redeemed from `StakeToken` in a single transaction.
- Route 1. `Token/aToken/StataTokenV2` can be restaked into `StakeToken` if set as a reward for this specific stake.
- Route 2. `Token` can be deposited into or redeemed from `StakeToken`.
- Route 2. `Token` can be restaked into `StakeToken` if set as a reward for this specific stake.

![Routes Diagram](/assets/helper_routes.svg)

<br>

## Helper structs and actions

All structures and their parameters are detailed in the [interface](./interfaces/IUmbrellaBatchHelper.sol). Most actions require signatures to authorize transactions on behalf of the token owner.

- **CooldownPermit**: Triggers cooldown on `StakeToken` (via `cooldownPermit` function). For further clarification, refer to the [`StakeToken` documentation](../stakeToken/README.md).
- **ClaimPermit**: Claims rewards for specified `StakeToken`s and restakes them when possible (via `claimRewardsPermit` function).

  - If `restake == false`, the [signature](../rewards/RewardsDistributor.sol#52) must be made considering the actual receiver (`msg.sender`) of the funds.
  - If `restake == true`, the [signature](../rewards/RewardsDistributor.sol#52) must be made considering that the helper contract will receive the rewards.
  - Rewards can be restaked if they are the original tokens used to obtain the `StakeToken` (e.g. see [Supported Routes](#supported-routes)).
  - For the first route, if the reward is any token other than `StakeToken`, reinvestment is possible. For the second route, if the reward is `Token`, it can also be reinvested.
  - If a reward cannot be reinvested into `StakeToken`, it will be transferred to the `msg.sender`.
  - The `msg.sender` will receive all rewards and `StakeToken`s resulting from this operation.

- **Permit**: Manages allowances for `deposit/redeem` actions using `permit` and the corresponding signature.
- **IOData**: Handles deposits or withdrawals from `StakeToken`s (via `deposit` or `redeem` functions).

  - Deposits require prior approval via `permit` call or manual `approve` call for the initial token.
  - Withdrawals require `permit` call or manual `approve` call for the `StakeToken`.
  - *Important!* A withdrawal can only be completed if the required cooldown period has passed but is still within the `cooldown + unstakeWindow` timeframe. For further clarification, refer to the [`StakeToken` documentation](../stakeToken/README.md).
  - If the specified input token cannot be transferred to the helper’s address (due to insufficient allowance or `pause`) or cannot be directly converted to `StakeToken`, the transaction will be reverted. The same with redeem from `StakeToken`.

All functions are external and batch of actions could be called using `multicall`.

<br>

## Security principles

This contract is designed to mitigate many potential issues related to data validation. It employs a minimal set of functions that intentionally limit the available functionality for the user. If a user requires additional features (e.g., sending rewards to a specific address, claiming a lot of rewards from several assets without several signatures or triggering the cooldown on behalf of another user), they should interact directly with the `Umbrella` system components or use another helpers with more "wide" `multicall` functionality.

This design choice reduces the risk of potential attacks where a helper contract might be exploited by malicious actors. By using this contract, the recipient of all funds (during deposit, reward claiming, or withdrawal processes) is always guaranteed to be the `msg.sender`. Additionally, any extended functionality (such as increasing or decreasing allowances via permits or activating cooldowns for staked tokens) is restricted to only target the `msg.sender`.

### Permit-Based Operations

The contract supports actions that require user signatures, including:

- `ClaimSelectedRewardsPermit`: a call to `RewardsController` that collects the user's rewards.
- `CooldownPermit`: a call to specified `StakeToken` to trigger `cooldown` activation of user.
- `Permit`: a call to any token to increase/decrease allowance given to this contract.

Even if an attacker manages to obtain the necessary signatures, they cannot exploit them within this contract. This serves as an additional layer of protection for users.

### Data Validation

The contract fully validates its behavior using the provided input data. If data is incorrect, the transaction will revert, ensuring the integrity of operations.

The contract also prevents dust accumulation, cause all balance changes are tracked on-chain internally.

This approaches ensures that the contract is secure, efficient, and minimizes potential vulnerabilities while providing essential functionality for users.

### `Pausable`, `Rescuable` and `Ownable`

This contract inherits from the abstract contracts `Pausable`, `Rescuable`, and `Ownable`. The contract `owner` will be a multisig wallet responsible for pausing the contract in case of emergency situations. Additionally, the `owner` will have the ability to rescue funds that were mistakenly sent to the contract.

<br>

## Additional information

For additional information on implementation, we strongly advise you to familiarize yourself with the [interface](./interfaces/IUmbrellaBatchHelper.sol) with all possible structures, the work of [`RewardsController`](../rewards/README.md), [`StakeToken`](../stakeToken/README.md), as well as the [helper contract](UmbrellaBatchHelper.sol) itself.
