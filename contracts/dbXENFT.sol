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

    mapping(uint256 => mapping(address => uint256)) public userPowerPerCycle;
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
        console.log();
        console.log("***************************** ->> ciclu curent ", getCurrentCycle());
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo.decodeMintInfo();
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(userReward, xenft.xenBurned(tokenId), maturityTs, term) /10000;
        //require(msg.value >= fee, "dbXENFT: value less than protocol fee");
        uint256 power = 10000000000000000000;
        console.log("userReward  ", power);
        console.log("totalPower before  ", totalPower);
        totalPower += power;
        console.log("totalPower  ", totalPower);
        userTotalPower[msg.sender] = userTotalPower[msg.sender] + power;
        userPowerPerCycle[getCurrentCycle()][msg.sender] = userPowerPerCycle[getCurrentCycle()][msg.sender] + power;
        console.log("userPowerPerCycle[getCurrentCycle()][msg.sender]  ", userPowerPerCycle[getCurrentCycle()][msg.sender]);
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
        updateUserStake(user);
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
        require(xenft.ownerOf(tokenId) == msg.sender, "You do not own this NFT!");
        IBurnableToken(xenft).burn(user, tokenId);
    }

    /**
     * @dev Updates the global state related to starting a new cycle along 
     * with helper state variables used in computation of staking rewards.
     */
    function setUpNewCycle() internal {
        if (alreadyUpdatePower[getCurrentCycle()] == false) {
            lastCyclePower = totalPower;
            console.log("LA DIV ", totalPower);
            totalPower = (lastCyclePower * 10000) / 10020;
            console.log("AFTER DIV ", totalPower);
            alreadyUpdatePower[getCurrentCycle()] = true;
        }
    }

    function updateUserStake(address user) internal {
        if(userCycleStake[userLastCycleStake[user]][user] != 0 && userLastCycleStake[user] != getCurrentCycle()){
            userWithdrawableStake[msg.sender] = userWithdrawableStake[msg.sender] + userCycleStake[userLastCycleStake[user]][user];
            userCycleStake[userLastCycleStake][user] = 0;
            userLastCycleStake[user] = 0;
        }
    }

    function updateUserPower(address user) internal {
        console.log("UPDATE USER POWER");
        uint256 lastActiveCycle = lastActiveCycle[user];
        uint256 currentCycle = getCurrentCycle();
        console.log("active cycle last ",lastActiveCycle);
        console.log("currnet cycle ",currentCycle);
        if(lastActiveCycle < currentCycle && lastActiveCycle != 0){
            uint256 numberOfInactiveCycles = currentCycle - lastActiveCycle;
             console.log("numberOfInactiveCycles ", numberOfInactiveCycles);
            for(uint256 index = lastActiveCycle ; index < numberOfInactiveCycles; index++) {
                console.log("index ",index);
                console.log("before div ", userTotalPower[user]);
                console.log("before div pe ciclu", userPowerPerCycle[index][user]);
                userPowerPerCycle[index][user] = userPowerPerCycle[index][user] * 10000 / 10020;
                userTotalPower[user] = userTotalPower[user] * 10000 / 10020;
                console.log("after div ", userTotalPower[user]);
                console.log("after div pe ciclu", userPowerPerCycle[index][user]);
            } 
        }
        if( currentCycle == 0){
            console.log("here");
            userPowerPerCycle[0][user] = userPowerPerCycle[0][user] * 10000 / 10020;
            userTotalPower[user] = userTotalPower[user] * 10000 / 10020;
            console.log("after here ", userTotalPower[user]);
            console.log("after here", userPowerPerCycle[0][user]);
        }
    }

    //punem un anumit numar pe fiecare xen sau cum se trateaa aici?
    function stake(uint256 amount)
        external
        nonReentrant()
    {
        require(amount > 0, "DBXen: amount is zero");
        updateUserPower(user);
        updateUserStake(msg.sender);
        uint256 currentCycle = getCurrentCycle();
        userPowerPerCycle[currentCycle][msg.sender] = userPowerPerCycle[currentCycle][msg.sender] + 1;
        userTotalPower[msg.sender] = userTotalPower[msg.sender] + 1;
        totalPower = totalPower + 1;
        userLastCycleStake[msg.sender] = currentCycle;
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender] + amount;
        userCycleStake[currentCycle][msg.sender] = userCycleStake[currentCycle][msg.sender] + amount;
        dxn.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake(uint256 amount)
        external
        nonReentrant()
    {
        require(amount > 0, "dbXENFT: amount is zero");

        require(
            amount <= userStakedAmount[msg.sender],
            "dbXENFT: amount greater than withdrawable stake"
        );
        updateUserPower(msg.sender);
        updateUserStake(msg.sender);
        uint256 currentCycle = getCurrentCycle();
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender] - amount;
        userWithdrawableStake[msg.sender] = userWithdrawableStake[msg.sender] - amount;
        dxn.safeTransfer(msg.sender, amount);
    }

    function claimFees() external {
        updateUserStake(msg.sender);
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

        // console.log("1 ",daysSinceMinted);   
        // console.log("3 ",daysTillClaim);

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