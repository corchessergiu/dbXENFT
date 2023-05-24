// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IXENCrypto.sol";
import "./libs/MintInfo.sol";
import "./XENFT.sol";
import "./DBXenERC20.sol";
import "hardhat/console.sol";

contract dbXENFT is ReentrancyGuard, IBurnRedeemable {
    using MintInfo for uint256;
    using SafeMath for uint256;
    using SafeERC20 for DBXenERC20;

    XENTorrent public xenft;

    /**
     * DBXen Reward Token contract.
     * Initialized in constructor.
     */
    DBXenERC20 public dxn;

    address public xenCrypto;

    /**
     * Power for the previous cycle.
     */
    uint256 public lastCyclePower;

    uint256 public lastGlobalActiveCycle;

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

    mapping(uint256 => bool) public alreadyUpdateGlobalPower; 

    mapping(address => mapping(uint256 => bool)) public alreadyUpdateUserPower; 

    mapping(address => uint256) public userTotalPower;

    /**
     * The last cycle in which an account has burned.
     */
    mapping(address => uint256) public lastActiveCycle;
    

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;

    mapping(address => uint256) public userStakedAmount;

    mapping(uint256 => mapping(address => uint256)) public userCycleStake;
    
    mapping(address => uint256) public userPreviousStake;

    mapping(address => uint256) public userWithdrawableStake;

    mapping(address => uint256) public userLastCycleStake;

    mapping(address => uint256) public userLastCycleUnstake;
    /**
     * @param xenftAddress XENFT contract address.
     */
    constructor(address dbxAddress, address xenftAddress, address _xenCrypto, address _WETH, address _WETH_XEN_POOL) {
        dxn = DBXenERC20(dbxAddress);
        xenft = XENTorrent(xenftAddress);
        xenCrypto = _xenCrypto;
        WETH = _WETH;
        WETH_XEN_POOL = _WETH_XEN_POOL;
        newImagePeriodDuration = SECONDS_IN_YEAR;
        i_periodDuration = 1 days;
        i_initialTimestamp = block.timestamp;
    }

    modifier updateStats(uint256 tokenId) {
        console.log();
        console.log("token id " ,tokenId);
        console.log("***************************** ->> ciclu curent ", getCurrentCycle());
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo.decodeMintInfo();
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(userReward, xenft.xenBurned(tokenId), maturityTs, term) /10000;
        //require(msg.value >= fee, "dbXENFT: value less than protocol fee");
        uint256 power = 1 * 10 **18;
        //console.log("userReward  ", power);
        //console.log("totalPower before  ", totalPower);
        totalPower += power;
        //console.log("totalPower  ", totalPower);
        userTotalPower[msg.sender] = userTotalPower[msg.sender] + power;
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
        uint256 currentCycle = getCurrentCycle();
        //updateWithdrawableStakeAmount(user,currentCycle);
        //updateUserPower(user);
        lastActiveCycle[user] = currentCycle;
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
        require(xenft.ownerOf(tokenId) == msg.sender, "You do not own this NFT!");
        IBurnableToken(xenft).burn(user, tokenId);
    }

    function updateUserPower(address user) internal {
        console.log("***************** UPDATE USER POWER *****************");
        uint256 lastActiveCycleLocal = lastActiveCycle[user];
        uint256 currentCycle = getCurrentCycle();
        console.log("currentCycle ",currentCycle);
        console.log("lastActiveCycle ",lastActiveCycleLocal);

        if(lastActiveCycleLocal < currentCycle && alreadyUpdateUserPower[user][currentCycle] == false){
            console.log("INSIDE USER UPDATE POWER"); 
            uint256 numberOfInactiveCycles = currentCycle - lastActiveCycleLocal;
            console.log("numberOfInactiveCycles ",numberOfInactiveCycles);
            console.log("userWithdrawableStake[user] ",userWithdrawableStake[user]);
            if(userWithdrawableStake[user] != 0){
                for(uint256 index = 0 ; index < numberOfInactiveCycles; index++) {
                    if(lastActiveCycleLocal != 0){
                        calculateUserPower(user, lastActiveCycleLocal);
                    }
                    if(alreadyUpdateGlobalPower[lastActiveCycleLocal] == false){
                        lastCyclePower = totalPower;
                        calculateTotalPower(totalPower, lastGlobalActiveCycle);
                    }
                    calculateExtraPower(userWithdrawableStake[user],user);
                    lastActiveCycleLocal = lastActiveCycleLocal +1;
                    lastActiveCycle[user] = lastActiveCycleLocal;
                    console.log("lastActiveCycle ",lastActiveCycle[user]);
                } 
            } else {
                    console.log("else withdrawble ");
                    for(uint256 index = 1 ; index < numberOfInactiveCycles; index++) {
                        calculateUserPower(user, lastActiveCycleLocal);
                           if(alreadyUpdateGlobalPower[lastActiveCycleLocal] == false){
                                calculateTotalPower(totalPower, lastGlobalActiveCycle);
                                lastCyclePower = totalPower;
                            }
                        lastActiveCycleLocal = lastActiveCycleLocal + 1; 
                        lastActiveCycle[user] =  lastActiveCycleLocal;
                        console.log("lastActiveCycle[user] ",lastActiveCycle[user]);
                    }
            }
        }

        if(currentCycle == 0  && alreadyUpdateUserPower[user][0] == false){
            console.log("intru pentru ciclul 0!!!");
            calculateUserPower(user,0);
                if(alreadyUpdateGlobalPower[0] == false){
                    lastCyclePower = totalPower;
                    calculateTotalPower(totalPower, 0);
                }
        }
          console.log("*****************FINISH UPDATE USER POWER *****************");
    }
    
    function updateWithdrawableStakeAmount(address user, uint256 currentCycle) internal {
        uint256 lastStakeCycle = userLastCycleStake[user];
        console.log("UPDATEUL");
        if(userCycleStake[lastStakeCycle][user] != 0 && userLastCycleStake[user] != currentCycle){
            console.log("UPDATE stake inside");
            userWithdrawableStake[user] = userWithdrawableStake[user] + userCycleStake[lastStakeCycle][user];
            console.log("userWithdrawableStake[msg.sender] ",userWithdrawableStake[user]);
            userCycleStake[lastStakeCycle][user] = 0;
            userLastCycleStake[user] = 0;
        }
    }

    function updateWithdrawableStakeAmountAtUnstake(address user, uint256 amount) internal{
        userWithdrawableStake[user] = userWithdrawableStake[user] - amount;
        userStakedAmount[user] = userStakedAmount[user] - amount;
        console.log(" userWithdrawableStake[user]  after unstake action!",userWithdrawableStake[user]);
    }

    function calculateUserPower(address user, uint256 cycle) internal {
        console.log("calculateUserPower function");
        console.log("BEFORE");
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log(" alreadyUpdateUserPower[user][cycle] ", alreadyUpdateUserPower[user][cycle]);
        if(userTotalPower[user] * 10000 / 10020  > 1 ether){
            console.log("mai mare ************************************* ");
            userTotalPower[user] = userTotalPower[user] * 10000 / 10020;
            alreadyUpdateUserPower[user][cycle] = true;
        } else {
            userTotalPower[user] = 1 * 10 **18;
            alreadyUpdateUserPower[user][cycle] = true;
        }
        console.log("AFTER");
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log(" alreadyUpdateUserPower[user][cycle] ", alreadyUpdateUserPower[user][cycle]);
    }

    function calculateTotalPower(uint256 power, uint256 cycle) internal {
        console.log("CALCULATE TOTAL POWER");
        console.log("BEFORE");
        console.log("totalPower ",totalPower);
        console.log("alreadyUpdateGlobalPower[cycle] ", alreadyUpdateGlobalPower[cycle]);
        if(power * 10000 / 10020  > 1 ether){
            console.log("mai mare ma************************************* ");
            totalPower = (power * 10000) / 10020;
            alreadyUpdateGlobalPower[cycle] = true;
        } else {
            totalPower = 1 * 10 **18;
            alreadyUpdateGlobalPower[cycle] = true;
        }
        console.log("AFTER");
        console.log("totalPower ",totalPower);
        console.log("alreadyUpdateGlobalPower[cycle] ", alreadyUpdateGlobalPower[cycle]);
    }
    
    function calculateExtraPower(uint256 amountOfDXNStaked, address user) internal{
        console.log("CALCULATE EXTRA POWER");
        console.log("BEFORE");
        console.log("amountOfDXNStaked ",amountOfDXNStaked);
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log("totalPower ", totalPower);
        uint256 extraAmountOfPower = amountOfDXNStaked * 10000000;
        console.log(extraAmountOfPower);
        userTotalPower[user] = userTotalPower[user]  + extraAmountOfPower;
        totalPower = totalPower + extraAmountOfPower;
        console.log("AFTER");
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log("totalPower ", totalPower);
    }

    //punem un anumit numar pe fiecare xen sau cum se trateaa aici?
    function stake(uint256 amount)
        external
        nonReentrant()
    {   
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender,currentCycle);
        updateUserPower(msg.sender);
        require(amount > 0, "DBXen: amount is zero");
        userLastCycleStake[msg.sender] = currentCycle;
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender] + amount;
        userCycleStake[currentCycle][msg.sender] = userCycleStake[currentCycle][msg.sender] + amount;
        dxn.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake(uint256 amount)
        external
        nonReentrant()
    {   
        console.log("UNSTAKE*******->>>>>>>>>>>>>>>>>>>>>*************************************");
        require(amount > 0, "dbXENFT: amount is zero");
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender,currentCycle);
        require(
            amount <= userWithdrawableStake[msg.sender],
            "dbXENFT: amount greater than withdrawable stake"
        );
        updateWithdrawableStakeAmountAtUnstake(msg.sender,amount);
        updateUserPower(msg.sender);
        dxn.safeTransfer(msg.sender, amount);
    }

    function claimFees() external {
        updateUserPower(msg.sender);
        uint256 fees = (userTotalPower[msg.sender] / totalPower) * cycleAccruedFees[getCurrentCycle()];
        require(fees > 0, "dbXENFT: amount is zero");
        sendViaCall(payable(msg.sender), fees);
    }

    function _calculateFee(uint256 userReward, uint256 xenBurned, uint256 maturityTs, uint256 term) private returns(uint256){
        uint256 xenDifference;
        uint256 daysTillClaim;
        uint256 daysSinceMinted;
        uint256 daysDifference; 
        console.log("calculate ffffff");
        console.log("USER REWARD ESTIMATED ",userReward);
        console.log(xenBurned);
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
            daysTillClaim = ((maturityTs - block.timestamp) / SECONDS_IN_DAY);
            daysSinceMinted = term - daysTillClaim;
        } else {
            daysTillClaim = 0;
            console.log("TERM ",term);
            console.log(term * SECONDS_IN_DAY);
            console.log(block.timestamp - maturityTs);
            console.log("Curent ",block.timestamp);
            daysSinceMinted = ((term * SECONDS_IN_DAY + (block.timestamp - maturityTs))) / SECONDS_IN_DAY;
            console.log("ZILE DE LA MINT", daysSinceMinted);
        }

        if(daysSinceMinted > daysTillClaim){
            daysDifference = daysSinceMinted - daysTillClaim;
        }
        uint256 maxValue = daysDifference > 0 ? daysDifference : 0;
        console.log(maxValue);
        uint256 secondMAXVal = 5 * FIXED_POINT_FACTOR/10; //0.5
        if(maxValue != 0){
            uint256 procentageValue = ((10_000_000 - (11389 * maxValue))* FIXED_POINT_FACTOR) / MAX_BPS;
            console.log("PROCENTAJ ->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ",procentageValue);
            // if(secondMAXVal > procentageValue){
            //     return xenDifference * secondMAXVal;
            // } else {
            //     return xenDifference * procentageValue;
            // }
           return 1 ether;
        } else {
            //return 5 * FIXED_POINT_FACTOR/10;
            return  2 ether;
        }
    }

    function getQuote(uint128 amountIn) internal view returns(uint256 amountOut) {
        (int24 tick, ) = OracleLibrary.consult(WETH_XEN_POOL, 1);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, xenCrypto, WETH);
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
            console.log("intru " );
            uint256 secsLate = block.timestamp - maturityTs;
            penalty = _penalty(secsLate);
            console.log("Am penality ",penalty);
        }
        uint256 rankDiff = IXENCrypto(xenCrypto).globalRank() - cRank;
        uint256 rankDelta = rankDiff > 2 ? rankDiff : 2;
        uint256 EAA = (1000 + eeaRate);
        uint256 reward = IXENCrypto(xenCrypto).getGrossReward(rankDelta, amplifier, term, EAA);
        console.log("AM REWARD ",reward);
        return (reward * (100 - penalty)) / 100;
    }

    function _calculateUserMintReward(uint256 tokenId, uint256 mintInfo) internal view returns(uint256 userMintReward) {
        uint256 vmuCount = xenft.vmuCount(tokenId);
        (uint256 term, uint256 maturityTs, uint256 rank, uint256 amp, uint256 eea, , , , ) = mintInfo.decodeMintInfo();
        uint256 mintReward = _calculateMintReward(rank, term, maturityTs, amp, eea);
        return mintReward * vmuCount;
    }

    /**
    *   @dev confirms support for IBurnRedeemable interfaces
    */
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