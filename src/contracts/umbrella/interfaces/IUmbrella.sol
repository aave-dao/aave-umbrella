// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IUmbrellaStkManager} from './IUmbrellaStkManager.sol';

interface IUmbrella is IUmbrellaStkManager {
  /**
   * @dev Attempted to set `deficitOffset` less than possible to avoid immediate slashing.
   */
  error TooMuchDeficitOffsetReduction();

  /**
   * @dev Attempted to cover zero deficit.
   */
  error ZeroDeficitToCover();

  /**
   * @dev Attempted to slash for reserve with zero new deficit or without `SlashingConfig` setup.
   */
  error CannotSlash();

  /**
   * @dev Attempted to slash a basket of `StakeToken`s. Unreachable error in the current version.
   */
  error NotImplemented();
}
