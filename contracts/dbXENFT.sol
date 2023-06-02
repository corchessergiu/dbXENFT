// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
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

    uint256 public extraPowerValue;

    /**
     * Contract creation timestamp.
     * Initialized in constructor.
     */
    uint256 public immutable i_initialTimestamp;

    uint256 public totalPower;

    //mapping(uint256 => bool) public alreadyUpdateGlobalPower; 
    
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

    mapping(address => mapping(uint256 => uint256)) userPowerPerCycle;

    mapping (uint256 => uint256) public totalPowerPerCycle;

    mapping(address => uint256) public userUncalimedFees;

    mapping(uint256 => bool) public alreadyUpdateTotalPower;

    mapping(address => mapping(uint256 => bool)) public alreadyFeesUpdated;
    
    mapping(uint256 => bool) public alreadyUpdateUserPowerPerCycle;

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
        extraPowerValue = 1_000_000;
    }

    modifier updateStats(uint256 tokenId, address user) {
        uint256 currentCycle = getCurrentCycle();
        console.log("USER ",user);
        console.log("###############################Ciclul curent#################################", currentCycle);
        updateWithdrawableStakeAmount(user,currentCycle);
        updateTotalPower(currentCycle,user);
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo.decodeMintInfo();
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(userReward, xenft.xenBurned(tokenId), maturityTs, term);
        //total power fix si dam xenul procentaj din total power, scade la inceput de ciclu cu 1% si dupa se adauga inca 100
        //1% decrease pe zi 
        require(msg.value >= fee, "dbXENFT: value less than protocol fee");
        console.log("**********After functions updates********");
        console.log("USER REWARD ->>>>>>>>>>>>>>>>>>>>>>>> ",userReward);
        console.log("Before updates");
        console.log("Total power ",totalPower);
        console.log("userPowerPerCycle[user][currentCycle] ",userPowerPerCycle[user][currentCycle]);
        console.log("totalPowerPerCycle[currentCycle] ",totalPowerPerCycle[currentCycle]);
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log("cycleAccruedFees[currentCycle] ",cycleAccruedFees[currentCycle]);
        uint256 power = userReward;
        totalPower = totalPower + power;
        userPowerPerCycle[user][currentCycle] = userPowerPerCycle[user][currentCycle] + power;
        totalPowerPerCycle[currentCycle] = totalPowerPerCycle[currentCycle] + power;
        userTotalPower[user] = userTotalPower[user] + power;
        cycleAccruedFees[currentCycle] = cycleAccruedFees[currentCycle] + fee;

        console.log("After updates");
        console.log("Total power ",totalPower);
        console.log("userPowerPerCycle[user][currentCycle] ",userPowerPerCycle[user][currentCycle]);
        console.log("totalPowerPerCycle[currentCycle] ",totalPowerPerCycle[currentCycle]);
        console.log("userTotalPower[user] ",userTotalPower[user]);
        console.log("cycleAccruedFees[currentCycle] ",cycleAccruedFees[currentCycle]);
        _;
    }

    // IBurnRedeemable IMPLEMENTATION
    /**
        @dev implements IBurnRedeemable interface for burning XEN and completing update for state
     */
    function onTokenBurned(address user, uint256 amount) external {
        require(msg.sender == address(xenft), "dbXENFT: illegal callback caller");
        uint256 currentCycle = getCurrentCycle();
        lastGlobalActiveCycle = currentCycle;
        lastActiveCycle[user] = currentCycle;
    }

    /**
    * @dev Burn XENFT
    * 
    */
    function burnNFT( uint256 tokenId)
        external
        payable
        nonReentrant()
        updateStats(tokenId, msg.sender)
    {           
        require(xenft.ownerOf(tokenId) == msg.sender, "You do not own this NFT!");
        IBurnableToken(xenft).burn(msg.sender, tokenId);
    }

    function updateUserPower(address user, uint256 cycle) internal {
        console.log("***************** UPDATE USER POWER *****************");
        uint256 lastUserActiveCycle = lastActiveCycle[user];
        console.log("lastUserActiveCycle ",lastUserActiveCycle);
        console.log("Cyclul aici ", cycle);
        if(lastUserActiveCycle < cycle) {
            console.log("Se intra in if");
            uint256 numberOfInactiveCycles = cycle - lastUserActiveCycle;
            if(userWithdrawableStake[user] != 0) {
                for(uint256 index = 0 ; index < numberOfInactiveCycles; index++) {
                    if(lastUserActiveCycle != 0){
                        calculateUserPower(user, lastUserActiveCycle);
                    }
                    //calculateExtraPower(userWithdrawableStake[user],user,cycle);
                    updateFees(user, lastUserActiveCycle);
                    lastUserActiveCycle = lastUserActiveCycle +1;
                    lastActiveCycle[user] = lastUserActiveCycle;
                    console.log("lastActiveCycle ",lastActiveCycle[user]);
                } 
            } else {
                    for(uint256 index = 0 ; index < numberOfInactiveCycles; index++) {
                        calculateUserPower(user, lastUserActiveCycle);
                        updateFees(user, lastUserActiveCycle);
                        lastUserActiveCycle += 1; 
                        lastActiveCycle[user] =  lastUserActiveCycle;
                        console.log("lastActiveCycle ",lastActiveCycle[user]);
                    }
            }
        }

    }
    
    function updateWithdrawableStakeAmount(address user, uint256 currentCycle) internal {
        console.log("*****************UPDATE updateWithdrawableStakeAmount STAKE*****************");
        uint256 lastStakeCycle = userLastCycleStake[user];
        console.log("lastStakeCycle ",lastStakeCycle);
        console.log("userCycleStake[lastStakeCycle][user] ",userCycleStake[lastStakeCycle][user]);
        console.log("userLastCycleStake[user] ",userLastCycleStake[user]);
        console.log(" userWithdrawableStake[user] ", userWithdrawableStake[user]);
        if(userCycleStake[lastStakeCycle][user] != 0 && userLastCycleStake[user] != currentCycle){
            userWithdrawableStake[user] = userWithdrawableStake[user] + userCycleStake[lastStakeCycle][user];
            userCycleStake[lastStakeCycle][user] = 0;
            userLastCycleStake[user] = 0;
        }
        console.log("AFTER ");
        console.log(" userWithdrawableStake[user] ", userWithdrawableStake[user]);
        console.log("userCycleStake[lastStakeCycle][user] ",userCycleStake[lastStakeCycle][user]);
        console.log("userLastCycleStake[user] ",userLastCycleStake[user]);
        console.log("****************FINISH PE withdrawable*******************");
    }

    function calculateUserPower(address user, uint256 cycle) internal {
        console.log("CALCULATE USER POWER FUNCTION");
        console.log("cycle ",cycle);
        console.log("User power before div ", userTotalPower[user]);
        uint256 userLocalPower = userTotalPower[user] * 10000 / 10020;
        console.log("User power after div ", userLocalPower);
        if(userTotalPower[user] == 0) {
            console.log("se intra pe primul caz ");
            userTotalPower[user] = 0;
            userPowerPerCycle[user][cycle] = 0;
            alreadyUpdateUserPower[user][cycle] = true;
            alreadyUpdateUserPowerPerCycle[cycle] = true;
        } else {
            if(cycle != 0 && alreadyUpdateUserPower[user][cycle] == false){
                if(userLocalPower  > 1 ether) {
                    console.log("Mai mare rezultatul decat 1");
                    userTotalPower[user] = userLocalPower;
                    userPowerPerCycle[user][cycle] = userLocalPower;
                    alreadyUpdateUserPower[user][cycle] = true;
                    alreadyUpdateUserPowerPerCycle[cycle] = true;
                } else {
                    console.log("Mai mic rezultatul decat 1");
                    userTotalPower[user] = 1 * 10 **18;
                    userPowerPerCycle[user][cycle] =  1 * 10 **18;
                    alreadyUpdateUserPower[user][cycle] = true;
                    alreadyUpdateUserPowerPerCycle[cycle] = true;
                }
            }
        }
        console.log("DUPA UPDATE DE USER POWER AVEM ");
        console.log(" userTotalPower[user] ", userTotalPower[user]);
        console.log("userPowerPerCycle[user][cycle] ",userPowerPerCycle[user][cycle]);
    }

    function updateTotalPower(uint256 cycle, address user) internal {
        console.log("***************updateTotalPower function******************");
        console.log("cycle ",cycle);
        console.log("Power before div ",totalPower);
        uint256 power = totalPower * 10000 / 10020;
        console.log("Power after div ",power);
        uint256 numberOfInactiveCycles = cycle - lastGlobalActiveCycle;
        console.log("numberOfInactiveCycles ",numberOfInactiveCycles);
        for(uint256 index = 0 ; index < numberOfInactiveCycles; index++) {
            if(cycle != 0 && alreadyUpdateTotalPower[cycle] == false) {
                if(power < 1 ether){
                    totalPower = 1 * 10 **18;
                    alreadyUpdateTotalPower[cycle] = true;
                } else {
                    totalPower = power;
                    alreadyUpdateTotalPower[cycle] = true;
                }
            console.log("Total now ",totalPower);
            power = totalPower * 10000 / 10020;
            console.log("Total now after div ",power);
            totalPowerPerCycle[cycle] = totalPower;
            console.log("Total power per cycle ",totalPowerPerCycle[cycle]);
            }
        }
        console.log("CALL CATRE UPDATE USER POWER ->>>>>>>>>>>>>>>>>>>");
        updateUserPower(user, cycle);
    }
    
    // function calculateExtraPower(uint256 amountOfDXNStaked, address user, uint256 cycle) internal {
    //     console.log("Intru pe extra power ");
    //     uint256 extraAmountOfPower = amountOfDXNStaked * extraPowerValue;
    //     userPowerPerCycle[user][cycle] += extraAmountOfPower;
    //     userTotalPower[user] = userTotalPower[user]  + extraAmountOfPower;
    //     totalPower += extraAmountOfPower;
    //     totalPowerPerCycle[cycle] =  totalPower;
    // }

    function updateFees(address user, uint256 cycle) internal {
        console.log("UPDATE FEE FUNCTION");
        console.log("cyclu ", cycle);
        console.log("alreadyFeesUpdated[user][cycle] ",alreadyFeesUpdated[user][cycle]);
        console.log("cycleAccruedFees[cycle] " ,cycleAccruedFees[cycle]);
        console.log(" userPowerPerCycle[user][cycle] ", user," ", userPowerPerCycle[user][cycle]);
        console.log(" totalPowerPerCycle[cycle] ",totalPowerPerCycle[cycle]);
        console.log("Acumulat pana acum ",userUncalimedFees[user]);
        if(alreadyFeesUpdated[user][cycle] == false && cycleAccruedFees[cycle] != 0){
            if(totalPowerPerCycle[cycle] != 0){
                userUncalimedFees[user] = userUncalimedFees[user] + ((userPowerPerCycle[user][cycle] * cycleAccruedFees[cycle])/totalPowerPerCycle[cycle]); 
            }
            alreadyFeesUpdated[user][cycle] = true;
        }
        console.log("USERUL CU ADRESA ",user, " are de luat:");
        console.log(" userUncalimedFees[user] ", userUncalimedFees[user]);
    }

    //punem un anumit numar pe fiecare xen sau cum se trateaa aici?
    function stake(uint256 amount)
        external
        nonReentrant()
    {   
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender,currentCycle);
        updateTotalPower(currentCycle, msg.sender);
        require(amount > 0, "DBXen: amount is zero");
        userLastCycleStake[msg.sender] = currentCycle;
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender] + amount;
        userCycleStake[currentCycle][msg.sender] = userCycleStake[currentCycle][msg.sender] + amount;
        uint256 extraAmountOfPower = amount * extraPowerValue;
        userPowerPerCycle[user][cycle] += extraAmountOfPower;
        userTotalPower[user] = userTotalPower[user]  + extraAmountOfPower;
        totalPower += extraAmountOfPower;
        totalPowerPerCycle[cycle] =  totalPower;
        dxn.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake()
        external
        nonReentrant()
    {   
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender,currentCycle);
        require(
            userWithdrawableStake[msg.sender] > 0,
            "dbXENFT: your stake amount is 0"
        );
        updateTotalPower(currentCycle, msg.sender);
        uint256 extraAmountOfPower = userWithdrawableStake[msg.sender] * extraPowerValue;
        userPowerPerCycle[user][cycle] -= extraAmountOfPower;
        userTotalPower[user] = userTotalPower[user]  - extraAmountOfPower;
        totalPower -= extraAmountOfPower;
        totalPowerPerCycle[cycle] =  totalPower;
        userWithdrawableStake[msg.sender] = 0;
        userStakedAmount[msg.sender] = 0;
        dxn.safeTransfer(msg.sender, userWithdrawableStake[msg.sender]);
    }

    function claimFees() external {
        //claim fee partial
        updateWithdrawableStakeAmount(msg.sender,getCurrentCycle());
        updateTotalPower(getCurrentCycle(), msg.sender);
        uint256 fees = userUncalimedFees[msg.sender];
        require(fees > 0, "dbXENFT: amount is zero");
        userUncalimedFees[msg.sender] = 0;
        sendViaCall(payable(msg.sender), fees);
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
            daysTillClaim = ((maturityTs - block.timestamp) / SECONDS_IN_DAY);
            daysSinceMinted = term - daysTillClaim;
        } else {
            daysTillClaim = 0;
            //console.log("TERM ",term);
            daysSinceMinted = ((term * SECONDS_IN_DAY + (block.timestamp - maturityTs))) / SECONDS_IN_DAY;
            //console.log("ZILE DE LA MINT", daysSinceMinted);
        }

        //console.log("daysTillClaim ",daysTillClaim);
        //console.log("daysSinceMinted ",daysSinceMinted);

        if(daysSinceMinted > daysTillClaim){
            daysDifference = daysSinceMinted - daysTillClaim;
        }
        //console.log("daysDifference ",daysDifference);
        uint256 firstMaxValue = daysDifference > 0 ? daysDifference : 0;
        //console.log("maxValue first ",firstMaxValue);
        uint256 maxResult;
        uint256 xenDifXmaxResult;
        if(firstMaxValue != 0){
            uint256 procentageValue = ((10_000_000 - (11389 * firstMaxValue))* FIXED_POINT_FACTOR) / MAX_BPS;
            //console.log("PROCENTAJ ->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ",procentageValue);
            maxResult = procentageValue > 0.5 ether ? procentageValue : 0.5 ether;
            //console.log("max result " ,maxResult);
            xenDifXmaxResult = (xenDifference * maxResult/FIXED_POINT_FACTOR)/(1_000_000_000*FIXED_POINT_FACTOR);
            //console.log("xenDifXmaxResult ",xenDifXmaxResult);
            //console.log(xenDifXmaxResult > 0.001 ether ? xenDifXmaxResult : 0.001 ether);
            return xenDifXmaxResult > 0.001 ether ? xenDifXmaxResult : 0.001 ether;
        } else {
            //console.log((xenDifference/(1_000_000_000*FIXED_POINT_FACTOR)) > 0.001 ether ? xenDifference/(1_000_000_000*FIXED_POINT_FACTOR) : 0.001 ether);
            return (xenDifference/(1_000_000_000*FIXED_POINT_FACTOR)) > 0.001 ether ? xenDifference/(1_000_000_000*FIXED_POINT_FACTOR) : 0.001 ether;
        }
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
        return mintReward * vmuCount * 1 ether;
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