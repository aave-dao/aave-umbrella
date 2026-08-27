// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';
import {Pausable} from 'openzeppelin-contracts/contracts/utils/Pausable.sol';

import {ISlashingRobot, IAutomation} from './interfaces/ISlashingRobot.sol';

import {IUmbrellaStakeToken} from '../stakeToken/interfaces/IUmbrellaStakeToken.sol';
import {IUmbrella} from '../umbrella/interfaces/IUmbrella.sol';

/**
 * @title SlashingRobot
 * @author BGD Labs
 * @notice Contract to perform automated slashing on umbrella
 * @dev Aave automation-compatible contract to:
 *      - check if reserves could be slashed
 *      - executes slashing on the reserves
 * The current version assumes basket of assets on Umbrella is disabled.
 */
contract SlashingRobot is Ownable, ISlashingRobot {
  /// @inheritdoc ISlashingRobot
  address public immutable UMBRELLA;

  /// @inheritdoc ISlashingRobot
  uint256 public constant MAX_CHECK_SIZE = 10;

  mapping(address => bool) internal _disabledReserves;

  /**
   * @param umbrella Address of the `umbrella` contract
   * @param robotGuardian Address of the robot guardian
   */
  constructor(address umbrella, address robotGuardian) Ownable(robotGuardian) {
    UMBRELLA = umbrella;
  }

  /**
   * @inheritdoc IAutomation
   * @dev run off-chain, checks if reserves should be slashed
   */
  function checkUpkeep(bytes memory) public view virtual override returns (bool, bytes memory) {
    address[] memory stkTokens = _shuffleAddresses(IUmbrella(UMBRELLA).getStkTokens());
    address[] memory reservesToSlash = new address[](stkTokens.length);
    uint256 slashCount;

    for (uint256 i; i < stkTokens.length; ++i) {
      IUmbrella.StakeTokenData memory stakeTokenData = IUmbrella(UMBRELLA).getStakeTokenData(
        stkTokens[i]
      );

      if (_canStakeBeSlashed(stakeTokenData.reserve, stkTokens[i])) {
        reservesToSlash[slashCount++] = stakeTokenData.reserve;
      }

      if (slashCount >= MAX_CHECK_SIZE) {
        break;
      }
    }

    if (slashCount != 0) {
      assembly {
        mstore(reservesToSlash, slashCount)
      }

      return (true, abi.encode(reservesToSlash));
    }

    return (false, '');
  }

  /**
   * @inheritdoc IAutomation
   * @dev executes slashing action on the `umbrella` contract for the `reserve`s.
   * If the data was not collected via `checkUpkeep`, then two checks for on stk side will be skipped,
   * however it's not fully correct use of the system.
   * If outdated data is used (as a result of frontrun or other griefing or racing keepers),
   * then the slash will be simply skipped or reverted into try-catch.
   * @param performData abi encoded addresses of the reserve assets to slash.
   */
  function performUpkeep(bytes calldata performData) external {
    address[] memory reserves = abi.decode(performData, (address[]));
    bool slashingPerformed;

    for (uint256 i; i < reserves.length; ++i) {
      if (!_checkReserve(reserves[i])) {
        continue;
      }

      try IUmbrella(UMBRELLA).slash(reserves[i]) returns (uint256 amount) {
        slashingPerformed = true;

        emit ReserveSlashed(reserves[i], amount);
      } catch {}
    }

    require(slashingPerformed, NoSlashesPerformed());
  }

  /// @inheritdoc ISlashingRobot
  function isDisabled(address reserve) public view returns (bool) {
    return _disabledReserves[reserve];
  }

  /// @inheritdoc ISlashingRobot
  function disable(address reserve, bool disabled) external onlyOwner {
    _disabledReserves[reserve] = disabled;

    emit ReserveDisabled(reserve, disabled);
  }

  /**
   * @notice Method to check if the stk could be slashed for future coverage of the `reserve` deficit.
   * @param reserve Address of the `reserve` to check if stk can be slashed for it
   * @param stkToken Address of the stk to check if it can be slashed
   * @return true if the stk could be slashed, false otherwise
   */
  function _canStakeBeSlashed(address reserve, address stkToken) internal view returns (bool) {
    bool isReserveSlashable = _checkReserve(reserve);
    bool isStakePaused = Pausable(stkToken).paused();
    bool isFundsNotZero = IUmbrellaStakeToken(stkToken).getMaxSlashableAssets() > 0;

    return isReserveSlashable && !isStakePaused && isFundsNotZero;
  }

  /**
   * @notice Method to check if there's some deficit on reserve and it's enabled for slashing.
   * @param reserve Address of the `reserve` to check it
   * @return bool True if the reserve slashable, false otherwise
   */
  function _checkReserve(address reserve) internal view returns (bool) {
    if (reserve == address(0) || isDisabled(reserve)) {
      return false;
    }

    (bool isSlashable, ) = IUmbrella(UMBRELLA).isReserveSlashable(reserve);
    return isSlashable;
  }

  /**
   * @notice Method to shuffle address array
   * @param addresses List of stk token addresses to shuffle
   * @return Array of shuffled addresses
   */
  function _shuffleAddresses(address[] memory addresses) internal view returns (address[] memory) {
    uint256 randomNumber = uint256(
      keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp))
    );

    for (uint256 i; i < addresses.length; ++i) {
      uint256 n = i + (randomNumber % (addresses.length - i));

      if (n == i) {
        continue;
      }

      address temp = addresses[n];
      addresses[n] = addresses[i];
      addresses[i] = temp;
    }

    return addresses;
  }
}
