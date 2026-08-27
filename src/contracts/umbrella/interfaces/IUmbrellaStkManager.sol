// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ITransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/interfaces/ITransparentProxyFactory.sol';

import {IUmbrellaConfigurationBase} from './IUmbrellaConfigurationBase.sol';

interface IUmbrellaStkManager is IUmbrellaConfigurationBase {
  struct StakeTokenSetup {
    /// @notice Address of the underlying token for which the `UmbrellaStakeToken` will be created
    address underlying;
    /// @notice Cooldown duration of the `UmbrellaStakeToken`
    uint256 cooldown;
    /// @notice Time period during which funds can be withdrawn from the `UmbrellaStakeToken`
    uint256 unstakeWindow;
    /// @notice Suffix to be added in the end to name and symbol (optional, can be empty)
    string suffix;
  }

  struct CooldownConfig {
    /// @notice `UmbrellaStakeToken` address
    address umbrellaStake;
    /// @notice Amount of seconds users have to wait between triggering the `cooldown()` and being able to withdraw funds
    uint256 newCooldown;
  }

  struct UnstakeWindowConfig {
    /// @notice `UmbrellaStakeToken` address
    address umbrellaStake;
    /// @notice Amount of seconds users have to withdraw after `cooldown`
    uint256 newUnstakeWindow;
  }

  /**
   * @notice Event is emitted when a new `UmbrellaStakeToken` is created.
   * @param umbrellaStake Address of the new `UmbrellaStakeToken`
   * @param underlying Address of the underlying token it is created for
   * @param name Name of the new `UmbrellaStakeToken`
   * @param symbol Symbol of the new `UmbrellaStakeToken`
   */
  event UmbrellaStakeTokenCreated(
    address indexed umbrellaStake,
    address indexed underlying,
    string name,
    string symbol
  );

  // DEFAULT_ADMIN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Creates new `UmbrellaStakeToken`s.
   * @param stakeTokenSetups Array of `UmbrellaStakeToken`s setup configs
   * @return stakeTokens Array of new `UmbrellaStakeToken`s addresses
   */
  function createStakeTokens(
    StakeTokenSetup[] calldata stakeTokenSetups
  ) external returns (address[] memory stakeTokens);

  /**
   * @notice Sets a new `cooldown`s (in seconds) for the specified `UmbrellaStakeToken`s.
   * @param cooldownConfigs Array of new `cooldown` configs
   */
  function setCooldownStk(CooldownConfig[] calldata cooldownConfigs) external;

  /**
   * @notice Sets a new `unstakeWindow`s (in seconds) for the specified `UmbrellaStakeToken`s.
   * @param unstakeWindowConfigs Array of new `unstakeWindow` configs
   */
  function setUnstakeWindowStk(UnstakeWindowConfig[] calldata unstakeWindowConfigs) external;

  // RESCUE_GUARDIAN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Rescue tokens sent erroneously to the contract.
   * @param stk Address of the `UmbrellaStakeToken` to rescue from
   * @param erc20Token Address of the token to rescue
   * @param to Address of the tokens receiver
   * @param amount Amount of tokens to rescue
   */
  function emergencyTokenTransferStk(
    address stk,
    address erc20Token,
    address to,
    uint256 amount
  ) external;

  /**
   * @notice Rescue native currency (e.g. Ethereum) sent erroneously to the contract.
   * @param stk Address of the `UmbrellaStakeToken` to rescue from
   * @param to Address of the tokens receiver
   * @param amount Amount of tokens to rescue
   */
  function emergencyEtherTransferStk(address stk, address to, uint256 amount) external;

  // PAUSE_GUARDIAN_ROLE
  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Pauses `UmbrellaStakeToken`.
   * @param stk Address of the `UmbrellaStakeToken` to turn pause on
   */
  function pauseStk(address stk) external;

  /**
   * @notice Unpauses `UmbrellaStakeToken`.
   * @param stk Address of the `UmbrellaStakeToken` to turn pause off
   */
  function unpauseStk(address stk) external;

  /////////////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice Predicts new `UmbrellaStakeToken`s addresses.
   * @dev Should be used only to predict new `UmbrellaStakeToken` addresses and not to calculate already deployed ones.
   * @param stakeSetups Array of `UmbrellaStakeToken`s setup configs
   * @return stakeTokens Array of new `UmbrellaStakeToken`s predicted addresses
   */
  function predictStakeTokensAddresses(
    StakeTokenSetup[] calldata stakeSetups
  ) external view returns (address[] memory);

  /**
   * @notice Returns a list of all the `UmbrellaStakeToken`s created via this `Umbrella` instance.
   * @return Array of addresses containing all the `UmbrellaStakeToken`s
   */
  function getStkTokens() external view returns (address[] memory);

  /**
   * @notice Returns true if the provided address is a `UmbrellaStakeToken` belonging to this `Umbrella` instance.
   * @return True if the token is part of this `Umbrella`, false otherwise
   */
  function isUmbrellaStkToken(address stakeToken) external view returns (bool);

  /**
   * @notice Returns the `TransparentProxyFactory` contract used to create `UmbrellaStakeToken`s.
   * @return `TransparentProxyFactory` address
   */
  function TRANSPARENT_PROXY_FACTORY() external view returns (ITransparentProxyFactory);

  /**
   * @notice Returns the `UmbrellaStakeToken` implementation used to instantiate new umbrella stake tokens.
   * @return `UmbrellaStakeToken` implementation address
   */
  function UMBRELLA_STAKE_TOKEN_IMPL() external view returns (address);

  /**
   * @notice Returns the `SUPER_ADMIN` address, which has `DEFAULT_ADMIN_ROLE` and is used to manage `UmbrellaStakeToken`s upgradability.
   * @return `SUPER_ADMIN` address
   */
  function SUPER_ADMIN() external view returns (address);
}
