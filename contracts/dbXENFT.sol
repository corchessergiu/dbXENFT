// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
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

    uint256 public currentCycle;

    uint256 public previousStartedCycle;

    uint256 public currentStartedCycle;

    uint256 public lastStartedCycle;

    uint256 public currentCycleReward;

    uint256 public lastCycleReward;

    uint256 public constant SECONDS_IN_DAY = 3_600 * 24;

    uint256 public constant MAX_PENALTY_PCT = 99;

    /**
     * Basis points representation of 100 percent.
     */
    uint256 public constant MAX_BPS = 10_000_000;

    uint256 public constant BASE_XEN = 1_000_000_000;

    uint256 public constant SCALING_FACTOR = 1e40;

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

    uint256 public pendingExtraPower;

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;

    mapping(uint256 => uint256) public totalPowerPerCycle;

    mapping(uint256 => uint256) public totalGlobalPower;

    mapping(uint256 => uint256) public totalExtraEntryPower;

    mapping(uint256 => uint256) public tokenEntryPower;

    mapping(uint256 => uint256) public tokenEntryCycle;

    mapping(uint256 => uint256) public dxnExtraEntryPower;

    mapping(uint256 => uint256) public tokenEntryPowerWithStake;

    mapping(uint256 => uint256) public DBXeNFTPower;

    mapping(uint256 => uint256) public baseDBXeNFTPower;

    mapping(uint256 => uint256) public summedCycleStakes;

    mapping(uint256 => uint256) public cycleFeesPerStakeSummed;

    mapping(uint256 => uint256) public rewardPerCycle;

    mapping(uint256 => uint256) public tokenFirstStake;

    mapping(uint256 => uint256) public tokenSecondStake;

    mapping(uint256 => mapping(uint256 => uint256)) tokenStakeCycle;

    mapping(uint256 => uint256) pendingDXN;

    mapping(address => uint256) public tokenAccruedFees;

    mapping(uint256 => uint256) public precedentStartedCycle;

    mapping(uint256 => uint256) public lastFeeUpdateCycle;

    mapping(address => uint256) public tokenWithdrawableStake;

    mapping(uint256 => uint256) public tokenUnderlyingXENFT;

    uint256 public pendingStakeWithdrawal;

    event NewCycleStarted(
        uint256 indexed cycle,
        uint256 calculatedCycleReward,
        uint256 summedCycleStakes
    );

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
        i_periodDuration = 1 days;
        i_initialTimestamp = block.timestamp;
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
            maturityTs,
            term
        );
        require(msg.value >= fee, "Payment less than fee");

        uint256 dbxenftId = DBXENFTInstance.mintDBXENFT(msg.sender);
        tokenEntryPower[dbxenftId] = estimatedReward;
        tokenEntryCycle[dbxenftId] = currentCycle;
        cycleAccruedFees[currentCycle] = cycleAccruedFees[currentCycle] + fee;
        totalPowerPerCycle[currentCycle] += estimatedReward;
        tokenUnderlyingXENFT[dbxenftId] = tokenId;

        xenft.transferFrom(msg.sender, address(this), tokenId);
    }

    function calcStakeFee(uint256 dxnAmount) internal returns(uint256 stakeFee){
        stakeFee = dxnAmount / 1000;
    }

    function calcExtraPower(uint256 power, uint256 dxnAmount) internal pure returns(uint256 calcPower){
        calcPower = power * dxnAmount / 1e21;
    }

    //punem un anumit numar pe fiecare xen sau cum se trateaa aici?
    function stake(uint256 amount, uint256 tokenId) external payable nonReentrant onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateTotalPower(currentCycle, msg.sender);
        require(amount > 0, "DBXen: amount is zero");
        require(tokenEntryPower[tokenId] != 0, "DBXeNFT does not exist");
        uint256 stakeFee = calcStakeFee(amount);
        require(msg.value >= stakeFee, "Value less than staking fee");
        uint256 cycleToSet = currentCycle + 1;

        if (lastStartedCycle == currentStartedCycle) {
            cycleToSet = currentCycle;
        }

        if (
            (cycleToSet != tokenFirstStake[tokenId] &&
                cycleToSet != tokenSecondStake[tokenId])
        ) {
            if (tokenFirstStake[tokenId] == 0) {
                tokenFirstStake[tokenId] = cycleToSet;
            } else if (tokenSecondStake[tokenId] == 0) {
                tokenSecondStake[tokenId] = cycleToSet;
            }
        }

        tokenStakeCycle[tokenId][cycleToSet] += amount;
        pendingDXN[tokenId] += amount;

        uint256 extraPower = calcExtraPower(amount, tokenEntryPower[tokenId]);
        dxnExtraEntryPower[tokenId] += extraPower;
        tokenEntryPowerWithStake[currentCycle] += tokenEntryPower[tokenId];
        totalExtraEntryPower[currentCycle] += extraPower;

        dxn.safeTransferFrom(msg.sender, address(this), amount);
    }

    function unstake(uint256 tokenId, uint256 amount) external nonReentrant onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        require(
            tokenWithdrawableStake[tokenId] > 0,
            "DBXeNFT: No DXN staked."
        );

        if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += amount;
        } else {
            summedCycleStakes[currentCycle] -= amount;
        }

        uint256 powerDecrease = calcExtraPower(baseDBXeNFTPower[tokenId], amount);
        tokenWithdrawableStake[tokenId] -= amount;
        DBXeNFTPower[tokenId] -= powerDecrease;

        dxn.safeTransfer(msg.sender, tokenWithdrawableStake[msg.sender]);
    }

    function claimFees(uint256 tokenId) external nonReentrant() onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender){
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        uint256 fees = tokenAccruedFees[tokenId];
        require(fees > 0, "dbXENFT: amount is zero");
        tokenAccruedFees[msg.sender] = 0;
        sendViaCall(payable(msg.sender), fees);
    }

    function calcMaturityDays(uint256 term, uint256 maturityTs) internal returns(uint256 maturityDays) {
        uint256 daysTillClaim;
        uint256 daysSinceMinted;

        if(block.timestamp < maturityTs) {
            daysTillClaim = ((maturityTs - block.timestamp) / SECONDS_IN_DAY);
            daysSinceMinted = term - daysTillClaim;
        } else {
            daysTillClaim = 0;
            daysSinceMinted =
                ((term * SECONDS_IN_DAY + (block.timestamp - maturityTs))) /
                SECONDS_IN_DAY;
        }

        if (daysSinceMinted > daysTillClaim) {
            maturityDays = daysSinceMinted - daysTillClaim;
        }
    }

    function claimXen(uint256 tokenId) external onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);

        uint256 xenftId = tokenUnderlyingXENFT[tokenId];
        uint256 mintInfo = xenft.mintInfo(xenftId);

        require(!mintInfo.getRedeemed(), "XENFT: Already redeemed");

        uint256 DBXenftPow = DBXeNFTPower[tokenId];
        if(DBXenftPow > 1e18) {
            uint256 newPow = Math.mulDiv(DBXeNFTPower[tokenId], 1e18, baseDBXeNFTPower[tokenId]);
            DBXeNFTPower[tokenId] = newPow;
            DBXenftPow -= newPow;
            baseDBXeNFTPower[tokenId] = 1e18;

            if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += DBXenftPow;
            } else {
                summedCycleStakes[currentCycle] -= DBXenftPow;
            }
        }

        xenft.bulkClaimMintReward(xenftId, msg.sender);
    }

    function _calculateFee(
        uint256 userReward,
        uint256 maturityTs,
        uint256 term
    ) private returns (uint256 burnFee) {
        uint256 maturityDays = calcMaturityDays(term, maturityTs);
        uint256 maxDays = Math.max(maturityDays, 0);
        uint256 maxPctReduction = Math.min(11389 * maxDays, 5_000_000);
        uint256 xenMulReduction = Math.mulDiv(estXenReward, maxPctReduction, MAX_BPS);
        burnFee = Math.max(1e15, xenMulReduction / BASE_XEN);
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
                    (cycleAccruedFees[lastStartedCycle] * SCALING_FACTOR) /
                    summedCycleStakes[lastStartedCycle];

            cycleFeesPerStakeSummed[lastStartedCycle + 1] =
                cycleFeesPerStakeSummed[previousStartedCycle] +
                feePerStake;
        }
    }

    function setUpNewCycle() internal {
        uint256 currentCycleMemory = currentCycle;
        uint256 lastStartedCycleMemory = lastStartedCycle;
        if (rewardPerCycle[currentCycleMemory] == 0) {
            lastCycleReward = currentCycleReward;
            uint256 calculatedCycleReward = lastCycleReward +
                (lastCycleReward / 100);

            currentCycleReward = calculatedCycleReward;
            rewardPerCycle[currentCycleMemory] = calculatedCycleReward;

            if(pendingExtraPower != 0) {
                summedCycleStakes[currentStartedCycle] += pendingExtraPower;
                pendingExtraPower = 0;
            }

            if(tokenEntryPowerWithStake[lastStartedCycleMemory] != 0) {
                uint256 powerForEntryWithStake = tokenEntryPowerWithStake[lastStartedCycleMemory]
                    * lastCycleReward / totalPowerPerCycle[lastStartedCycleMemory];
                pendingExtraPower = dxnExtraEntryPower[lastStartedCycleMemory] * powerForEntryWithStake
                    / tokenEntryPowerWithStake[lastStartedCycleMemory];
            } 

            currentStartedCycle = currentCycleMemory;
            precedentStartedCycle[currentCycleMemory] = lastStartedCycleMemory;

            summedCycleStakes[currentStartedCycle] += summedCycleStakes[lastStartedCycleMemory];

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

    function updateDBXeNFT(uint256 tokenId) internal {
        if(baseDBXeNFTPower[tokenId] == 0) {
            uint256 entryCycle = tokenEntryCycle[tokenId];
            baseDBXeNFTPower[tokenId] = tokenEntryPower[tokenId] * 
                rewardPerCycle[entryCycle] / totalPowerPerCycle[entryCycle];
            DBXeNFTPower[tokenId] += baseDBXeNFTPower;
        }

        uint256 stakedDXN = pendingDXN[tokenId];

        if (
            currentCycle > lastStartedCycle &&
            lastFeeUpdateCycle[tokenId] != lastStartedCycle + 1
        ) {
            uint256 stakeCycle = tokenFirstStake[tokenId] - 1;
            if(stakedDXN != 0 && (lastStartedCycle != stakeCycle
            && currentStartedCycle != lastStartedCycle)) {
                uint256 extraPower = calcExtraPower(baseDBXeNFTPower, stakedDXN);
                tokenAccruedFees[tokenId] += (DBXeNFTPower[tokenId] 
                    * cycleFeesPerStakeSummed[stakeCycle + 1] - 
                    cycleFeesPerStakeSummed[precedentStartedCycle[stakeCycle] + 1]) / SCALING_FACTOR;
                uint256 totalPower = DBXeNFTPower[tokenId] + extraPower;
                uint256 stakeCycleFeesToSubract = (totalPower 
                    * cycleAccruedFees[stakeCycle + 1]) / SCALING_FACTOR;
                tokenAccruedFees[tokenId] += (totalPower 
                    * (cycleFeesPerStakeSummed[lastStartedCycle + 1] - cycleFeesPerStakeSummed[stakeCycle + 1])) / SCALING_FACTOR;
                tokenAccruedFees -= stakeCycleFeesToSubract;
                DBXeNFTPower[tokenId] += stakedDXN;
                pendingDXN = 0;
            } else {
                tokenAccruedFees[tokenId] += (DBXeNFTPower[tokenId] 
                    * (cycleFeesPerStakeSummed[lastStartedCycle + 1] - cycleFeesPerStakeSummed[lastFeeUpdateCycle])) / SCALING_FACTOR;
            }
            lastFeeUpdateCycle[tokenId] = lastStartedCycle + 1;
        }

        if (
            tokenFirstStake[tokenId] != 0 &&
            currentCycle > tokenFirstStake[tokenId]
        ) {
            uint256 unlockedFirstStake = tokenStakeCycle[tokenId][tokenFirstStake[tokenId]];

            tokenWithdrawableStake[tokenId] += unlockedFirstStake;

            tokenStakeCycle[tokenId][tokenFirstStake[tokenId]] = 0;
            tokenFirstStake[tokenId] = 0;

            if (tokenSecondStake[tokenId] != 0) {
                if (currentCycle > tokenSecondStake[tokenId]) {
                    uint256 unlockedSecondStake = tokenStakeCycle[tokenId][tokenSecondStake[tokenId]];

                    tokenWithdrawableStake[tokenId] += unlockedSecondStake;

                    tokenStakeCycle[tokenId][tokenSecondStake[tokenId]] = 0;
                    tokenSecondStake[tokenId] = 0;
                } else {
                    tokenFirstStake[tokenId] = tokenSecondStake[tokenId];
                    tokenSecondStake[tokenId] = 0;
                }
            }
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
