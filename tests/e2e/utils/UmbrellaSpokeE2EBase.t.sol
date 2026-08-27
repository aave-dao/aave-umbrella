// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import 'forge-std/Test.sol';

import {AccessManager} from 'aave-v4/dependencies/openzeppelin/AccessManager.sol';
import {AssetInterestRateStrategy, IAssetInterestRateStrategy} from 'aave-v4/hub/AssetInterestRateStrategy.sol';
import {HubInstance} from 'aave-v4/hub/instances/HubInstance.sol';
import {IHub} from 'aave-v4/hub/interfaces/IHub.sol';
import {Roles} from 'aave-v4/deployments/utils/libraries/Roles.sol';

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {TransparentProxyFactory} from 'solidity-utils/contracts/transparent-proxy/TransparentProxyFactory.sol';

import {IRewardsStructs} from '../../../src/contracts/rewards/interfaces/IRewardsStructs.sol';
import {IUmbrellaConfigurationV4} from '../../../src/contracts/umbrella/interfaces/IUmbrellaConfigurationV4.sol';
import {IUmbrellaStkManager} from '../../../src/contracts/umbrella/interfaces/IUmbrellaStkManager.sol';

import {RewardsController} from '../../../src/contracts/rewards/RewardsController.sol';
import {UmbrellaStakeToken} from '../../../src/contracts/stakeToken/UmbrellaStakeToken.sol';
import {UmbrellaSpoke} from '../../../src/contracts/umbrella/UmbrellaSpoke.sol';

import {MockOracleWithDecimals} from '../../umbrella/utils/mocks/MockOracleWithDecimals.sol';
import {MockERC20_6_Decimals} from '../../rewards/utils/mock/MockERC20_6_Decimals.sol';

import {TestSpoke} from './TestSpoke.sol';

/**
 * @notice Deploys a real Aave V4 `Hub` next to a real `Umbrella` deployment and wires them the way a
 * production setup does: `UmbrellaSpoke` is an active `spoke` of the `hub` holding the deficit eliminator role.
 */
abstract contract UmbrellaSpokeE2EBaseTest is Test {
  address public defaultAdmin = vm.addr(0x1000);
  address public user = vm.addr(0x3000);
  address public borrower = vm.addr(0x5000);
  address public collector = vm.addr(0x6000);
  address public feeReceiver = vm.addr(0x8000);

  uint256 public constant SEEDED_LIQUIDITY = 1_000_000 * 1e6;
  uint256 public constant ORACLE_PRICE = 1e8;
  uint8 public constant ORACLE_DECIMALS = 8;

  bytes32 public constant COVERAGE_MANAGER_ROLE = keccak256('COVERAGE_MANAGER_ROLE');
  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  AccessManager public accessManager;
  IHub public hub;
  AssetInterestRateStrategy public irStrategy;
  uint256 public assetId;

  TestSpoke public lendingSpoke;
  TestSpoke public secondSpoke;

  MockERC20_6_Decimals public underlying;
  RewardsController public rewardsController;
  UmbrellaStakeToken public stakeToken;
  UmbrellaSpoke public umbrella;

  TransparentProxyFactory public transparentProxyFactory;

  function setUp() public virtual {
    transparentProxyFactory = new TransparentProxyFactory();
    underlying = new MockERC20_6_Decimals('M6', 'M6');

    _deployUmbrella();
    _deployHub();
    _registerSpokes();
    _configureCoverage();

    // the `hub` starts with the liquidity of a supplying spoke, out of which every deficit is carved
    underlying.mint(address(lendingSpoke), SEEDED_LIQUIDITY);
    lendingSpoke.add(assetId, SEEDED_LIQUIDITY);
  }

  function _deployUmbrella() internal {
    RewardsController rewardsControllerImpl = new RewardsController();
    rewardsController = RewardsController(
      transparentProxyFactory.create(
        address(rewardsControllerImpl),
        defaultAdmin,
        abi.encodeWithSelector(RewardsController.initialize.selector, defaultAdmin)
      )
    );

    UmbrellaStakeToken umbrellaStakeTokenImpl = new UmbrellaStakeToken(rewardsController);
    UmbrellaSpoke umbrellaImpl = new UmbrellaSpoke();

    umbrella = UmbrellaSpoke(
      transparentProxyFactory.create(
        address(umbrellaImpl),
        defaultAdmin,
        abi.encodeWithSelector(
          UmbrellaSpoke.initialize.selector,
          defaultAdmin,
          collector,
          address(umbrellaStakeTokenImpl),
          address(transparentProxyFactory)
        )
      )
    );

    IUmbrellaStkManager.StakeTokenSetup[]
      memory stakeSetups = new IUmbrellaStkManager.StakeTokenSetup[](1);

    stakeSetups[0] = IUmbrellaStkManager.StakeTokenSetup({
      underlying: address(underlying),
      cooldown: 2 weeks,
      unstakeWindow: 2 days,
      suffix: 'v1'
    });

    vm.prank(defaultAdmin);
    stakeToken = UmbrellaStakeToken(umbrella.createStakeTokens(stakeSetups)[0]);
  }

  function _deployHub() internal {
    accessManager = new AccessManager(address(this));

    HubInstance hubImpl = new HubInstance();
    hub = IHub(
      transparentProxyFactory.create(
        address(hubImpl),
        defaultAdmin,
        abi.encodeWithSelector(HubInstance.initialize.selector, address(accessManager))
      )
    );

    irStrategy = new AssetInterestRateStrategy(address(hub));

    accessManager.setTargetFunctionRole(
      address(hub),
      Roles.getHubConfiguratorRoleSelectors(),
      Roles.HUB_CONFIGURATOR_ROLE
    );
    accessManager.grantRole(Roles.HUB_CONFIGURATOR_ROLE, address(this), 0);

    // `eliminateDeficit` is permissioned on the `Hub`, so `Umbrella` needs the role to cover a deficit
    accessManager.setTargetFunctionRole(
      address(hub),
      Roles.getHubDeficitEliminatorRoleSelectors(),
      Roles.HUB_DEFICIT_ELIMINATOR_ROLE
    );
    accessManager.grantRole(Roles.HUB_DEFICIT_ELIMINATOR_ROLE, address(umbrella), 0);

    assetId = hub.addAsset({
      underlying: address(underlying),
      decimals: 6,
      feeReceiver: feeReceiver,
      irStrategy: address(irStrategy),
      irData: abi.encode(
        IAssetInterestRateStrategy.InterestRateData({
          optimalUsageRatio: 90_00,
          baseDrawnRate: 5_00,
          rateGrowthBeforeOptimal: 5_00,
          rateGrowthAfterOptimal: 5_00
        })
      )
    });
  }

  function _registerSpokes() internal {
    lendingSpoke = new TestSpoke(hub);
    secondSpoke = new TestSpoke(hub);

    // the fee receiver is registered as a spoke by `addAsset` itself
    _addSpoke(address(lendingSpoke));
    _addSpoke(address(secondSpoke));
    _addSpoke(address(umbrella));
  }

  function _addSpoke(address spoke) internal {
    hub.addSpoke(
      assetId,
      spoke,
      IHub.SpokeConfig({
        addCap: hub.MAX_ALLOWED_SPOKE_CAP(),
        drawCap: hub.MAX_ALLOWED_SPOKE_CAP(),
        riskPremiumThreshold: hub.MAX_RISK_PREMIUM_THRESHOLD(),
        active: true,
        halted: false
      })
    );
  }

  function _configureCoverage() internal {
    IUmbrellaConfigurationV4.SlashingConfigUpdate[]
      memory configs = new IUmbrellaConfigurationV4.SlashingConfigUpdate[](1);

    configs[0] = IUmbrellaConfigurationV4.SlashingConfigUpdate({
      hub: address(hub),
      assetId: assetId,
      umbrellaStake: address(stakeToken),
      liquidationFee: 0,
      assetOracle: address(new MockOracleWithDecimals(int256(ORACLE_PRICE), ORACLE_DECIMALS)),
      umbrellaStakeUnderlyingOracle: address(
        new MockOracleWithDecimals(int256(ORACLE_PRICE), ORACLE_DECIMALS)
      )
    });

    vm.prank(defaultAdmin);
    umbrella.updateSlashingConfigs(configs);
  }

  /// @dev Draws liquidity and writes it off, producing a real deficit of `spoke` on the `hub`
  function _reportDeficit(TestSpoke spoke, uint256 amount) internal {
    spoke.draw(assetId, amount, borrower);
    spoke.reportDeficit(assetId, amount);
  }

  function _coverages(
    address spoke
  ) internal view returns (IUmbrellaConfigurationV4.SpokeCoverage[] memory coverages) {
    coverages = new IUmbrellaConfigurationV4.SpokeCoverage[](1);
    coverages[0] = IUmbrellaConfigurationV4.SpokeCoverage({
      hub: address(hub),
      assetId: assetId,
      spoke: spoke
    });
  }

  function _coverSpoke(address spoke) internal {
    vm.prank(defaultAdmin);
    umbrella.addCoveredSpokes(_coverages(spoke));
  }

  function _uncoverSpoke(address spoke) internal {
    vm.prank(defaultAdmin);
    umbrella.removeCoveredSpokes(_coverages(spoke));
  }

  function _fillStake(uint256 amount) internal {
    IRewardsStructs.RewardSetupConfig[] memory empty = new IRewardsStructs.RewardSetupConfig[](0);

    vm.prank(defaultAdmin);
    rewardsController.configureAssetWithRewards(address(stakeToken), 1_000_000 * 1e6, empty);

    underlying.mint(user, amount);

    vm.startPrank(user);
    underlying.approve(address(stakeToken), amount);
    stakeToken.deposit(amount, user);
    vm.stopPrank();
  }

  function _fundCoverageManager(uint256 amount) internal {
    underlying.mint(defaultAdmin, amount);

    vm.prank(defaultAdmin);
    underlying.approve(address(umbrella), amount);
  }

  function _spokeDeficit(address spoke) internal view returns (uint256) {
    return _fromRayUp(hub.getSpokeDeficitRay(assetId, spoke));
  }

  function _fromRayUp(uint256 amountRay) internal pure returns (uint256) {
    return amountRay / 1e27 + (amountRay % 1e27 == 0 ? 0 : 1);
  }
}
