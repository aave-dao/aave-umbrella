# Operating conditions

## Requirements

To ensure the system meets our expectations, we introduce two types of requirements:

1) Hard requirements. These requirements are enforced by the code. For example:
    1. `totalAssets <= totalSupply`, because `StakeToken` slashes reduce only the `totalAssets`.
    2. `targetLiquidity >= 10 ** decimals` (at least 1 whole token).
    3. `maxEmissionPerSecond <= 10^21` and `maxEmissionPerSecond >= minBound`, where `minBound = precisionBound > 2 ? precisionBound : 2`, and `precisionBound = targetLiquidity / 10 ^ 15`
    4. `totalSupply >= 1e6`

2) Soft requirements: These are conditions that the code does not enforce, but they provide guidelines for optimal behavior:
    1. `totalAssets/targetLiquidity <= 10`. This condition doesn't make any sense for holders, cause APY in this case will be less than optimal by 12.5 times. Futhermore, holding funds at risk of 100% slashing with such a low APY is not justified.
    2. `totalSupply/totalAssets <= 100`. The `totalSupply/totalAssets` ratio can, due to the architecture, grow up to 2 ^ 256 / 10 ^ 6. We set a limit of 100, once we reach it, we will redeploy the `StakeToken` contract. Because, such an increase in the exchange rate can lead to calculation inaccuracies in the entire system.

## Additional notes

1) Violating soft requirements doesn't mean the contract will not be functional anymore with this concrete asset, but may result in decreased calculation accuracy (potentially causing new accrued rewards to be zeroed out).

2) For simplicity, we will ignore the order of operations in some places and present the proofs in mathematical form. While there may be some exceptions, the following calculations are valid for the vast majority of cases.

## `SlopeCurve` - overflow check

1) (typeOf(index) = uint144) 2^144 ~= 2.23e43
2) Maximum possible `maxEmissionPerSecond` = 1e21
3) Maximum possible `currentEmission = SCALING_FACTOR * maxEmissionPerSecond * totalAssets/targetLiquidity = 1e39` (cause max(totalAssets/targetLiquidity) is 1 on `SlopeCurve`)
4) (Let's take min possible `totalSupply = 1e6`)
5) 2.23e43 * 1e6 / 1e39 / 365 / 24 / 3600 = ~707 years without overflow

~707 years without overflow under the worst conditions.

## Other sectors - overflow check

Since other sectors result in slower index growth, there's no need to check for overflow, only for a zero `indexIncrease` changes.

## `SlopeCurve` - zero `indexIncrease` check

The index should be able to be updated at least by 1 uint every second (ignoring precision loss for now)

1) `1 == (currentEmission * 1) / totalSupply`
2) `currentEmission == totalSupply` (cause totalSupply != 0 if totalAssets != 0)
3) `((2 * maxEmissionPerSecond * SCALING_FACTOR - (maxEmissionPerSecond * SCALING_FACTOR * totalAssets) / targetLiquidity) * totalAssets) / targetLiquidity == totalSupply`
4) `((2 * maxEmissionPerSecond * SCALING_FACTOR - maxEmissionPerSecond * SCALING_FACTOR * totalAssets / targetLiquidity) * totalAssets == totalSupply * targetLiquidity` (due to the fact, that `targetLiquidity` != 0)
5) `maxEmissionPerSecond * SCALING_FACTOR * totalAssets / targetLiquidity` can't exceed `maxEmissionPerSecond * SCALING_FACTOR` on `SlopeCurve`, so
6) `maxEmissionPerSecond * SCALING_FACTOR * totalAssets == totalSupply * targetLiquidity` (this is more strict check, than needed)
7) `maxEmissionPerSecond * SCALING_FACTOR == targetLiquidity * (totalSupply / totalAssets)`
8) `maxEmissionPerSecond * SCALING_FACTOR == targetLiquidity * 100` (worst case)
9) `maxEmissionPerSecond == targetLiquidity / 1e16`

If `maxEmissionPerSecond` is less than `targetLiquidity / 1e16`, then calculations could lose precision (rounding to zero). However, this is addressed by hard requirement 3.

## `Flat` - zero `indexIncrease` check

1) `indexIncrease = maxEmissionPerSecond * 1e18 * 8 / 10 * 1 / totalSupply` (should be equal to at least 1)
2) `totalSupply / totalAssets = 100` (worst case)
3) `totalSupply = 100 * totalAssets`
4) `totalAssets / targetLiquidity = 10` (worst case)
5) `totalAssets = 10 * targetLiquidity`
6) `totalSupply = 100 * 10 * targetLiquidity`
7) `indexIncrease = maxEmissionPerSecond * 1e18 * 8 / 10 / (1000 * targetLiquidity)`
8) `maxEmissionPerSecond * 8 / 10 * 1e18 >= 1000 * targetLiquidity`
9) `maxEmissionPerSecond >= targetLiquidity / 8e14`

If `maxEmissionPerSecond` exceeds `targetLiquidity / 8e14`, our calculations should be precise (as per hard requirement 3).

## `LinearDecreaseCurve` - zero `indexIncrease` check

Since both the `Flat` and `SlopeCurve` sectors should calculate precisely enough, the `LinearDecreaseCurve` should also do so. This is because the emission in the `LinearDecreaseCurve` is bounded between `maxEmissionPerSecond` and `flatEmission`, both of which have been shown to meet the required precision.

## Reward distribution requirements

The maximum value for `maxEmissionPerSecond` is `1000 * 1e18`.

* Calculating the number of tokens that can be distributed per year: `1000 * 60 * 60 * 24 * 365 ≈ 31,536,000,000`. This means approximately *31.54 billion tokens per year*.
* If the price of the reward token is at least 0.01 USD, the total value of rewards would be approximately *315.36 million USD annually*.

Assuming the market size of `stk` could represent about 5-10% of the total market size within the Pool, and the estimated APY should remain in the range of 5-10%, this volume of rewards should be sufficient for nearly any market.
