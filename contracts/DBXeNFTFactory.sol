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

contract DBXeNFTFactory is ReentrancyGuard {
    using MintInfo for uint256;
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

    uint256 public pendingExtraPower;

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;

    mapping(uint256 => uint256) public totalPowerPerCycle;

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

    mapping(uint256 => uint256) public tokenAccruedFees;

    mapping(uint256 => uint256) public precedentStartedCycle;

    mapping(uint256 => uint256) public lastFeeUpdateCycle;

    mapping(uint256 => uint256) public tokenWithdrawableStake;

    mapping(uint256 => uint256) public tokenUnderlyingXENFT;

    uint256 public pendingStakeWithdrawal;

    uint256 public pendingFees;

    uint256 public pendingPower;

    event NewCycleStarted(
        uint256 indexed cycle,
        uint256 calculatedCycleReward,
        uint256 summedCycleStakes
    );

    event DBXeNFTMinted(
        uint256 cycle,
        uint256 DBXeNFTId,
        uint256 XENFTID,
        uint256 fee,
        address minter
    );

    event FeesClaimed(
        uint256 indexed cycle,
        uint256 indexed tokenId,
        uint256 fees
    );

    modifier onlyNFTOwner(
        ERC721 tokenAddress,
        uint256 tokenId,
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
        address _xenCrypto
    ) {
        dxn = DBXenERC20(dbxAddress);
        xenft = XENTorrent(xenftAddress);
        xenCrypto = _xenCrypto;
        i_periodDuration = 1 days;
        i_initialTimestamp = block.timestamp;
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

        uint256 mintInfo = xenft.mintInfo(tokenId);

        (uint256 term, uint256 maturityTs, , , , , , , bool redeemed) = mintInfo
            .decodeMintInfo();

        uint256 fee;
        uint256 estimatedReward;
        if(redeemed) {
            fee = 1e15;
        } else {
            estimatedReward = _calculateUserMintReward(tokenId, mintInfo);

            fee = _calculateFee(
                estimatedReward,
                maturityTs,
                term
            );
        }
        require(msg.value >= fee, "Payment less than fee");

        uint256 dbxenftId = DBXENFTInstance.mintDBXENFT(msg.sender);
        uint256 currentCycleMem = currentCycle;

        if(redeemed) {
            baseDBXeNFTPower[dbxenftId] = 1e18;
            DBXeNFTPower[tokenId] = 1e18;

            if(currentCycleMem != 0) {
                lastFeeUpdateCycle[dbxenftId] = lastStartedCycle + 1;
            }

            if(currentCycleMem == currentStartedCycle) {
                summedCycleStakes[currentCycleMem] += 1e18;
            } else {
                pendingPower += 1e18;
            }
        } else {
            setUpNewCycle();
            tokenEntryPower[dbxenftId] = estimatedReward;
            tokenEntryCycle[dbxenftId] = currentCycleMem;
            totalPowerPerCycle[currentCycleMem] += estimatedReward;

            if(currentCycleMem != 0) {
                lastFeeUpdateCycle[dbxenftId] = lastStartedCycle + 1;
            }
        }
    
        cycleAccruedFees[currentCycleMem] = cycleAccruedFees[currentCycleMem] + fee;
        tokenUnderlyingXENFT[dbxenftId] = tokenId;

        xenft.transferFrom(msg.sender, address(this), tokenId);
        sendViaCall(payable(msg.sender), msg.value - fee);

        emit DBXeNFTMinted(
            currentCycleMem,
            dbxenftId,
            tokenId,
            fee,
            msg.sender
        );
    }

    function calcStakeFee(uint256 dxnAmount) internal pure returns(uint256 stakeFee){
        stakeFee = dxnAmount / 1000;
    }

    function calcExtraPower(uint256 power, uint256 dxnAmount) internal pure returns(uint256 calcPower){
        calcPower = Math.mulDiv(power, dxnAmount, 1e20);
    }

    function stake(uint256 amount, uint256 tokenId) external payable nonReentrant onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        require(amount > 0, "DBXen: amount is zero");

        uint256 tokenEntryPowerMem = tokenEntryPower[tokenId];
        require(tokenEntryPowerMem != 0, "DBXeNFT does not exist");
        uint256 stakeFee = calcStakeFee(amount);
        require(msg.value >= stakeFee, "Value less than staking fee");
        uint256 currentCycleMem = currentCycle;
        uint256 currentStartedCycleMem = currentStartedCycle;
        if(currentCycleMem == currentStartedCycle) {
            cycleAccruedFees[currentCycleMem] += stakeFee;
        } else {
            pendingFees += stakeFee;
        }

        uint256 cycleToSet = currentCycleMem + 1;
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

        if(baseDBXeNFTPower[tokenId] == 0){
            uint256 extraPower = calcExtraPower(amount, tokenEntryPowerMem);
            dxnExtraEntryPower[tokenId] += extraPower;
            tokenEntryPowerWithStake[currentStartedCycleMem] += tokenEntryPowerMem;
            totalExtraEntryPower[currentStartedCycleMem] += extraPower;
        } else {
            uint256 extraPower = calcExtraPower(baseDBXeNFTPower[tokenId], amount);
            pendingPower += extraPower;
        }

        dxn.safeTransferFrom(msg.sender, address(this), amount);
        sendViaCall(payable(msg.sender), msg.value - stakeFee);
    }

    function unstake(uint256 tokenId, uint256 amount) external nonReentrant onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        require(
            tokenWithdrawableStake[tokenId] > 0,
            "DBXeNFT: No withdrawable DXN available."
        );

        uint256 powerDecrease = calcExtraPower(baseDBXeNFTPower[tokenId], amount);
        tokenWithdrawableStake[tokenId] -= amount;
        DBXeNFTPower[tokenId] -= powerDecrease;

        if (lastStartedCycle == currentStartedCycle) {
            pendingStakeWithdrawal += powerDecrease;
        } else {
            summedCycleStakes[currentCycle] -= powerDecrease;
        }

        dxn.safeTransfer(msg.sender, amount);
    }

    function claimFees(uint256 tokenId) external nonReentrant() onlyNFTOwner(DBXENFTInstance, tokenId, msg.sender){
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        uint256 fees = tokenAccruedFees[tokenId];
        require(fees > 0, "dbXENFT: amount is zero");
        tokenAccruedFees[tokenId] = 0;
        sendViaCall(payable(msg.sender), fees);
        emit FeesClaimed(currentCycle, tokenId, fees);
    }

    function calcMaturityDays(uint256 term, uint256 maturityTs) internal view returns(uint256 maturityDays) {
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

        require(currentCycle != tokenEntryCycle[tokenId], "Can not claim during entry cycle");

        uint256 DBXenftPow = DBXeNFTPower[tokenId];
        uint256 baseDBXeNFTPow = baseDBXeNFTPower[tokenId];
        if(baseDBXeNFTPow > 1e18 && DBXenftPow != baseDBXeNFTPow) {
            uint256 newPow = Math.mulDiv(DBXenftPow, 1e18, baseDBXeNFTPow);
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
    ) private view returns (uint256 burnFee) {
        uint256 maturityDays = calcMaturityDays(term, maturityTs);
        uint256 maxDays = Math.max(maturityDays, 0);
        uint256 daysReduction = 11389 * maxDays;
        uint256 difference = MAX_BPS - daysReduction;
        uint256 maxPctReduction = Math.max(difference, 5_000_000);
        uint256 xenMulReduction = Math.mulDiv(userReward, maxPctReduction, MAX_BPS);
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

            if(pendingFees != 0) {
                cycleAccruedFees[currentCycleMemory] += pendingFees;
                pendingFees = 0;
            }

            if(tokenEntryPowerWithStake[lastStartedCycleMemory] != 0) {
                uint256 powerForEntryWithStake = Math.mulDiv(tokenEntryPowerWithStake[lastStartedCycleMemory],
                    lastCycleReward, totalPowerPerCycle[lastStartedCycleMemory]); 
                uint256 extraPower = Math.mulDiv(totalExtraEntryPower[lastStartedCycleMemory],
                    powerForEntryWithStake, tokenEntryPowerWithStake[lastStartedCycleMemory]);
                summedCycleStakes[currentCycleMemory] += extraPower;
                
            }

            if(pendingPower != 0) {
                summedCycleStakes[currentCycleMemory] += pendingPower;
                pendingPower = 0;
            }

            currentStartedCycle = currentCycleMemory;
            precedentStartedCycle[currentCycleMemory] = lastStartedCycleMemory;

            summedCycleStakes[currentCycleMemory] += summedCycleStakes[lastStartedCycleMemory] + calculatedCycleReward;

            if (pendingStakeWithdrawal != 0) {
                summedCycleStakes[
                    currentCycleMemory
                ] -= pendingStakeWithdrawal;
                pendingStakeWithdrawal = 0;
            }

            emit NewCycleStarted(
                currentCycle,
                calculatedCycleReward,
                summedCycleStakes[currentCycleMemory]
            );
        }
    }

    function updateDBXeNFT(uint256 tokenId) internal {
        uint256 entryCycle = tokenEntryCycle[tokenId];
        if(baseDBXeNFTPower[tokenId] == 0 && currentCycle > entryCycle) {
            baseDBXeNFTPower[tokenId] = Math.mulDiv(tokenEntryPower[tokenId],
                rewardPerCycle[entryCycle], totalPowerPerCycle[entryCycle]);
            DBXeNFTPower[tokenId] += baseDBXeNFTPower[tokenId];
        }

        uint256 lastStartedCycleMem = lastStartedCycle;
        if (
            currentCycle > lastStartedCycleMem &&
            lastFeeUpdateCycle[tokenId] != lastStartedCycleMem + 1
        ) {
            
            tokenAccruedFees[tokenId] += (DBXeNFTPower[tokenId] 
                    * (cycleFeesPerStakeSummed[lastStartedCycleMem + 1] - cycleFeesPerStakeSummed[lastFeeUpdateCycle[tokenId]])) / SCALING_FACTOR;

            uint256 stakedDXN = pendingDXN[tokenId];
            if(stakedDXN != 0) {
                uint256 stakeCycle = tokenFirstStake[tokenId] - 1;
                uint256 extraPower = calcExtraPower(baseDBXeNFTPower[tokenId], stakedDXN);
            
                console.log(tokenId, lastStartedCycleMem, stakeCycle, currentStartedCycle);
                if(lastStartedCycleMem != stakeCycle
                    && currentStartedCycle != lastStartedCycleMem) {
                        tokenAccruedFees[tokenId] += (extraPower 
                        * (cycleFeesPerStakeSummed[lastStartedCycleMem + 1] - 
                        cycleFeesPerStakeSummed[stakeCycle + 1])) / SCALING_FACTOR;
                        console.log("here");
                }
                pendingDXN[tokenId] = 0;
                DBXeNFTPower[tokenId] += extraPower;
            }
            
            lastFeeUpdateCycle[tokenId] = lastStartedCycleMem + 1;
        }

        uint256 tokenFirstStakeMem = tokenFirstStake[tokenId];
        if (
            tokenFirstStakeMem != 0 &&
            currentCycle > tokenFirstStakeMem
        ) {
            uint256 unlockedFirstStake = tokenStakeCycle[tokenId][tokenFirstStakeMem];

            tokenWithdrawableStake[tokenId] += unlockedFirstStake;

            tokenStakeCycle[tokenId][tokenFirstStakeMem] = 0;
            tokenFirstStake[tokenId] = 0;

            uint256 tokenSecondStakeMem = tokenSecondStake[tokenId];
            if (tokenSecondStake[tokenId] != 0) {
                if (currentCycle > tokenSecondStakeMem) {
                    uint256 unlockedSecondStake = tokenStakeCycle[tokenId][tokenSecondStakeMem];

                    tokenWithdrawableStake[tokenId] += unlockedSecondStake;

                    tokenStakeCycle[tokenId][tokenSecondStakeMem] = 0;
                    tokenSecondStake[tokenId] = 0;
                } else {
                    tokenFirstStake[tokenId] = tokenSecondStakeMem;
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
