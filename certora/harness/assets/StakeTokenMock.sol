pragma solidity ^0.8.20;

/* Location of the erc4626:
/home/nissan/Dropbox/certora/aave/1-UMBRELLA/WORK/lib/aave-v3-origin/lib/solidity-utils/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol
*/
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract StakeTokenMock is ERC4626 {
  constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20("ERC4626Mock", "E4626M") ERC4626 (asset_) {}
}
