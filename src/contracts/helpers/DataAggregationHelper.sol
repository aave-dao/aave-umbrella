// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

import {IRescuableBase, RescuableBase} from 'solidity-utils/contracts/utils/RescuableBase.sol';
import {Rescuable} from 'solidity-utils/contracts/utils/Rescuable.sol';

import {IERC4626StataToken} from 'aave-v3-origin/contracts/extensions/stata-token/interfaces/IERC4626StataToken.sol';
import {IStataTokenV2} from 'aave-v3-origin/contracts/extensions/stata-token/interfaces/IStataTokenV2.sol';
import {IAaveOracle} from 'aave-v3-origin/contracts/interfaces/IAaveOracle.sol';
import {IAToken} from 'aave-v3-origin/contracts/interfaces/IAToken.sol';

import {IUmbrellaConfiguration} from '../umbrella/interfaces/IUmbrellaConfiguration.sol';
import {IUmbrellaStakeToken} from '../stakeToken/interfaces/IUmbrellaStakeToken.sol';
import {IRewardsController} from '../rewards/interfaces/IRewardsController.sol';
import {IStakeToken} from '../stakeToken/interfaces/IStakeToken.sol';
import {IUmbrella} from '../umbrella/interfaces/IUmbrella.sol';

/**
 * @title DataAggregationHelper
 * @notice DataAggregationHelper is a utility contract designed to help getting all necessary data for frontend.
 * @author BGD labs
 */
contract DataAggregationHelper is Ownable, Rescuable {
  IRewardsController public immutable REWARDS_CONTROLLER;

  enum TokenType {
    None,
    Token,
    AToken,
    StataToken
  }

  struct StakeTokenData {
    TokenData stakeTokenData;
    uint256 totalAssets;
    uint256 targetLiquidity;
    bool isStakeConfigured;
    RewardTokenData[] rewardsTokenData;
  }

  struct RewardTokenData {
    TokenData rewardTokenData;
    uint256 maxEmissionPerSecond;
    uint256 distributionEnd;
  }

  struct TokenRouteData {
    address stakeToken;
    TokenFromRoute[] tokensFromRoute;
  }

  struct TokenFromRoute {
    TokenType typeOfToken;
    TokenData tokenData;
  }

  struct TokenData {
    address token;
    uint256 price;
    string name;
    string symbol;
    uint8 decimals;
  }

  struct StakeTokenUserData {
    address stakeToken;
    uint256 stakeUserBalance;
    RewardTokenUserData[] rewardsTokenUserData;
  }

  struct RewardTokenUserData {
    address reward;
    uint256 currentReward;
  }

  struct TokenRouteBalances {
    address stakeToken;
    BalanceOfTokenFromRoute[] balancesOfRouteTokens;
  }

  struct BalanceOfTokenFromRoute {
    TokenType typeOfToken;
    address token;
    uint256 userBalance;
  }

  error ZeroAddress();

  constructor(address rewardsController_, address owner_) Ownable(owner_) {
    require(rewardsController_ != address(0), ZeroAddress());

    REWARDS_CONTROLLER = IRewardsController(rewardsController_);
  }

  function getAllAggregatedData(
    IUmbrella umbrella,
    IAaveOracle aaveOracle,
    address user
  )
    external
    view
    returns (
      StakeTokenData[] memory,
      TokenRouteData[] memory,
      StakeTokenUserData[] memory,
      TokenRouteBalances[] memory
    )
  {
    address[] memory stakeTokens = IUmbrella(umbrella).getStkTokens();

    StakeTokenData[] memory tokenData = _getTokenAggregatedData(stakeTokens, umbrella, aaveOracle);
    TokenRouteData[] memory tokenRouteData = _getTokensRouteData(stakeTokens, aaveOracle);

    StakeTokenUserData[] memory userData;
    TokenRouteBalances[] memory userBalances;

    if (user != address(0)) {
      userData = _getUserAggregatedData(stakeTokens, user);
      userBalances = _getUserBalancesFromRouteTokens(stakeTokens, user);
    }

    return (tokenData, tokenRouteData, userData, userBalances);
  }

  function getTokensAggregatedData(
    IUmbrella umbrella,
    IAaveOracle aaveOracle
  ) external view returns (StakeTokenData[] memory) {
    address[] memory stakeTokens = IUmbrella(umbrella).getStkTokens();

    return _getTokenAggregatedData(stakeTokens, umbrella, aaveOracle);
  }

  function getTokensRouteData(
    IUmbrella umbrella,
    IAaveOracle aaveOracle
  ) external view returns (TokenRouteData[] memory) {
    address[] memory stakeTokens = IUmbrella(umbrella).getStkTokens();

    return _getTokensRouteData(stakeTokens, aaveOracle);
  }

  function getUserAggregatedData(
    IUmbrella umbrella,
    address user
  ) external view returns (StakeTokenUserData[] memory) {
    address[] memory stakeTokens = IUmbrella(umbrella).getStkTokens();

    return _getUserAggregatedData(stakeTokens, user);
  }

  function getUserBalancesFromRouteTokens(
    IUmbrella umbrella,
    address user
  ) external view returns (TokenRouteBalances[] memory) {
    address[] memory stakeTokens = IUmbrella(umbrella).getStkTokens();

    return _getUserBalancesFromRouteTokens(stakeTokens, user);
  }

  function whoCanRescue() public view override returns (address) {
    return owner();
  }

  function maxRescue(
    address
  ) public pure override(IRescuableBase, RescuableBase) returns (uint256) {
    return type(uint256).max;
  }

  function _getTokenAggregatedData(
    address[] memory stakeTokens,
    IUmbrella umbrella,
    IAaveOracle aaveOracle
  ) internal view returns (StakeTokenData[] memory) {
    StakeTokenData[] memory stakeTokensData = new StakeTokenData[](stakeTokens.length);
    IUmbrellaConfiguration.StakeTokenData memory stakeConfig;

    for (uint256 i; i < stakeTokens.length; ++i) {
      stakeConfig = umbrella.getStakeTokenData(stakeTokens[i]);

      stakeTokensData[i].totalAssets = IUmbrellaStakeToken(stakeTokens[i]).totalAssets();
      stakeTokensData[i].targetLiquidity = REWARDS_CONTROLLER
        .getAssetData(stakeTokens[i])
        .targetLiquidity;
      stakeTokensData[i].isStakeConfigured = stakeConfig.reserve != address(0);

      uint256 stakePrice;
      if (stakeConfig.underlyingOracle != address(0)) {
        // ask for a price directly, cause token configuration was already initialized at least once
        stakePrice = uint256(IUmbrellaStakeToken(stakeTokens[i]).latestAnswer());
      } else if (stakeConfig.underlyingOracle == address(0) && stakeConfig.reserve == address(0)) {
        // stake token wasn't included in config yet, so it's price is equal to price of underlying
        address underlying = IStakeToken(stakeTokens[i]).asset();

        (bool isStata, ) = _stataTokenCheck(underlying);

        _tryGetUnderlyingPrice(underlying, aaveOracle, isStata);
      } else {
        // unreachable code in the current version, will set max in case this could happen in future
        stakePrice = type(uint256).max;
      }

      stakeTokensData[i].stakeTokenData = _buildTokenStruct(stakeTokens[i], stakePrice, 0);

      address[] memory rewards = REWARDS_CONTROLLER.getAllRewards(stakeTokens[i]);
      stakeTokensData[i].rewardsTokenData = new RewardTokenData[](rewards.length);

      for (uint256 j; j < rewards.length; ++j) {
        IRewardsController.RewardDataExternal memory rewardData = REWARDS_CONTROLLER.getRewardData(
          stakeTokens[i],
          rewards[j]
        );

        stakeTokensData[i].rewardsTokenData[j].maxEmissionPerSecond = rewardData
          .maxEmissionPerSecond;
        stakeTokensData[i].rewardsTokenData[j].distributionEnd = rewardData.distributionEnd;

        // Top reward cases:
        // 1) aToken
        // 2) Token
        // 3) StataToken (should be only in rare cases)
        // return max otherwise, cause source of price isn't known
        address tokenToAskPriceFor = rewards[j];
        uint256 rewardPrice;

        // check if reward is `aToken`
        (bool success, bytes memory data) = rewards[j].staticcall(
          abi.encodeWithSelector(IAToken.UNDERLYING_ASSET_ADDRESS.selector)
        );

        if (success) {
          tokenToAskPriceFor = abi.decode(data, (address));
        }

        // Token || aToken
        // price of `aToken` is equal to price of `Token`, cause backed 1-1
        try aaveOracle.getAssetPrice(tokenToAskPriceFor) returns (uint256 reservePrice) {
          rewardPrice = reservePrice;
        } catch {
          // Check for `StataToken`, if this `Stata` isn't even from this `Pool` it will anyway return actual price
          (success, data) = rewards[j].staticcall(
            abi.encodeWithSelector(IERC4626StataToken.latestAnswer.selector)
          );
          // if success is false, then source of price isn't known, it's a `Token/aToken` or another type of `Token` except `StataToken`, that isn't listed on this concrete Aave `Pool`
          // Don't make revert here, cause it's a normal situation and this price should be get from somewhere else
          rewardPrice = success ? abi.decode(data, (uint256)) : type(uint256).max;
        }

        stakeTokensData[i].rewardsTokenData[j].rewardTokenData = _buildTokenStruct(
          rewards[j],
          rewardPrice,
          0
        );
      }
    }

    return stakeTokensData;
  }

  function _getTokensRouteData(
    address[] memory stakeTokens,
    IAaveOracle aaveOracle
  ) internal view returns (TokenRouteData[] memory) {
    TokenRouteData[] memory tokenRouteData = new TokenRouteData[](stakeTokens.length);

    for (uint256 i; i < stakeTokens.length; ++i) {
      tokenRouteData[i].stakeToken = stakeTokens[i];
      tokenRouteData[i].tokensFromRoute = _getTokensFromRoute(stakeTokens[i], aaveOracle);
    }

    return tokenRouteData;
  }

  function _getUserAggregatedData(
    address[] memory stakeTokens,
    address user
  ) internal view returns (StakeTokenUserData[] memory) {
    StakeTokenUserData[] memory stakeTokensUserData = new StakeTokenUserData[](stakeTokens.length);

    for (uint256 i; i < stakeTokens.length; ++i) {
      stakeTokensUserData[i].stakeToken = stakeTokens[i];
      stakeTokensUserData[i].stakeUserBalance = IERC20(stakeTokens[i]).balanceOf(user);

      address[] memory rewards = REWARDS_CONTROLLER.getAllRewards(stakeTokens[i]);
      stakeTokensUserData[i].rewardsTokenUserData = new RewardTokenUserData[](rewards.length);

      for (uint256 j; j < rewards.length; ++j) {
        stakeTokensUserData[i].rewardsTokenUserData[j] = RewardTokenUserData({
          reward: rewards[j],
          currentReward: REWARDS_CONTROLLER.calculateCurrentUserReward(
            stakeTokens[i],
            rewards[j],
            user
          )
        });
      }
    }

    return stakeTokensUserData;
  }

  function _getUserBalancesFromRouteTokens(
    address[] memory stakeTokens,
    address user
  ) internal view returns (TokenRouteBalances[] memory) {
    TokenRouteBalances[] memory tokenRouteBalances = new TokenRouteBalances[](stakeTokens.length);

    for (uint256 i; i < stakeTokens.length; ++i) {
      tokenRouteBalances[i].stakeToken = stakeTokens[i];
      tokenRouteBalances[i].balancesOfRouteTokens = _getBalancesFromRoute(stakeTokens[i], user);
    }

    return tokenRouteBalances;
  }

  function _getTokensFromRoute(
    address stakeToken,
    IAaveOracle aaveOracle
  ) internal view returns (TokenFromRoute[] memory) {
    uint8 decimals = IERC20Metadata(stakeToken).decimals();

    address underlyingOfStakeToken = IStakeToken(stakeToken).asset();

    (bool isStata, address aToken) = _stataTokenCheck(underlyingOfStakeToken);

    TokenFromRoute[] memory tokens = new TokenFromRoute[](isStata ? 3 : 1);

    tokens[0] = TokenFromRoute({
      typeOfToken: isStata ? TokenType.StataToken : TokenType.Token,
      tokenData: _buildTokenStruct(
        underlyingOfStakeToken,
        _tryGetUnderlyingPrice(underlyingOfStakeToken, aaveOracle, isStata),
        decimals
      )
    });

    if (isStata) {
      address token = IStataTokenV2(underlyingOfStakeToken).asset();

      uint256 price = aaveOracle.getAssetPrice(token);

      tokens[1] = TokenFromRoute({
        typeOfToken: TokenType.AToken,
        tokenData: _buildTokenStruct(aToken, price, decimals)
      });

      tokens[2] = TokenFromRoute({
        typeOfToken: TokenType.Token,
        tokenData: _buildTokenStruct(token, price, decimals)
      });
    }

    return tokens;
  }

  function _getBalancesFromRoute(
    address stakeToken,
    address user
  ) internal view returns (BalanceOfTokenFromRoute[] memory) {
    address underlyingOfStakeToken = IStakeToken(stakeToken).asset();

    (bool isStata, address aToken) = _stataTokenCheck(underlyingOfStakeToken);

    BalanceOfTokenFromRoute[] memory balances = new BalanceOfTokenFromRoute[](isStata ? 3 : 1);

    balances[0] = BalanceOfTokenFromRoute({
      typeOfToken: isStata ? TokenType.StataToken : TokenType.Token,
      token: underlyingOfStakeToken,
      userBalance: IERC20(underlyingOfStakeToken).balanceOf(user)
    });

    if (isStata) {
      address token = IStataTokenV2(underlyingOfStakeToken).asset();

      balances[1] = BalanceOfTokenFromRoute({
        typeOfToken: TokenType.AToken,
        token: aToken,
        userBalance: IERC20(aToken).balanceOf(user)
      });

      balances[2] = BalanceOfTokenFromRoute({
        typeOfToken: TokenType.Token,
        token: token,
        userBalance: IERC20(token).balanceOf(user)
      });
    }

    return balances;
  }

  function _stataTokenCheck(address token) internal view returns (bool isStata, address aToken) {
    bytes memory data;

    (isStata, data) = address(token).staticcall(
      abi.encodeWithSelector(IERC4626StataToken.aToken.selector)
    );

    if (isStata) {
      aToken = abi.decode(data, (address));
    }

    return (isStata, aToken);
  }

  function _buildTokenStruct(
    address token,
    uint256 price,
    uint8 decimals
  ) internal view returns (TokenData memory) {
    return
      TokenData({
        token: token,
        price: price,
        name: IERC20Metadata(token).name(),
        symbol: IERC20Metadata(token).symbol(),
        decimals: decimals != 0 ? decimals : IERC20Metadata(token).decimals()
      });
  }

  function _tryGetUnderlyingPrice(
    address underlyingToken,
    IAaveOracle aaveOracle,
    bool isStata
  ) internal view returns (uint256) {
    if (isStata) {
      return uint256(IStataTokenV2(underlyingToken).latestAnswer()); // stata has `latestAnswer()`
    } else {
      try aaveOracle.getAssetPrice(underlyingToken) returns (uint256 price) {
        return price; // just token used as underlying for stake
      } catch {
        return type(uint256).max; // not standard or lp-token, which isn't listed in the `Pool` connected with `AaveOracle`
      }
    }
  }
}
