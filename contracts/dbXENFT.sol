// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IXENCrypto.sol";
import "./libs/MintInfo.sol";
import "./XENFT.sol";
import "./DBXenERC20.sol";
import "./DBXENFT.sol";
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

    DBXENFT public immutable DBXENFTInstance;

    /**
     * Power for the previous cycle.
     */
    uint256 public lastCyclePower;

    uint256 public lastGlobalActiveCycle;

    uint256 public currentCycle;

    uint256 public previousStartedCycle;

    uint256 public currentStartedCycle;

    uint256 public lastStartedCycle;

    uint256 public currentCycleReward;

    uint256 public lastCycleReward;

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

    mapping(uint256 => uint256) public dbxenftEntryPower;

    mapping(address => mapping(uint256 => uint256)) userPowerPerCycle;

    mapping(uint256 => uint256) public totalPowerPerCycle;

    mapping(address => uint256) public userUncalimedFees;

    mapping(uint256 => bool) public alreadyUpdateTotalPower;

    mapping(address => mapping(uint256 => bool)) public alreadyFeesUpdated;

    mapping(address => mapping(uint256 => uint256))
        public userTotalPowerPerCycle;

    mapping(uint256 => bool) public alreadyUpdateUserPowerPerCycle;

    mapping(uint256 => uint256) public totalGlobalPower;

    mapping(uint256 => uint256) public tokenEntryPower;

    mapping(uint256 => uint256) public summedCycleStakes;

    mapping(uint256 => uint256) public cycleFeesPerStakeSummed;

    mapping(uint256 => uint256) public rewardPerCycle;

    event NewCycleStarted(
        uint256 indexed cycle,
        uint256 calculatedCycleReward,
        uint256 summedCycleStakes
    );

    modifier updateStats(uint256 tokenId, address user) {
        uint256 currentCycle = getCurrentCycle();
        console.log("USER ", user);
        console.log(
            "###############################Ciclul curent#################################",
            currentCycle
        );
        updateWithdrawableStakeAmount(user, currentCycle);
        updateTotalPower(currentCycle, user);
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo
            .decodeMintInfo();
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(
            userReward,
            xenft.xenBurned(tokenId),
            maturityTs,
            term
        );
        uint256 power = userReward;
        //userPowerPerCycle[user][currentCycle] = userPowerPerCycle[user][currentCycle] + power;
        cycleAccruedFees[currentCycle] = cycleAccruedFees[currentCycle] + fee;
        totalPowerPerCycle[currentCycle] += power;
        console.log("After updates");
        //console.log("Total power ",totalPower);
        console.log(
            "userPowerPerCycle[user][currentCycle] ",
            userPowerPerCycle[user][currentCycle]
        );
        console.log(
            "totalPowerPerCycle[currentCycle] ",
            totalPowerPerCycle[currentCycle]
        );
        console.log(
            "cycleAccruedFees[currentCycle] ",
            cycleAccruedFees[currentCycle]
        );
        _;
    }

    modifier onlyNFTOwner(
        ERC721 tokenAddress,
        tokenId,
        address user
    ) {
        require(
            tokenAddress.ownerOf(tokenId) == user,
            "You do not own this NFT!"
        );
        _;
    }

    // IBurnRedeemable IMPLEMENTATION
    /**
        @dev implements IBurnRedeemable interface for burning XEN and completing update for state
     */
    function onTokenBurned(address user, uint256 amount) external {
        require(
            msg.sender == address(xenft),
            "dbXENFT: illegal callback caller"
        );
        uint256 currentCycle = getCurrentCycle();
        lastGlobalActiveCycle = currentCycle;
        lastActiveCycle[user] = currentCycle;
    }

    /**
     * @param xenftAddress XENFT contract address.
     */
    constructor(
        address dbxAddress,
        address xenftAddress,
        address _xenCrypto,
        address _WETH,
        address _WETH_XEN_POOL
    ) {
        dxn = DBXenERC20(dbxAddress);
        xenft = XENTorrent(xenftAddress);
        xenCrypto = _xenCrypto;
        WETH = _WETH;
        WETH_XEN_POOL = _WETH_XEN_POOL;
        newImagePeriodDuration = SECONDS_IN_YEAR;
        i_periodDuration = 1 days;
        i_initialTimestamp = block.timestamp;
        extraPowerValue = 1_000_000;
        totalGlobalPower[0] = 10_000;
        DBXENFTInstance = new DBXENFT();
        currentCycleReward = 10000 * 1e18;
        summedCycleStakes[0] = 10000 * 1e18;
        rewardPerCycle[0] = 10000 * 1e18;
    }

    /**
     * @dev Burn XENFT
     *
     */
    function burnNFT(
        uint256 tokenId
    ) external payable nonReentrant onlyNFTOwner(xenft, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        setUpNewCycle();

        uint256 mintInfo = xenft.mintInfo(tokenId);

        (uint256 term, uint256 maturityTs, , , , , , , ) = mintInfo
            .decodeMintInfo();

        uint256 estimatedReward = _calculateUserMintReward(tokenId, mintInfo);

        uint256 fee = _calculateFee(
            estimatedReward,
            xenft.xenBurned(tokenId),
            maturityTs,
            term
        );
        require(msg.value >= fee, "Payment less than fee");

        uint256 dbxenftId = DBXENFTInstance.mintDBXENFT(msg.sender);
        tokenEntryPower[dbxenftId] = estimatedReward;
        cycleAccruedFees[currentCycle] = cycleAccruedFees[currentCycle] + fee;
        totalPowerPerCycle[currentCycle] += estimatedReward;

        xenft.transferFrom(msg.sender, address(this), tokenId);
    }

    function updateWithdrawableStakeAmount(
        address user,
        uint256 currentCycle
    ) internal {
        console.log(
            "*****************UPDATE updateWithdrawableStakeAmount STAKE*****************"
        );
        uint256 lastStakeCycle = userLastCycleStake[user];
        console.log("lastStakeCycle ", lastStakeCycle);
        console.log(
            "userCycleStake[lastStakeCycle][user] ",
            userCycleStake[lastStakeCycle][user]
        );
        console.log("userLastCycleStake[user] ", userLastCycleStake[user]);
        console.log(
            " userWithdrawableStake[user] ",
            userWithdrawableStake[user]
        );
        if (
            userCycleStake[lastStakeCycle][user] != 0 &&
            userLastCycleStake[user] != currentCycle
        ) {
            userWithdrawableStake[user] =
                userWithdrawableStake[user] +
                userCycleStake[lastStakeCycle][user];
            userCycleStake[lastStakeCycle][user] = 0;
            userLastCycleStake[user] = 0;
        }
        console.log("AFTER ");
        console.log(
            " userWithdrawableStake[user] ",
            userWithdrawableStake[user]
        );
        console.log(
            "userCycleStake[lastStakeCycle][user] ",
            userCycleStake[lastStakeCycle][user]
        );
        console.log("userLastCycleStake[user] ", userLastCycleStake[user]);
        console.log(
            "****************FINISH PE withdrawable*******************"
        );
    }

    function updatePowerForUser(address user, uint256 cycle) internal {
        uint256 userLastActiveCycle = lastActiveCycle[user];
        uint256 numberOfInactiveCycles = cycle - userLastActiveCycle;
        uint256 intermediateCycle = userLastActiveCycle;

        for (uint256 index = 0; index < numberOfInactiveCycles; index++) {
            if (alreadyUpdateUserPower[user][intermediateCycle] == false) {
                alreadyUpdateUserPower[user][intermediateCycle] = true;
                userTotalPowerPerCycle[user][intermediateCycle] =
                    (userPowerPerCycle[user][intermediateCycle] *
                        totalGlobalPower[intermediateCycle]) /
                    totalPowerPerCycle[intermediateCycle];
            }
        }
    }

    function updateTotalPower(uint256 cycle, address user) internal {
        console.log(
            "***************updateTotalPower function******************"
        );
        console.log("cycle ", cycle);
        console.log("Power before div ", totalPower);
        uint256 intermediateCycle = lastGlobalActiveCycle;
        console.log("lastGlobalActiveCycle ", intermediateCycle);
        uint256 localPower;
        if (cycle > 0 && intermediateCycle != 0) {
            uint256 numberOfInactiveCycles = cycle - lastGlobalActiveCycle;
            for (uint256 index = 0; index < numberOfInactiveCycles; index++) {
                console.log(
                    "alreadyUpdateTotalPower[intermediateCycle] ",
                    alreadyUpdateTotalPower[intermediateCycle]
                );
                console.log("intermediateCycle ", intermediateCycle);
                if (alreadyUpdateTotalPower[intermediateCycle] == false) {
                    alreadyUpdateTotalPower[intermediateCycle] = true;
                    console.log(
                        "totalPowerPerCycle[intermediateCycle - 1] ",
                        totalPowerPerCycle[intermediateCycle - 1]
                    );
                    localPower =
                        (totalPowerPerCycle[intermediateCycle - 1] * 10000) /
                        1000000;
                    console.log("Total now after div ", localPower);
                    totalGlobalPower[intermediateCycle] = localPower;
                    console.log(
                        " totalGlobalPower[intermediateCycle] ->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ",
                        intermediateCycle
                    );
                    intermediateCycle += 1;
                }
            }
        }
        updatePowerForUser(user, cycle);
        console.log("CALL CATRE UPDATE USER POWER ->>>>>>>>>>>>>>>>>>>");
    }

    function calculateExtraPower(
        uint256 amountOfDXNStaked,
        address user,
        uint256 cycle
    ) internal {
        console.log("Intru pe extra power ");
        uint256 extraAmountOfPower = amountOfDXNStaked * extraPowerValue;
        userPowerPerCycle[user][cycle] += extraAmountOfPower;
    }

    function updateFees(address user, uint256 cycle) internal {
        console.log("UPDATE FEE FUNCTION");
        console.log("cyclu ", cycle);
        console.log(
            "alreadyFeesUpdated[user][cycle] ",
            alreadyFeesUpdated[user][cycle]
        );
        console.log("cycleAccruedFees[cycle] ", cycleAccruedFees[cycle]);
        console.log(
            " userPowerPerCycle[user][cycle] ",
            user,
            " ",
            userPowerPerCycle[user][cycle]
        );
        console.log(" totalPowerPerCycle[cycle] ", totalPowerPerCycle[cycle]);
        console.log("Acumulat pana acum ", userUncalimedFees[user]);
        if (
            alreadyFeesUpdated[user][cycle] == false &&
            cycleAccruedFees[cycle] != 0
        ) {
            if (totalPowerPerCycle[cycle] != 0) {
                userUncalimedFees[user] =
                    userUncalimedFees[user] +
                    ((userPowerPerCycle[user][cycle] *
                        cycleAccruedFees[cycle]) / totalPowerPerCycle[cycle]);
            }
            alreadyFeesUpdated[user][cycle] = true;
        }
        console.log("USERUL CU ADRESA ", user, " are de luat:");
        console.log(" userUncalimedFees[user] ", userUncalimedFees[user]);
    }

    //punem un anumit numar pe fiecare xen sau cum se trateaa aici?
    function stake(uint256 amount) external nonReentrant {
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender, currentCycle);
        updateTotalPower(currentCycle, msg.sender);
        require(amount > 0, "DBXen: amount is zero");
        userLastCycleStake[msg.sender] = currentCycle;
        userStakedAmount[msg.sender] = userStakedAmount[msg.sender] + amount;
        userCycleStake[currentCycle][msg.sender] =
            userCycleStake[currentCycle][msg.sender] +
            amount;
        uint256 extraAmountOfPower = amount * extraPowerValue;
        userPowerPerCycle[msg.sender][currentCycle] += extraAmountOfPower;
        totalPowerPerCycle[currentCycle] += extraAmountOfPower;
        dxn.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake() external nonReentrant {
        uint256 currentCycle = getCurrentCycle();
        updateWithdrawableStakeAmount(msg.sender, currentCycle);
        require(
            userWithdrawableStake[msg.sender] > 0,
            "dbXENFT: your stake amount is 0"
        );
        updateTotalPower(currentCycle, msg.sender);
        uint256 extraAmountOfPower = userWithdrawableStake[msg.sender] *
            extraPowerValue;
        userPowerPerCycle[msg.sender][currentCycle] -= extraAmountOfPower;
        userWithdrawableStake[msg.sender] = 0;
        totalPowerPerCycle[currentCycle] -= extraAmountOfPower;
        userStakedAmount[msg.sender] = 0;
        dxn.safeTransfer(msg.sender, userWithdrawableStake[msg.sender]);
    }

    function claimFees() external {
        updateWithdrawableStakeAmount(msg.sender, getCurrentCycle());
        updateTotalPower(getCurrentCycle(), msg.sender);
        uint256 fees = userUncalimedFees[msg.sender];
        require(fees > 0, "dbXENFT: amount is zero");
        userUncalimedFees[msg.sender] = 0;
        sendViaCall(payable(msg.sender), fees);
    }

    function _calculateFee(
        uint256 userReward,
        uint256 xenBurned,
        uint256 maturityTs,
        uint256 term
    ) private returns (uint256) {
        uint256 xenDifference;
        uint256 daysTillClaim;
        uint256 daysSinceMinted;
        uint256 daysDifference;

        if (userReward > xenBurned) {
            xenDifference = userReward - xenBurned;
        } else {
            if (xenBurned == 0 && userReward == 0)
                return (1 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 250_000_000 * FIXED_POINT_FACTOR)
                return (22 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 500_000_000 * FIXED_POINT_FACTOR) return 2 ether;
            if (xenBurned == 1_000_000_000 * FIXED_POINT_FACTOR)
                return (18 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 2_000_000_000 * FIXED_POINT_FACTOR)
                return (16 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 2_500_000_000 * FIXED_POINT_FACTOR)
                return (14 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 5_000_000_000 * FIXED_POINT_FACTOR)
                return (12 * FIXED_POINT_FACTOR) / 10;
            if (xenBurned == 10_000_000_000 * FIXED_POINT_FACTOR)
                return 1 ether;
        }

        if (block.timestamp < maturityTs) {
            daysTillClaim = ((maturityTs - block.timestamp) / SECONDS_IN_DAY);
            daysSinceMinted = term - daysTillClaim;
        } else {
            daysTillClaim = 0;
            //console.log("TERM ",term);
            daysSinceMinted =
                ((term * SECONDS_IN_DAY + (block.timestamp - maturityTs))) /
                SECONDS_IN_DAY;
            //console.log("ZILE DE LA MINT", daysSinceMinted);
        }

        //console.log("daysTillClaim ",daysTillClaim);
        //console.log("daysSinceMinted ",daysSinceMinted);

        if (daysSinceMinted > daysTillClaim) {
            daysDifference = daysSinceMinted - daysTillClaim;
        }
        //console.log("daysDifference ",daysDifference);
        uint256 firstMaxValue = daysDifference > 0 ? daysDifference : 0;
        //console.log("maxValue first ",firstMaxValue);
        uint256 maxResult;
        uint256 xenDifXmaxResult;
        if (firstMaxValue != 0) {
            uint256 procentageValue = ((10_000_000 - (11389 * firstMaxValue)) *
                FIXED_POINT_FACTOR) / MAX_BPS;
            //console.log("PROCENTAJ ->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> ",procentageValue);
            maxResult = procentageValue > 0.5 ether
                ? procentageValue
                : 0.5 ether;
            //console.log("max result " ,maxResult);
            xenDifXmaxResult =
                ((xenDifference * maxResult) / FIXED_POINT_FACTOR) /
                (1_000_000_000 * FIXED_POINT_FACTOR);
            //console.log("xenDifXmaxResult ",xenDifXmaxResult);
            //console.log(xenDifXmaxResult > 0.001 ether ? xenDifXmaxResult : 0.001 ether);
            return
                xenDifXmaxResult > 0.001 ether ? xenDifXmaxResult : 0.001 ether;
        } else {
            //console.log((xenDifference/(1_000_000_000*FIXED_POINT_FACTOR)) > 0.001 ether ? xenDifference/(1_000_000_000*FIXED_POINT_FACTOR) : 0.001 ether);
            return
                (xenDifference / (1_000_000_000 * FIXED_POINT_FACTOR)) >
                    0.001 ether
                    ? xenDifference / (1_000_000_000 * FIXED_POINT_FACTOR)
                    : 0.001 ether;
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
        if (block.timestamp > maturityTs) {
            uint256 secsLate = block.timestamp - maturityTs;
            penalty = _penalty(secsLate);
        }
        uint256 rankDiff = IXENCrypto(xenCrypto).globalRank() - cRank;
        uint256 rankDelta = rankDiff > 2 ? rankDiff : 2;
        uint256 EAA = (1000 + eeaRate);
        uint256 reward = IXENCrypto(xenCrypto).getGrossReward(
            rankDelta,
            amplifier,
            term,
            EAA
        );
        return (reward * (100 - penalty)) / 100;
    }

    function _calculateUserMintReward(
        uint256 tokenId,
        uint256 mintInfo
    ) internal view returns (uint256 userMintReward) {
        uint256 vmuCount = xenft.vmuCount(tokenId);
        (
            uint256 term,
            uint256 maturityTs,
            uint256 rank,
            uint256 amp,
            uint256 eea,
            ,
            ,
            ,

        ) = mintInfo.decodeMintInfo();
        uint256 mintReward = _calculateMintReward(
            rank,
            term,
            maturityTs,
            amp,
            eea
        );
        return mintReward * vmuCount * 1 ether;
    }

    /**
     *   @dev confirms support for IBurnRedeemable interfaces
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IBurnRedeemable).interfaceId;
    }

    function updateCycleFeesPerStakeSummed() internal {
        if (currentCycle != currentStartedCycle) {
            previousStartedCycle = lastStartedCycle + 1;
            lastStartedCycle = currentStartedCycle;
        }

        if (
            currentCycle > lastStartedCycle &&
            cycleFeesPerStakeSummed[lastStartedCycle + 1] == 0
        ) {
            uint256 feePerStake =
                    ((cycleAccruedFees[lastStartedCycle] + pendingFees) *
                        SCALING_FACTOR) /
                    summedCycleStakes[lastStartedCycle];

            cycleFeesPerStakeSummed[lastStartedCycle + 1] =
                cycleFeesPerStakeSummed[previousStartedCycle] +
                feePerStake;
        }
    }

    function setUpNewCycle() internal {
        if (rewardPerCycle[currentCycle] == 0) {
            lastCycleReward = currentCycleReward;
            uint256 calculatedCycleReward = lastCycleReward +
                (lastCycleReward / 100);
            currentCycleReward = calculatedCycleReward;
            rewardPerCycle[currentCycle] = calculatedCycleReward;

            currentStartedCycle = currentCycle;

            summedCycleStakes[currentStartedCycle] +=
                summedCycleStakes[lastStartedCycle] +
                currentCycleReward;

            if (pendingStake != 0) {
                summedCycleStakes[currentStartedCycle] += pendingStake;
                pendingStake = 0;
            }

            if (pendingStakeWithdrawal != 0) {
                summedCycleStakes[
                    currentStartedCycle
                ] -= pendingStakeWithdrawal;
                pendingStakeWithdrawal = 0;
            }

            emit NewCycleStarted(
                currentCycle,
                calculatedCycleReward,
                summedCycleStakes[currentStartedCycle]
            );
        }
    }

    /**
     * @dev Returns the index of the cycle at the current block time.
     */
    function getCurrentCycle() public view returns (uint256) {
        return (block.timestamp - i_initialTimestamp) / i_periodDuration;
    }

    function calculateCycle() internal {
        uint256 calculatedCycle = getCurrentCycle();

        if (calculatedCycle > currentCycle) {
            currentCycle = calculatedCycle;
        }
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
