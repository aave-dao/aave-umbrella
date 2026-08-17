
import {Umbrella} from 'src/contracts/umbrella/Umbrella.sol';
import {IPool, DataTypes} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {ReserveConfiguration} from 'aave-v3-origin/contracts/protocol/libraries/configuration/ReserveConfiguration.sol';


contract UmbrellaHarness is Umbrella {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  constructor() Umbrella() {}

  function get_is_virtual_active(address reserve) external view returns (bool) {
    return POOL().getConfiguration(reserve).getIsVirtualAccActive();
  }
}
