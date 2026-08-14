// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import 'forge-std/Test.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';

import {IRewardsStructs} from '../../../src/contracts/rewards/interfaces/IRewardsStructs.sol';
import {IUmbrellaConfigurationV4} from '../../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {IUmbrellaStkManager} from '../../../src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol';

import {RewardsController} from '../../../src/contracts/rewards/RewardsController.sol';
import {StakeToken} from '../../../src/contracts/stakeToken/StakeToken.sol';
import {UmbrellaStakeToken} from '../../../src/contracts/stakeToken/UmbrellaStakeToken.sol';
import {UmbrellaSpoke} from '../../../src/contracts/umbrella/UmbrellaSpoke.sol';

import {MockHub} from './mocks/MockHub.sol';
import {MockOracleWithDecimals} from './mocks/MockOracleWithDecimals.sol';

import {MockERC20_6_Decimals} from '../../rewards/utils/mock/MockERC20_6_Decimals.sol';
import {MockERC20_18_Decimals} from '../../rewards/utils/mock/MockERC20_18_Decimals.sol';

/**
 * @notice Exposes the internal deficit setters, so that the desynchronized states which the `Hub` and
 * `UmbrellaSpoke` are expected to survive can be reproduced without a matching `Hub` state.
 */
contract UmbrellaSpokeHarness is UmbrellaSpoke {
  function setPendingDeficit(address hub, uint256 assetId, address spoke, uint256 amount) external {
    _setPendingDeficit(hub, assetId, spoke, amount);
  }

  function setDeficitOffsetUnchecked(
    address hub,
    uint256 assetId,
    address spoke,
    uint256 amount
  ) external {
    _setDeficitOffset(hub, assetId, spoke, amount);
  }
}

abstract contract UmbrellaSpokeBaseTest is Test {
  address public defaultAdmin = vm.addr(0x1000);

  address public user = vm.addr(0x3000);
  address public someone = vm.addr(0x4000);

  address public collector = vm.addr(0x6000);

  address public spokeA = vm.addr(0x7000);
  address public spokeB = vm.addr(0x7001);
  address public unlistedSpoke = vm.addr(0x7002);
  address public tokenizationSpoke = vm.addr(0x7003);

  MockERC20_6_Decimals public underlying6Decimals;
  MockERC20_6_Decimals public anotherUnderlying6Decimals;
  MockERC20_18_Decimals public underlying18Decimals;

  UmbrellaStakeToken public stakeWith6Decimals;
  UmbrellaStakeToken public stakeWith18Decimals;

  UmbrellaStakeToken public unusedStake;

  RewardsController public rewardsController;
  UmbrellaSpokeHarness public umbrella;

  MockHub public hub;
  MockHub public anotherHub;

  TransparentProxyFactory transparentProxyFactory;
  UmbrellaStakeToken umbrellaStakeTokenImpl;

  uint256 public defaultCooldown = 2 weeks;
  uint256 public defaultUnstakeWindow = 2 days;

  uint256 public constant ASSET_6_DECIMALS = 0;
  uint256 public constant ASSET_18_DECIMALS = 1;
  uint256 public constant UNLISTED_ASSET = 2;

  uint256 public constant ORACLE_PRICE = 1e8;
  uint8 public constant ORACLE_DECIMALS = 8;

  bytes32 public constant COVERAGE_MANAGER_ROLE = keccak256('COVERAGE_MANAGER_ROLE');
  bytes32 public constant RESCUE_GUARDIAN_ROLE = keccak256('RESCUE_GUARDIAN_ROLE');
  bytes32 public constant PAUSE_GUARDIAN_ROLE = keccak256('PAUSE_GUARDIAN_ROLE');
  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  function setUp() public virtual {
    transparentProxyFactory = new TransparentProxyFactory();

    underlying6Decimals = new MockERC20_6_Decimals('M6', 'M6');
    anotherUnderlying6Decimals = new MockERC20_6_Decimals('AM6', 'AM6');
    underlying18Decimals = new MockERC20_18_Decimals('M18', 'M18');

    RewardsController rewardsControllerImpl = new RewardsController();
    rewardsController = RewardsController(
      transparentProxyFactory.create(
        address(rewardsControllerImpl),
        defaultAdmin,
        abi.encodeWithSelector(RewardsController.initialize.selector, defaultAdmin)
      )
    );
    umbrellaStakeTokenImpl = new UmbrellaStakeToken(rewardsController);

    unusedStake = UmbrellaStakeToken(
      transparentProxyFactory.create(
        address(umbrellaStakeTokenImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          UmbrellaStakeToken.initialize.selector,
          address(underlying6Decimals),
          'Unused 6 decimals',
          'U6',
          address(defaultAdmin),
          defaultCooldown,
          defaultUnstakeWindow
        )
      )
    );

    UmbrellaSpokeHarness umbrellaImpl = new UmbrellaSpokeHarness();

    umbrella = UmbrellaSpokeHarness(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          UmbrellaSpoke.initialize.selector,
          defaultAdmin,
          collector,
          umbrellaStakeTokenImpl,
          address(transparentProxyFactory)
        )
      )
    );

    _createStakeTokens();
    _createHubs();
  }

  function _createStakeTokens() internal {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](2);

    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying6Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'v1'
    });

    stakeSetups[1] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying18Decimals),
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: 'v1'
    });

    vm.prank(defaultAdmin);
    address[] memory addresses = umbrella.createStakeTokens(stakeSetups);

    stakeWith6Decimals = UmbrellaStakeToken(addresses[0]);
    stakeWith18Decimals = UmbrellaStakeToken(addresses[1]);
  }

  function _createStakeToken(
    address stakeUnderlying,
    string memory suffix
  ) internal returns (address) {
    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);

    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: stakeUnderlying,
      cooldown: defaultCooldown,
      unstakeWindow: defaultUnstakeWindow,
      suffix: suffix
    });

    vm.prank(defaultAdmin);
    return umbrella.createStakeTokens(stakeSetups)[0];
  }

  function _createHubs() internal {
    hub = new MockHub();
    hub.listAsset(ASSET_6_DECIMALS, address(underlying6Decimals), 6);
    hub.listAsset(ASSET_18_DECIMALS, address(underlying18Decimals), 18);

    anotherHub = new MockHub();
    anotherHub.listAsset(ASSET_6_DECIMALS, address(anotherUnderlying6Decimals), 6);

    // a deficit is covered through the `hub`, so `Umbrella` has to be a `spoke` of every covered pair
    hub.setSpokeListed(ASSET_6_DECIMALS, address(umbrella), true);
    hub.setSpokeListed(ASSET_18_DECIMALS, address(umbrella), true);
    anotherHub.setSpokeListed(ASSET_6_DECIMALS, address(umbrella), true);

    // every `hub` starts with the liquidity of a tokenization spoke, out of which the deficit is carved
    _seedHubLiquidity(hub, ASSET_6_DECIMALS, address(underlying6Decimals), 1_000_000 * 1e6);
    _seedHubLiquidity(hub, ASSET_18_DECIMALS, address(underlying18Decimals), 1_000_000 * 1e18);
    _seedHubLiquidity(
      anotherHub,
      ASSET_6_DECIMALS,
      address(anotherUnderlying6Decimals),
      1_000_000 * 1e6
    );
  }

  function _seedHubLiquidity(
    MockHub targetHub,
    uint256 assetId,
    address token,
    uint256 amount
  ) internal {
    MockERC20_6_Decimals(token).mint(address(targetHub), amount);
    targetHub.seedSpokeShares(assetId, tokenizationSpoke, amount);
  }

  function _newOracle(int256 price, uint8 priceDecimals) internal returns (address) {
    return address(new MockOracleWithDecimals(price, priceDecimals));
  }

  /// @dev Both oracles quote 1 unit of the asset and 1 unit of the stake underlying at the same price,
  /// so that the amount slashed matches the deficit covered
  function _setUpOracles() internal returns (address assetOracle, address stakeUnderlyingOracle) {
    return (
      _newOracle(int256(ORACLE_PRICE), ORACLE_DECIMALS),
      _newOracle(int256(ORACLE_PRICE), ORACLE_DECIMALS)
    );
  }

  function _slashingConfigs(
    address targetHub,
    uint256 assetId,
    address umbrellaStake,
    uint256 liquidationFee
  ) internal returns (IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory) {
    (address assetOracle, address stakeUnderlyingOracle) = _setUpOracles();

    return
      _slashingConfigs(
        targetHub,
        assetId,
        umbrellaStake,
        liquidationFee,
        assetOracle,
        stakeUnderlyingOracle
      );
  }

  function _slashingConfigs(
    address targetHub,
    uint256 assetId,
    address umbrellaStake,
    uint256 liquidationFee,
    address assetOracle,
    address stakeUnderlyingOracle
  ) internal pure returns (IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs) {
    configs = new IUmbrellaConfigurationV4.SlashingConfigUpdate[](1);
    configs[0] = IUmbrellaConfigurationV4.SlashingConfigUpdate({
      hub: targetHub,
      assetId: assetId,
      umbrellaStake: umbrellaStake,
      liquidationFee: liquidationFee,
      assetOracle: assetOracle,
      umbrellaStakeUnderlyingOracle: stakeUnderlyingOracle
    });
  }

  function _removalPairs(
    address targetHub,
    uint256 assetId,
    address umbrellaStake
  ) internal pure returns (IUmbrellaConfigurationV4.SlashingConfigRemoval[] memory removals) {
    removals = new IUmbrellaConfigurationV4.SlashingConfigRemoval[](1);
    removals[0] = IUmbrellaConfigurationV4.SlashingConfigRemoval({
      hub: targetHub,
      assetId: assetId,
      umbrellaStake: umbrellaStake
    });
  }

  function _coverages(
    address targetHub,
    uint256 assetId,
    address spoke
  ) internal pure returns (IUmbrellaConfigurationV4.SpokeCoverage[] memory coverages) {
    coverages = new IUmbrellaConfigurationV4.SpokeCoverage[](1);
    coverages[0] = IUmbrellaConfigurationV4.SpokeCoverage({
      hub: targetHub,
      assetId: assetId,
      spoke: spoke
    });
  }

  /// @dev Sets up the default coverage of the 6 decimals asset: one `SlashingConfig` and one listed `spoke`
  function _setUpDefaultCoverage() internal {
    _updateSlashingConfigs(
      _slashingConfigs(address(hub), ASSET_6_DECIMALS, address(stakeWith6Decimals), 0)
    );

    _listAndCoverSpoke(address(hub), ASSET_6_DECIMALS, spokeA);
  }

  /// @dev Kept separate from the array creation, which deploys the oracles and would consume the prank
  function _updateSlashingConfigs(
    IUmbrellaConfigurationV4.SlashingConfigUpdate[] memory configs
  ) internal {
    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  function _listAndCoverSpoke(address targetHub, uint256 assetId, address spoke) internal {
    MockHub(targetHub).setSpokeListed(assetId, spoke, true);

    IUmbrellaConfigurationV4.SpokeCoverage[] memory coverages = _coverages(
      targetHub,
      assetId,
      spoke
    );

    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(coverages);
  }

  function _setUpRewardsController(address stakeToken) internal {
    IRewardsStructs.RewardSetupConfig[] memory empty = new IRewardsStructs.RewardSetupConfig[](0);
    uint256 targetLiquidity = 1_000_000 * 10 ** IERC20Metadata(stakeToken).decimals();

    vm.prank(defaultAdmin);
    rewardsController.configureAssetWithRewards(stakeToken, targetLiquidity, empty);
  }

  function _depositToStake(address stake, address depositor, uint256 amount) internal {
    deal(StakeToken(stake).asset(), depositor, amount);

    vm.startPrank(depositor);
    IERC20(StakeToken(stake).asset()).approve(stake, amount);
    StakeToken(stake).deposit(amount, depositor);
    vm.stopPrank();
  }

  /// @dev Makes the `stake` slashable up to `amount` of its underlying
  function _fillStake(address stake, uint256 amount) internal {
    _setUpRewardsController(stake);
    _depositToStake(stake, user, amount);
  }

  /// @dev Funds the coverage manager and approves `Umbrella` to pull the funds
  function _fundCoverageManager(address token, uint256 amount) internal {
    deal(token, defaultAdmin, amount);

    vm.prank(defaultAdmin);
    IERC20(token).approve(address(umbrella), amount);
  }
}
