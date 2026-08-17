// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import './SlashingRobot.t.sol';
import {GelatoSlashingRobot} from '../../src/contracts/automation/GelatoSlashingRobot.sol';

contract GelatoSlashingRobot_Test is SlashingRobot_Test {

  function setUp() public virtual override {
    super.setUp();
    robot = SlashingRobot(address(new GelatoSlashingRobot(address(umbrella), ROBOT_GUARDIAN)));
  }

  function _checkAndPerformAutomation() internal virtual override returns (bool) {
    (bool shouldRunKeeper, bytes memory encodedPerformData) = robot.checkUpkeep('');
    if (shouldRunKeeper) {
      (bool status, ) = address(robot).call(encodedPerformData);
      assertTrue(status, 'Perform Upkeep Failed');
    }
    return shouldRunKeeper;
  }
}
