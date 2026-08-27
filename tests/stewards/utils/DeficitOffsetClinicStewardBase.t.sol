// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {IRewardsStructs} from '../../../src/contracts/rewards/interfaces/IRewardsStructs.sol';
import {IUmbrellaConfiguration} from '../../../src/contracts/umbrella/interfaces/IUmbrellaConfiguration.sol';

import {StakeToken} from '../../../src/contracts/stakeToken/StakeToken.sol';
import {DeficitOffsetClinicSteward} from '../../../src/contracts/stewards/DeficitOffsetClinicSteward.sol';

import {RescuableBase, IRescuableBase} from '../../../src/contracts/stewards/DeficitOffsetClinicSteward.sol';
import {RescuableACL, IRescuable} from '../../../src/contracts/stewards/DeficitOffsetClinicSteward.sol';

import {UmbrellaBaseTest} from '../../umbrella/utils/UmbrellaBase.t.sol';
import {MockOracle} from '../../umbrella/utils/mocks/MockOracle.sol';

abstract contract DeficitOffsetClinicStewardBase is UmbrellaBaseTest {
  DeficitOffsetClinicSteward clinicSteward;

  bytes32 public constant FINANCE_COMMITTEE_ROLE = keccak256('FINANCE_COMITTEE_ROLE');
  address financeCommittee = vm.addr(0x0900);

  function setUp() public virtual override {
    super.setUp();

    clinicSteward = new DeficitOffsetClinicSteward(
      address(umbrella),
      collector,
      defaultAdmin,
      financeCommittee
    );

    IUmbrellaConfiguration.SlashingConfigUpdate[]
      memory stakeSetups = new IUmbrellaConfiguration.SlashingConfigUpdate[](2);

    stakeSetups[0] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying6Decimals),
      umbrellaStake: address(stakeWith6Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: _setUpOracles(address(underlying6Decimals))
    });
    stakeSetups[1] = IUmbrellaConfiguration.SlashingConfigUpdate({
      reserve: address(underlying18Decimals),
      umbrellaStake: address(stakeWith18Decimals),
      liquidationFee: 0,
      umbrellaStakeUnderlyingOracle: _setUpOracles(address(underlying18Decimals))
    });

    vm.startPrank(defaultAdmin);

    umbrella.updateSlashingConfigs(stakeSetups);
    umbrella.grantRole(COVERAGE_MANAGER_ROLE, address(clinicSteward));

    vm.stopPrank();
  }

  function _setUpOracles(address reserve) internal returns (address oracle) {
    aaveOracle.setAssetPrice(reserve, 1e8);

    return address(new MockOracle(1e8));
  }
}
