// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "./interfaces/IXENCrypto.sol";
import "./libs/MintInfo.sol";
import "./XENFT.sol";
import "hardhat/console.sol";

contract dbXENFT is ReentrancyGuard, IBurnRedeemable {
    using MintInfo for uint256;
    using SafeMath for uint256;

    XENTorrent public xenft;

    address public xenCrypto;

    /**
     * Power for the previous cycle.
     */
    uint256 public lastCyclePower;

    uint256 public constant SECONDS_IN_DAY = 3_600 * 24;

    uint256 public constant SECONDS_IN_YEAR = 3_600 * 24 * 365;

    uint256 public immutable newImagePeriodDuration;

    uint256 public constant MAX_PENALTY_PCT = 99;

    /**
    * Basis points representation of 100 percent.
    */
    uint256 public constant MAX_BPS = 10_000_000;

    uint256 private constant FIXED_POINT_DECIMALS = 18;
    
    uint256 private constant FIXED_POINT_FACTOR = 10 ** FIXED_POINT_DECIMALS;

    address WETH;

    address WETH_XEN_POOL;

       /**
     * Length of a fee distribution cycle. 
     * Initialized in contstructor to 1 day.
     */
    uint256 public immutable i_periodDuration;

    /**
     * Contract creation timestamp.
     * Initialized in constructor.
     */
    uint256 public immutable i_initialTimestamp;

    uint256 public totalPower;

    mapping(uint256 => bool) public alreadyUpdatePower; 

    mapping(address => uint256) public userTotalPower;

    /**
     * The last cycle in which an account has burned.
     */
    mapping(address => uint256) public lastActiveCycle;

    /**
     * The last cycle in which an account has updated power.
     */
    mapping(address => bool) public lastUserUpdatedPowerCycles;

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;
    // /**
    //  * @param xenftAddress XENFT contract address.
    //  */
    constructor(address xenftAddress, address _xenCrypto, address _WETH, address _WETH_XEN_POOL) {
        xenft = XENTorrent(xenftAddress);
        xenCrypto = _xenCrypto;
        WETH = _WETH;
        WETH_XEN_POOL = _WETH_XEN_POOL;
        newImagePeriodDuration = SECONDS_IN_YEAR;
        i_periodDuration = 1 days;
        i_initialTimestamp = block.timestamp;
    }

    modifier updateStats(uint256 tokenId) {
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo.decodeMintInfo();
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(userReward, xenft.xenBurned(tokenId), maturityTs, term) /10000;
        //require(msg.value >= fee, "dbXENFT: value less than protocol fee");
        uint256 power = _calculatePower(_calculateCurrentYearForPower(),userReward) * userReward;
        console.log("BEFORE ADD TOTAL POWER",totalPower);
        totalPower += power;
        console.log("AFTER ADD TOTAL POWER",totalPower);
        console.log("AFTER ADD USER POWER",userTotalPower[msg.sender]);
        userTotalPower[msg.sender] =  userTotalPower[msg.sender] + power;
        console.log("AFTER ADD USER POWER",userTotalPower[msg.sender]);
        cycleAccruedFees[getCurrentCycle()] += fee;
        //sendViaCall(payable(msg.sender), msg.value - fee);
        _;
    }
    // IBurnRedeemable IMPLEMENTATION

    /**
        @dev implements IBurnRedeemable interface for burning XEN and completing update for state
     */
    function onTokenBurned(address user, uint256 amount) external {
        require(msg.sender == address(xenft), "dbXENFT: illegal callback caller");
        setUpNewCycle();
        updateUserPower(user);
        lastActiveCycle[user] = getCurrentCycle();
    }

    /**
    * @dev Burn XENFT
    * 
    */
    function burnNFT(address user, uint256 tokenId)
        external
        payable
        nonReentrant()
        updateStats(tokenId)
    {           
        console.log("*********************");
        require(xenft.ownerOf(tokenId) == msg.sender, "You do not own this NFT!");
        IBurnableToken(xenft).burn(user, tokenId);
    }

    function _calculateFee(uint256 userReward, uint256 xenBurned, uint256 maturityTs, uint256 term) private returns(uint256){
        uint256 xenDifference;
        uint256 daysTillClaim;
        uint256 daysSinceMinted;
        uint256 daysDifference; 

        if(userReward  > xenBurned){
         xenDifference = userReward - xenBurned;
        } else {
            if(xenBurned == 0 && userReward ==0)
                return 1  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 250_000_000 * FIXED_POINT_FACTOR)
                return 22  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 500_000_000 * FIXED_POINT_FACTOR)
                return 2  ether;
            if(xenBurned == 1_000_000_000 * FIXED_POINT_FACTOR)
                return 18  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 2_000_000_000 * FIXED_POINT_FACTOR)
                return 16  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 2_500_000_000 * FIXED_POINT_FACTOR)
                return 14  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 5_000_000_000 * FIXED_POINT_FACTOR)
                return 12  * FIXED_POINT_FACTOR/10;
            if(xenBurned == 10_000_000_000 * FIXED_POINT_FACTOR)
                return 1 ether;
        }
        if(block.timestamp < maturityTs){
            daysTillClaim = ((maturityTs - block.timestamp + SECONDS_IN_DAY) / SECONDS_IN_DAY);
            daysSinceMinted = term - daysTillClaim;
        }

        console.log("1 ",daysSinceMinted);   
        console.log("3 ",daysTillClaim);

        if(daysSinceMinted > daysTillClaim){
            daysDifference = daysSinceMinted - daysTillClaim;
        }
        uint256 maxValue = daysDifference > 0 ? daysDifference : 0;

        if(maxValue != 0){
            uint256 procentageValue = (10_000_000 - (11389 * maxValue)) / MAX_BPS;
           // return xenDifference * procentageValue;
           return 1 ether;
        } else {
            //return xenDifference;
            return  2 ether;
        }
    }

   function _calculatePower(uint256 year, uint256 userReward) internal view returns (uint) {
        uint256 base = FIXED_POINT_FACTOR.div(2); // 0.5 as a fixed-point number with 18 decimal places
        uint256 result = base;
        if(year != 0 && userReward == 0){
            for (uint256 i = 1; i < year; i++) {
                result = result.mul(base).div(FIXED_POINT_FACTOR);
            }
        return result;
        } else {
            return 1;
        }
    }

    function getQuote(uint128 amountIn) internal view returns(uint256 amountOut) {
        (int24 tick, ) = OracleLibrary.consult(WETH_XEN_POOL, 1);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, xenCrypto, WETH);
    }

    function _calculateCurrentYearForPower() public returns(uint256){
        uint256 currentYear = (block.timestamp - i_initialTimestamp) / newImagePeriodDuration;
        if(currentYear < 50){
            return (block.timestamp - i_initialTimestamp) / newImagePeriodDuration;
        }else{
            return 50;
        }
    }

    function _calculateCurrentYear() public returns(uint256){
        return ((block.timestamp - i_initialTimestamp) / newImagePeriodDuration);
    }

    function _penalty(uint256 secsLate) private pure returns (uint256) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint256 daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > 7 - 1) return MAX_PENALTY_PCT;
        uint256 penalty = (uint256(1) << (daysLate + 3)) / 7 - 1;
        return penalty < MAX_PENALTY_PCT ? penalty : MAX_PENALTY_PCT;
    }

      function _calculateMintReward(
        uint256 cRank,
        uint256 term,
        uint256 maturityTs,
        uint256 amplifier,
        uint256 eeaRate
    ) private view returns (uint256) {
        uint256 penalty;
        if(block.timestamp > maturityTs){
            uint256 secsLate = block.timestamp - maturityTs;
            penalty = _penalty(secsLate);
        }
        uint256 rankDiff = IXENCrypto(xenCrypto).globalRank() - cRank;
        uint256 rankDelta = rankDiff > 2 ? rankDiff : 2;
        uint256 EAA = (1000 + eeaRate);
        uint256 reward = IXENCrypto(xenCrypto).getGrossReward(rankDelta, amplifier, term, EAA);
        return (reward * (100 - penalty)) / 100;
    }

    function _calculateUserMintReward(uint256 tokenId, uint256 mintInfo) internal view returns(uint256 userMintReward) {
        uint256 vmuCount = xenft.vmuCount(tokenId);
        (uint256 term, uint256 maturityTs, uint256 rank, uint256 amp, uint256 eea, , , , ) = mintInfo.decodeMintInfo();
        uint256 mintReward = _calculateMintReward(rank, term, maturityTs, amp, eea);
        return mintReward * vmuCount;
    }

    // /**
    //     @dev confirms support for IBurnRedeemable interfaces
    // */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == type(IBurnRedeemable).interfaceId;
    }

    /**
    * @dev Returns the index of the cycle at the current block time.
    */
    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - i_initialTimestamp) / i_periodDuration;
    }

    /**
     * @dev Updates the global state related to starting a new cycle along 
     * with helper state variables used in computation of staking rewards.
     */
    function setUpNewCycle() internal {
          console.log("TOTAL POWER BEFORE UPDATE CYCLE",totalPower);
        if (alreadyUpdatePower[getCurrentCycle()] == false && getCurrentCycle()!= 0) {
            lastCyclePower = totalPower;
            totalPower = (lastCyclePower * 10000) / 10020;
            alreadyUpdatePower[getCurrentCycle()] = true;
            console.log("TOTAL POWER after UPDATE CYCLE",totalPower);
        }
        if(getCurrentCycle() == 0){
             alreadyUpdatePower[getCurrentCycle()] = true;
        }
    }

    function updateUserPower(address user) internal{
        console.log("USER TOTAL POWER BEFORE UPDATE ",userTotalPower[user]);
        if(lastActiveCycle[user] < getCurrentCycle() && lastActiveCycle[user] != 0 && lastUserUpdatedPowerCycles[user] == false){
            uint256 numberOfInactiveCycles = getCurrentCycle() - lastActiveCycle[user];
            userTotalPower[user] = (userTotalPower[user] * 10000) / (10020 * numberOfInactiveCycles);
            console.log("USER TOTAL POWER after UPDATE ",userTotalPower[user]);
            lastUserUpdatedPowerCycles[user] = true;
        } 
    }

    /**
     * @dev Transfers newly accrued fees to sender's address.
     */
    function claimFees() external{
        updateUserPower(msg.sender);
        uint256 fees = (userTotalPower[msg.sender] / totalPower) * cycleAccruedFees[getCurrentCycle()];
        require(fees > 0, "dbXENFT: amount is zero");
        sendViaCall(payable(msg.sender), fees);
    }

    /**
    * Recommended method to use to send native coins.
    * 
    * @param to receiving address.
    * @param amount in wei.
    */
    function sendViaCall(address payable to, uint256 amount) internal {
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "DBXen: failed to send amount");
    }

}