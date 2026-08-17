pragma solidity ^0.8.0;

import {RewardsController} from 'src/contracts/rewards/RewardsController.sol';
import {InternalStructs} from 'src/contracts/rewards/libraries/InternalStructs.sol';

import {DummyContract} from './DummyContract.sol';

contract RewardsControllerHarness is RewardsController {
  DummyContract DUMMY;

  constructor() RewardsController() {}

  bytes32 private constant __RewardsDistributorStorageLocation =
    0x21b0411c7d97c506a34525b56b49eed70b15d28e22527c4589674c84ba9a5200;

  bytes32 private constant __RewardsControllerStorageLocation =
    0x7a5f91582c97dd0b2921808fbdbab73d3de091aefc8bf8607868e058abb2e300;
  

  // The "getStorage" functions of the contracts RewardsController and RewardsDistributor are
  // private, hence we make a copy of them.
  function __getRewardsDistributorStorage() private pure returns (RewardsDistributorStorage storage $) {
    assembly {$.slot := __RewardsDistributorStorageLocation}
  }

  function __getRewardsControllerStorage() internal pure returns (RewardsControllerStorage storage $) {
    assembly {$.slot := __RewardsControllerStorageLocation}
  }


  function get_rewardsInfo_length(address asset) external view returns (uint) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.rewardsInfo.length;
  }
  
  function get_targetLiquidity(address asset) external view returns (uint160) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.targetLiquidity;
  }
  
  //================================================
  // RewardData struct
  //================================================
  function get_rewardIndex(address asset, address reward) external view returns (uint144) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].rewardData.index;
  }

  function get_maxEmissionPerSecondScaled(address asset, address reward) external view returns (uint72) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].rewardData.maxEmissionPerSecondScaled;
  }

  function get_distributionEnd__map(address asset, address reward) external view returns (uint32) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].rewardData.distributionEnd;
  }

  function get_decimalsScaling(address asset, address reward) external view returns (uint8) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].rewardData.decimalsScaling;
  }

  //================================================
  // UserData struct
  //================================================
  function get_userIndex(address asset, address reward, address user) external view returns (uint144) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].userData[user].index ;
  }

  function get_accrued(address asset, address reward, address user) external view returns (uint112) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].userData[user].accrued ;
  }


  
  function get_distributionEnd__arr(address asset, uint ind) external view returns (uint32) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.rewardsInfo[ind].distributionEnd;
  }

  // Return the reward's address
  function get_addr(address asset, uint ind) external view returns (address) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.rewardsInfo[ind].addr;
  }

  function get_rewardPayer(address asset, address reward) external view returns (address) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.data[reward].rewardPayer ;
  }

  function get_lastUpdateTimestamp(address asset) external view returns (uint32) {
    InternalStructs.AssetData storage assetData = __getRewardsControllerStorage().assetsData[asset];
    return assetData.lastUpdateTimestamp;
  }
  


  function havoc_other_contracts() external {DUMMY.havoc_other_contracts();}
  function havoc_all_contracts() external {DUMMY.havoc_all_contracts_dummy();}
}
