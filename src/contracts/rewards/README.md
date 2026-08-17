# Umbrella Rewards Controller

The `RewardsController`/`RewardsDistributor` is a smart contract to track and allow claiming of rewards, designed exclusively for usage on the [Umbrella](https://governance.aave.com/t/bgd-aave-safety-module-umbrella/18366) system.

This contract works alongside the Umbrella `StakeToken`s to provide rewards to their holders for securing Aave against bad debt. These rewards can be arbitrary erc-20 tokens, without unexpected functionality (ERC777, fee-on-transfer, and others).

<br>

## Features

- **Multi-rewards accounting for StakeToken assets.** The system accounts for one or multiple rewards distributed evenly across all `StakeToken` holders over time, with emissions measured in rewards per second, moderated via an Emission Curve. Any action within the `StakeToken` that changes a user’s balance, `totalAssets`, or `totalSupply` triggers an automatic update to rewards.
- **Configurable access control for claiming of rewards.** Rewards accrue in the contract and can be claimed by the staker itself, trusted claimers, or via signature-based claims.
- **Emission Curve.** The rewards emitted by the system to stakers are moderated via a curve of intervals, function of current total liquidity and a configured target. See [`Emission Curve`](#emission-curve) for more info.
- **Two-layered access control and upgradeability.** The RewardsController operates under a transparent proxy and can be upgraded by Aave governance, which also acts as super-admin of the system. Constrained configuration of rewards is assigned to a different role to act as rewards admin of the system. See [`Access Control`](#access-control) for more info.

Refer to [`IRewardsController.sol`](interfaces/IRewardsController.sol) and [`IRewardsDistributor.sol`](interfaces/IRewardsDistributor.sol) for detailed method documentation.

<br>

## Brief high-level overview

### Contracts overview

All main logic is distributed between two main contracts [`RewardsController.sol`](RewardsController.sol), [`RewardsDistributor.sol`](RewardsDistributor.sol) and the library [`EmissionMath`](libraries/EmissionMath.sol).

- The [`RewardsDistributor.sol`](RewardsDistributor.sol) is an abstract contract that defines methods for granular rewards claiming.

- The [`EmissionMath`](libraries/EmissionMath.sol) is a library that is responsible for calculating indexes, the number of accrued rewards, `emissionPerSecond` and other parameters.

- The [`RewardsController.sol`](RewardsController.sol) is the main contract managing asset parameters, reward configurations, user reward calculations, and direct transfers. It stores a list of initialized assets and their configurations, with all relevant data tied to the asset address.

#### Asset config

- Assets can have multiple rewards (up to 8 in current version) and store `lastUpdateTime` and `targetLiquidity`.
  - The `lastUpdateTime` is a parameter that is updated every time an non-view interaction with the asset or rewards occurs. Sets the timestamp when the update occurs.
  - The `targetLiquidity` is a parameter that shows the optimal amount of `totalAssets` inside `StakeToken` that will result in the maximum number of rewards.
- The asset config stores information about all initialized rewards.

#### Reward config

- Each reward includes the following parameters:
  - The `maxEmissionPerSecond` is a maximum possible emission, which will be reached by depositing `targetLiquidity` amount of assets.
  - The `distributionEnd` is a timestamp when emissions stop.
  - The `rewardPayer` is an address funding the rewards.
- Rewards also store information about users.

#### User data

- Each user data stores indexes and accrued rewards.
  - The `index` is the index value that this user had at the time of the last update (can be 0 if the user has never interacted with the asset since the new reward was initialized).
  - The `accrued` is an amount of rewards pending to claim (updates when rewards are claimed, or when the index is updated).

Rewards can be shared across multiple assets but have unique parameters for each.
Setting asset and reward parameters is managed through two primary roles, ensuring proper initialization and maintenance.

### Access Control

There are two roles used to manage assets and their rewards.

- `DEFAULT_ADMIN_ROLE` will be assigned to Aave governance and responsible for:
  - Initializing new assets and configuring old ones.
  - Initializing new rewards and configuring old ones.
- `REWARDS_ADMIN_ROLE` will be assigned to multisig and responsible for configuring already initialized rewards.

Assets must be initialized before adding rewards. Both assets and rewards require valid parameters for initialization.

Both roles can update `maxEmissionPerSecond`, `distributionEnd` or disable reward emissions. Only `DEFAULT_ADMIN_ROLE` can modify `targetLiquidity`.

### `StakeToken` and rewards emission deactivation

Initialized assets and their rewards cannot be deleted. This condition protects user funds and rewards from arbitrary deletion or cancellation.
This condition helps users who do not actively follow the life of the protocol to collect rewards at a time convenient for them, even if a couple of years have passed since the assets were disabled within Umbrella.

Therefore, disabling `StakeToken` from `Umbrella` inside `RewardsController` looks like simply disabling the emission of all rewards.
Thus, we hope that, without additional incentives, users will withdraw their funds voluntarily due to the ineffectiveness of continued retention.

### Emission Curve

The [`EmissionMath`](libraries/EmissionMath.sol) library dynamically adjusts reward emission rates. It uses curves to increase, decrease, or maintain flat emission rates, depending on the `totalAssets` deposited into `StakeToken` relative to a `targetLiquidity`.

The piecewise linear curve is defined by three different sectors:

![Emission Curve Graph](/assets/emission_curve_graph.jpg)

1. The first sector uses a steeper, boosted formula where the emission rate scales proportionally with `totalAssets` relative to `targetLiquidity`, incentivizing early deposits. The calculation formula is:

    ```solidity
    emissionDecrease = (maxEmissionPerSecond * totalAssets) / targetLiquidity;
    emissionPerSecond = (2 * maxEmissionPerSecond - emissionDecrease) * totalAssets / targetLiquidity;
    ```

2. Between `targetLiquidity` and `targetLiquidityExcess`, the emission rate decreases from `maxEmissionPerSecond` to `flatEmissionPerSecond` (80% of `maxEmissionPerSecond`) to deter further deposits. The formula for this sector is:

    ```solidity
    deltaTarget = targetLiquidityExcess - targetLiquidity;
    deltaEmission = maxEmissionPerSecond - flatEmissionPerSecond;

    emissionPerSecond = maxEmissionPerSecond - ((deltaEmission * (totalAssets - targetLiquidity)) / deltaTarget);
    ```

3. Beyond `targetLiquidityExcess`, the emission rate becomes flat to discourage additional deposits. The formula is:

    ```solidity
    emissionPerSecond = flatEmission;
    ```

- **`maxEmissionPerSecond` Constraints:**
  - **Maximum:** `1,000 * 1e18` per second.
  - **Minimum:** Lesser of `2 wei` or `targetLiquidity / 1e15`. (See [EmissionMath](libraries/EmissionMath.sol))
- **`targetLiquidity` Constraints:**
  - **Minimum:** 1 asset token.
  - **Maximum:** `1e36`. (The upper bound is indirectly provided by the further validation performed on the minimum value required for the `maxEmissionPerSecond`. `maxEmissionPerSecond` must be <= 1e21 but also >= targetLiquidity * 1e3 / 1e18.)
- **Precision Loss:**
  - If totalSupply is below `1e6`, rewards distribution is adjusted to prevent overflow, which may affect fairness of reward distribution.
  - If `totalSupply/totalAssets` ratio exceeds `100` with minimal emission, precision may degrade, potentially requiring a `StakeToken` redeployment.

#### Key Parameters

- `targetLiquidityExcess` = `120%` of `targetLiquidity`
- `flatEmissionPerSecond` = `80%` of `maxEmissionPerSecond`

### Rewards decimals scaling

To simplify `index` calculations and optimize `storage` usage to reduce transaction fees, rewards are virtually scaled to 18 decimals.

- For 18-decimal rewards: No changes are made.
- For rewards with fewer decimals (e.g., 6): A multiplier (e.g., 1e12) is applied to scale them to 18 decimals.

This approach enables high-value, low-decimal assets (like wBTC) to be used as rewards for high-decimal, low-value assets without losing accuracy.

While this solution introduces minor inefficiencies and imposes additional restrictions, its advantages such as improved accuracy and compatibility far outweigh the drawbacks.

For more accurate calculations, it is proposed to use functions that return a scaled emission value.

### Operating Conditions

To ensure the system meets our expectations, we tested the system to see if it can work under certain conditions. Read more [here](/assets/operating_conditions.md) for details.

<br>

## Key Functions

### `configureAssetWithRewards`

- **Role:** Governance - only.
- **Purpose:** Sets or updates a new asset.
- **Functionality:**
  - Configures parameters like `targetLiquidity`.
  - Initializes or updates multiple rewards simultaneously.
  - If the asset is already initialized, updates all associated rewards.

### `configureRewards`

- **Role:** Restricted to `REWARDS_ADMIN_ROLE`.
- **Purpose:** Adjusts reward parameters for initialized assets and rewards.
- **Functionality:**
  - Always updates rewards before changing parameters.
  - Configures rewards only for assets already set up by the governance.
  - Allows batch modification of rewards for concrete `asset`.

### `handleAction`

- **Trigger:** Executed on every action in `StakeToken` that alters user `balance`, `totalAssets`, or `totalSupply`.
- **Purpose:** Updates rewards for a given asset and, if specified, for a particular user.
- **Outcome:** Recalculates accrued rewards and updates reward indices.

### `updateAsset`

- **Purpose:** Standalone alternatives to `handleAction`.
- **Functionality:** Update rewards independently but provide no advantage over `handleAction`. Primarily for internal use.

### `claim`

- **Purpose:** Collects accrued rewards.
- **Functionality:**
  - Multiple claim functions allow either full or selective reward collection.
  - Always updates reward indices and user data when called.
  - Combining claims with withdrawals in the same block minimizes redundant updates and gas costs.

### `setClaimer`

#### Public Access

- Allows any user to designate or revoke an authorized claimer for their rewards.

#### Admin Role Access

- DAO-only.
- Assigns or removes claimers for any token holder, useful for contracts unable to manage rewards independently.

#### Rescuable

[`RescuableACL`](https://github.com/bgd-labs/solidity-utils/blob/main/src/contracts/utils/RescuableACL.sol) has been applied to the `RewardsController` which will allow the `DAO` to rescue tokens from this contract.

## Limitations

- Can only be used for Umbrella `StakeToken`, as it requires interaction through an updated interface.
- If the `StakeToken` `totalSupply` is less than 1e6, a less fair reward distribution is applied. This prevents a sharp `index` increase relative to the actual `totalSupply`, ensuring system security against potential overflow.
- If the `totalSupply/totalAssets` ratio is exceeded by more than a 100 under minimal emission, calculation accuracy is not guaranteed.
- If the user's balance or the reward's index delta is small enough such that `(userBalance * (newRewardIndex - oldUserIndex)) < 10^18`, the user may lose the accrued reward for that timeframe. The reward index includes a multiplier of `10^18`, so this issue should not occur in most cases. However, in certain situations, this condition could be met. Be careful if index changes are small (`<< 10^18`). To avoid this issue, you can increase the intervals between data updates (through transfers or claims), as well as deposit more tokens.
