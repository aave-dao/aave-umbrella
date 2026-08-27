import "setup.spec";
import "invariants.spec";

use builtin rule sanity;

rule updateSlashingConfigSanity(env e) {
    IUmbrellaConfiguration.SlashingConfigUpdate[] slashingConfigs;
    require slashingConfigs.length == 1;
    updateSlashingConfigs(e, slashingConfigs);
    satisfy true;
}

rule predictStakeTokensAddressesSanity(env e) {
    IUmbrellaStkManager.StakeTokenSetup[] stakeSetups;
    require stakeSetups.length == 1;
    predictStakeTokensAddresses(e, stakeSetups);
    satisfy true;
}

rule createStakeTokensSanity(env e) {
    IUmbrellaStkManager.StakeTokenSetup[] stakeSetups;
    require stakeSetups.length == 1;
    createStakeTokens(e, stakeSetups);
    satisfy true;
}


// ==========================================================================
// The following function is to ease debugging
// ==========================================================================
function nice_values() {
  require currentContract == 100;
  require StakeTokenA==10;
  require erc20A==15;
  require erc20B==16;
}


// ===================================================================================
// The following function converts the price of the reserve (the asset with the deficit)
// to the price of the slashed asset (the underlive of the stake-token).
// We do the same calculation as done in the design.
// ==================================================================================
function reserve_price_to_stakeToken_price(env e, address reserve, mathint amount) returns mathint {
  uint256 asset_price = assetPriceCVL(reserve, e.block.timestamp); //price of the reserve
  int256 latest_answer = latestAnswerCVL(e.block.timestamp); // price of the stake-token
  require latest_answer > 0;

  return amount * asset_price / latest_answer;
}



//================================================================================================
// Rule: integrity_of_slashing
// Description: We check the following aspects of slash():
// - The slashed-amount can't exceed the real-deficit - deficit-offset - pending-deficit.
// - The pending-deficit is updated correctly.
// - The actual-slashed-amount can't exceed the deficit that can be covered + fees.
// - The balance of the contract grows as expected.
//
// - Note: In this rule the underline of the stake-token is the contract erc20A.
//================================================================================================
rule integrity_of_slashing() {
  env e; address _reserve;
  
  address _the_stake_token = getReserveSlashingConfigs(_reserve)[0].umbrellaStake;
  address _slashed_funds_recipient = SLASHED_FUNDS_RECIPIENT();
  address _underline_asset = _the_stake_token.asset(e);

  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  require _the_stake_token.asset(e) == erc20A;
  require _slashed_funds_recipient != _the_stake_token;

  uint256 _total_assets_pre = _the_stake_token.totalAssets(e);
  uint256 _bal_pre = _underline_asset.balanceOf(e, _slashed_funds_recipient);
  uint256 _pending_deficit_pre = getPendingDeficit(_reserve);
  
  uint256 _deficit_in_pool = _reservesDeficit[_reserve];
  uint256 _deficit_offset = getDeficitOffset(_reserve);

  // =============== The slashing ========================================
  uint256 _slashed_amount = slash(e, _reserve);
  // =====================================================================
  
  uint256 _bal_post = _underline_asset.balanceOf(e, _slashed_funds_recipient);
  uint256 _pending_deficit_post = getPendingDeficit(_reserve);
  uint256 _total_assets_post = _the_stake_token.totalAssets(e);

  mathint _deficit_to_cover = _deficit_in_pool - _deficit_offset - _pending_deficit_pre;
  assert _slashed_amount <= _deficit_to_cover;
  assert _pending_deficit_post == _pending_deficit_pre + _slashed_amount;

  // Currently we must have a single stake-token associated to a reserve
  assert getReserveSlashingConfigs(_reserve).length==1; 

  uint256 _liquidation_fee = getReserveSlashingConfigs(_reserve)[0].liquidationFee;

  // We calculate the fees the same as in the contract
  mathint _deficit_to_cover_plus_fee =
    mulDivDownCVL_pessim(assert_uint256(_deficit_to_cover), assert_uint256(_liquidation_fee + 10^4), 10^4);

  mathint _actual_slashed_amount = _total_assets_pre - _total_assets_post;
  assert _actual_slashed_amount <= reserve_price_to_stakeToken_price(e, _reserve, _deficit_to_cover_plus_fee);
  assert _bal_post - _bal_pre == _actual_slashed_amount;
}

//================================================================================================
// Rule: integrity_of_coverPendingDeficit
// Description: We check the following aspects of coverPendingDeficit():
// - The _covered_amount, which is the value returned from the function equals to the minimum between
//   the pending-deficit and amount (a parameter passed to the function).
// - The pending-deficit is updated correctly.
// - The function POOL's function, eliminateReserveDeficit(), is called with the correct parameters.
// - The correct amount of money is transferred to currentContract (either from the AToken or from the reserve,
//   depending whether virtual accounting is enabled or not). Note that this money should be transfer to
//   the pool in the POOL's function eliminateReserveDeficit(). But since we don't include the real POOL's
//   functions here, we just check that the money arrived to currentContract.

// - Note: In this rule the reserve is the contract erc20A, and its AToken is erc20B
//================================================================================================
rule integrity_of_coverPendingDeficit() {
  env e; address _reserve; uint256 _amount;
  
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;
  require e.msg.sender != currentContract;

  uint256 _pending_deficit_pre = getPendingDeficit(_reserve);
  uint256 _bal_of_contract_reserve_pre = erc20A.balanceOf(currentContract);
  uint256 _bal_of_contract_AToken_pre = erc20B.balanceOf(currentContract);
  
  // =============== covering ============================================
  uint256 _covered_amount = coverPendingDeficit(e, _reserve, _amount);
  // =====================================================================
  
  uint256 _pending_deficit_post = getPendingDeficit(_reserve);
  uint256 _bal_of_contract_reserve_post = erc20A.balanceOf(currentContract);
  uint256 _bal_of_contract_AToken_post = erc20B.balanceOf(currentContract);

  satisfy _amount > _pending_deficit_pre;
  assert _covered_amount == (_amount <= _pending_deficit_pre ? _amount : _pending_deficit_pre);
  assert _pending_deficit_post == _pending_deficit_pre - _covered_amount;
  assert eliminateReserveDeficit__asset == _reserve && eliminateReserveDeficit__amount == _covered_amount;
  assert get_is_virtual_active(_reserve) ?
    _covered_amount == _bal_of_contract_AToken_post - _bal_of_contract_AToken_pre :
    _covered_amount == _bal_of_contract_reserve_post - _bal_of_contract_reserve_pre ;
}



//================================================================================================
// Rule: integrity_of_coverDeficitOffset
// Description: We check the following aspects of coverDeficitOffset():
// - The pending-deficit value isn't changed.
// - The covered-amount, which is the value returned from the function, plus pending-deficit
//   can't exceed the deficit of the asset. Moreover, covered-amount can't exceed that offset-deficit
//   or the amount (a parameter passed to the function).
// - The deficit-offset is updated correctly.
// - The function POOL's function, eliminateReserveDeficit(), is called with the correct parameters.
// - The correct amount of money is transferred to currentContract (either from the AToken or from the reserve,
//   depending whether virtual accounting is enabled or not). Note that this money should be transfer to
//   the pool in the POOL's function eliminateReserveDeficit(). But since we don't include the real POOL's
//   functions here, we just check that the money arrived to currentContract.

// - Note: In this rule the reserve is the contract erc20A, and its AToken is erc20B
//================================================================================================
rule integrity_of_coverDeficitOffset() {
  env e; address _reserve; uint256 _amount;
  
  address _the_stake_token = getReserveSlashingConfigs(_reserve)[0].umbrellaStake;

  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;

  require e.msg.sender != currentContract; require e.msg.sender != _the_stake_token;

  uint256 _deficit_in_pool_pre = getReserveDeficitCVL(_reserve);
  uint256 _pending_deficit_pre = getPendingDeficit(_reserve);
  uint256 _deficit_offset_pre = getDeficitOffset(_reserve);
  uint256 _bal_of_contract_reserve_pre = erc20A.balanceOf(currentContract);
  uint256 _bal_of_contract_AToken_pre = erc20B.balanceOf(currentContract);
  
  // =============== covering ============================================
  uint256 _covered_amount = coverDeficitOffset(e, _reserve, _amount);
  // =====================================================================
  
  uint256 _pending_deficit_post = getPendingDeficit(_reserve);
  uint256 _deficit_offset_post = getDeficitOffset(_reserve);
  uint256 _bal_of_contract_reserve_post = erc20A.balanceOf(currentContract);
  uint256 _bal_of_contract_AToken_post = erc20B.balanceOf(currentContract);

  assert _pending_deficit_pre == _pending_deficit_post;
  assert _covered_amount + _pending_deficit_pre <= _deficit_in_pool_pre;
  
  assert _covered_amount <= (_amount <= _deficit_offset_pre ? _amount : _deficit_offset_pre);
  assert _deficit_offset_post == _deficit_offset_pre - _covered_amount;
  assert eliminateReserveDeficit__asset == _reserve && eliminateReserveDeficit__amount == _covered_amount;
  assert get_is_virtual_active(_reserve) ?
    _covered_amount == _bal_of_contract_AToken_post - _bal_of_contract_AToken_pre :
    _covered_amount == _bal_of_contract_reserve_post - _bal_of_contract_reserve_pre ;
}



//================================================================================================
// Rule: possible_slashing_amount_cant_be_changed
// Description:
// Define the possible-slashing-amount to be:  deficit-in-pool - pending-deficit - deficit-offset. 
// We verify that the possible-slashing-amount doesn't changed except for the following functions
// that obviously should change it:
// - setDeficitOffset(..): this function simply changes the deficit-offset.
// - slash(..): this function changes the pending-deficit.
// - coverReserveDeficit(..): this function changes the deficit-in-pool.
// - updateSlashingConfigs(..): this function changes the deficit-offset.
//================================================================================================
rule possible_slashing_amount_cant_be_changed(method f) filtered {f ->
    f.selector != sig:setDeficitOffset(address,uint256).selector
    && f.selector != sig:slash(address).selector
    && f.selector != sig:coverReserveDeficit(address,uint256).selector
    && f.selector != sig:updateSlashingConfigs(IUmbrellaConfiguration.SlashingConfigUpdate[]).selector
    } {
  env e; address _reserve;

  uint256 _deficit_in_pool_pre = getReserveDeficitCVL(_reserve);
  uint256 _pending_deficit_pre = getPendingDeficit(_reserve);
  uint256 _deficit_offset_pre = getDeficitOffset(_reserve);

  mathint _possible_slashing_pre = _deficit_in_pool_pre - _pending_deficit_pre - _deficit_offset_pre < 0 ?
    0 :
    _deficit_in_pool_pre - _pending_deficit_pre - _deficit_offset_pre;

  calldataarg args;
  f(e,args);

  uint256 _deficit_in_pool_post = getReserveDeficitCVL(_reserve);
  uint256 _pending_deficit_post = getPendingDeficit(_reserve);
  uint256 _deficit_offset_post = getDeficitOffset(_reserve);

  mathint _possible_slashing_post = _deficit_in_pool_post - _pending_deficit_post - _deficit_offset_post < 0 ?
    0 :
    _deficit_in_pool_post - _pending_deficit_post - _deficit_offset_post;

  assert _possible_slashing_post == _possible_slashing_pre;
}



//================================================================================================
// Rule: slashing_cant_DOS_other_functions
// Description: We check that an attacker can't use the slash function in order to make other functions
//              to revert. That is, if a function f doesn't revert when executed from some state,
//              then if an attacker front-run the slash() function (from the same state) then f
//              still doesn't revert.
// Note: We only check the slash() function because it is the only non-view function that can be run
//       without a special role.
//================================================================================================
rule slashing_cant_DOS_other_functions(method f)
  filtered {f ->
    // if no deficit, the call slash(..) reverts. Hence we can't call 2 consecutive slash().
    f.selector != sig:slash(address).selector
    // calling to unpauseStk must be when in pause, But slashing can't be called when in pause.
    && f.selector != sig:unpauseStk(address).selector 
    // The following 4 functions are treated seperately
    && f.selector != sig:coverPendingDeficit(address,uint256).selector
    && f.selector != sig:coverDeficitOffset(address,uint256).selector
    && f.selector != sig:coverReserveDeficit(address,uint256).selector
    && f.selector != sig:setDeficitOffset(address,uint256).selector
    } {
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();

  env e2; calldataarg args; env e1;
  require e1.block.timestamp <= e2.block.timestamp;
  require (e2.msg.sender != currentContract && e2.msg.sender != erc20A && e2.msg.sender != erc20B &&
           e2.msg.sender != StakeTokenA);
  require (e1.msg.sender != currentContract && e1.msg.sender != erc20A && e1.msg.sender != erc20B &&
           e1.msg.sender != StakeTokenA);
  
  storage initialStorage = lastStorage;
  //The following are parameters for the emergency functions
  address umbrellaStake; address erc20Token; address to; uint256 amount;
  require erc20Token != StakeTokenA;
  if (f.selector == sig:emergencyTokenTransfer(address,address,uint256).selector) {
    emergencyTokenTransfer(e2, erc20Token, to, amount);
  }
  else if (f.selector == sig:emergencyTokenTransferStk(address,address,address,uint256).selector) {
    emergencyTokenTransferStk(e2, umbrellaStake, erc20Token, to, amount);
  }
  else {
    f(e2, args);
  }
  
  address _reserve; 
  slash(e1, _reserve) at initialStorage;

  if (f.selector == sig:emergencyTokenTransfer(address,address,uint256).selector) {
    emergencyTokenTransfer@withrevert(e2, erc20Token, to, amount);
  }
  else if (f.selector == sig:emergencyTokenTransferStk(address,address,address,uint256).selector) {
    emergencyTokenTransferStk(e2, umbrellaStake, erc20Token, to, amount);
  }
  else {
    f@withrevert(e2, args);
  }
  assert !lastReverted;
}



//================================================================================================
// See: slashing_cant_DOS_other_functions
//================================================================================================
rule slashing_cant_DOS__coverPendingDeficit() {
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();

  address _reserve; uint256 _amount;
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;
  
  env e2; env e1;
  require e1.block.timestamp <= e2.block.timestamp;
  require (e2.msg.sender != currentContract && e2.msg.sender != erc20A && e2.msg.sender != erc20B &&
           e2.msg.sender != StakeTokenA);
  require (e1.msg.sender != currentContract && e1.msg.sender != erc20A && e1.msg.sender != erc20B &&
           e1.msg.sender != StakeTokenA);
  
  storage initialStorage = lastStorage;
  
  uint256 _pendingDeficit = getPendingDeficit(_reserve);
  require _amount <= _pendingDeficit; // this should be handled by the proposal that calls coverPendingDeficit()
  coverPendingDeficit(e2, _reserve, _amount);
  
  address __reserve;
  slash(e1, __reserve) at initialStorage;

  coverPendingDeficit@withrevert(e2, _reserve, _amount);
  assert !lastReverted;
}



//================================================================================================
// See: slashing_cant_DOS_other_functions
//================================================================================================
rule slashing_cant_DOS__coverDeficitOffset() {
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();

  address _reserve;
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;
  
  env e2; env e1;
  require e1.block.timestamp <= e2.block.timestamp;
  require (e2.msg.sender != currentContract && e2.msg.sender != erc20A && e2.msg.sender != erc20B &&
           e2.msg.sender != StakeTokenA);
  require (e1.msg.sender != currentContract && e1.msg.sender != erc20A && e1.msg.sender != erc20B &&
           e1.msg.sender != StakeTokenA);
  
  storage initialStorage = lastStorage;

  uint256 _amount;
  coverDeficitOffset(e2, _reserve, _amount);
  
  address __reserve; 
  slash(e1, __reserve) at initialStorage;

  coverDeficitOffset@withrevert(e2, _reserve, _amount);
  assert !lastReverted;
}




//================================================================================================
// See: slashing_cant_DOS_other_functions
//================================================================================================
rule slashing_cant_DOS__setDeficitOffset() {
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();

  address _reserve;
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;
  
  env e2; env e1;
  require e1.block.timestamp <= e2.block.timestamp;
  require (e2.msg.sender != currentContract && e2.msg.sender != erc20A && e2.msg.sender != erc20B &&
           e2.msg.sender != StakeTokenA);
  require (e1.msg.sender != currentContract && e1.msg.sender != erc20A && e1.msg.sender != erc20B &&
           e1.msg.sender != StakeTokenA);
  
  storage initialStorage = lastStorage;

  uint256 _newDeficitOffset;
  setDeficitOffset(e2, _reserve, _newDeficitOffset);
  
  address __reserve; 
  slash(e1, __reserve) at initialStorage;

  uint256 _pending_deficit = getPendingDeficit(_reserve);
  require _pending_deficit + _newDeficitOffset <= 2^256-1; // Reasonable values
 
  setDeficitOffset@withrevert(e2, _reserve, _newDeficitOffset);
  assert !lastReverted;
}





//================================================================================================
// See: slashing_cant_DOS_other_functions
//================================================================================================
rule slashing_cant_DOS__coverReserveDeficit() {
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20A();
  requireInvariant inv_sumOfBalances_eq_totalSupply__erc20B();

  address _reserve; uint256 _amount;
  require _reserve == erc20A;
  require ATokenOfReserve(_reserve) == erc20B;

  env e2; env e1;
  require e1.block.timestamp <= e2.block.timestamp;
  require (e2.msg.sender != currentContract && e2.msg.sender != erc20A && e2.msg.sender != erc20B &&
           e2.msg.sender != StakeTokenA);
  require (e1.msg.sender != currentContract && e1.msg.sender != erc20A && e1.msg.sender != erc20B &&
           e1.msg.sender != StakeTokenA);
  
  storage initialStorage = lastStorage;
  
  uint256 _pendingDeficit = getPendingDeficit(_reserve);
  coverReserveDeficit(e2, _reserve, _amount);
  assert _pendingDeficit == 0;

  address __reserve; slash(e1, __reserve) at initialStorage;
    
  coverReserveDeficit@withrevert(e2, _reserve, _amount);
  assert !lastReverted;
}
