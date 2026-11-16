import "Pool.spec";

using UmbrellaStakeTokenA as StakeTokenA;

using ERC20A as erc20A;
using ERC20B as erc20B;

methods {
    function StakeTokenA.eip712Domain() external 
        returns(bytes1,string memory,string memory,uint256,address,bytes32,uint256[]) => NONDET DELETE;

    function StakeTokenA.name() external returns(string memory) => NONDET DELETE;

    function _.latestAnswer() external with (env e) => latestAnswerCVL(/*calledContract,*/e.block.timestamp) expect int256;

    /// This one created a new contract, which we ignore.
    function _.createDeterministic(address logic, address initialOwner, bytes data, bytes32 salt) external =>
        determinsticAddress(logic, initialOwner, data, salt) expect address;

    /// This one just predicts the expected created contract's address. Should conform to the value of 'createDeterministic'.
    function _.predictCreateDeterministic(address logic, address initialOwner, bytes data, bytes32 salt) external =>
        determinsticAddress(logic, initialOwner, data, salt) expect address;

    function Math.mulDiv(uint256 x, uint256 y, uint256 denominator) internal returns uint256 => mulDivDownCVL_pessim(x,y,denominator);

    function UmbrellaStkManager._getStakeNameAndSymbol(address,string calldata) internal returns (string memory, string memory) => randomStakeNameAndSymbol();
}

// ====  envfree methods ===========================================================
methods {
  function getDeficitOffset(address reserve) external returns (uint256) envfree;
  function getPendingDeficit(address reserve) external returns (uint256) envfree;
  function SLASHED_FUNDS_RECIPIENT() external returns (address) envfree;
  function get_is_virtual_active(address reserve) external returns (bool) envfree;
  function getReserveSlashingConfigs(address) external returns (IUmbrellaConfigurationBase.SlashingConfig[]) envfree;

  function erc20A.totalSupply() external returns (uint256) envfree;
  function erc20A.balanceOf(address account) external returns (uint256) envfree;
  function erc20A.allowance(address,address) external returns (uint256) envfree;
  function erc20B.totalSupply() external returns (uint256) envfree;
  function erc20B.balanceOf(address account) external returns (uint256) envfree;
  function erc20B.allowance(address,address) external returns (uint256) envfree;

  function StakeTokenA.asset() external returns (address) envfree;
}


ghost latestAnswerCVL(uint256 /*timestamp*/) returns int256;

persistent ghost createDeterministicAddress(address,address,bytes32,bytes32) returns address 
{
    axiom forall address logic. forall address initialOwner. forall bytes32 dataHash. forall bytes32 salt.
        createDeterministicAddress(logic, initialOwner, dataHash, salt) != 0;
    /*
    /// Injectivity axiom, use only if necessary
    axiom forall address logic. forall address initialOwner. forall bytes32 dataHash. forall bytes32 salt.
        forall address logicA. forall address initialOwnerA. forall bytes32 dataHashA. forall bytes32 saltA.
        createDeterministicAddress(logic, initialOwner, dataHash, salt) ==
        createDeterministicAddress(logicA, initialOwnerA, dataHashA, saltA) =>
        logicA == logic && initialOwner == initialOwnerA && dataHash == dataHashA && salt == saltA;
    */
}

function determinsticAddress(address logic, address initialOwner, bytes data, bytes32 salt) returns address {
    bytes32 dataHash = keccak256(data);
    return createDeterministicAddress(logic,initialOwner,dataHash,salt);
}

function mulDivDownCVL_pessim(uint256 x, uint256 y, uint256 z) returns uint256 {
    assert z !=0, "mulDivDown error: cannot divide by zero";
    return require_uint256(x * y / z);
}

function randomStakeNameAndSymbol() returns (string, string) {
    string name; require name.length <= 32;
    string symbol; require symbol.length <= 32;
    return (name, symbol);
}
