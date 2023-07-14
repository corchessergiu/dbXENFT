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

contract DBXeNFTFactory is ReentrancyGuard {
    using MintInfo for uint256;
    using SafeERC20 for ERC20;

    /**
     * XENFT Token contract.
     */
    XENTorrent public xenft;

    /**
     * DBXen Reward Token contract.
     */
    ERC20 public immutable dxn;

    /**
     * Xen Token contract.
     */
    address public immutable xenCrypto;

    /**
     * DBXeNFT Reward Token contract.
     */
    DBXENFT public immutable dbxenft;

    /**
     * Index (0-based) of the current cycle.
     * 
     * Updated upon cycle setup that is triggered by contract interraction 
     * (account burn tokens, claims fees, claims rewards, stakes or unstakes).
     */
    uint256 public currentCycle;

    /**
     * Stores the index of the penultimate active cycle plus one.
     */
    uint256 public previousStartedCycle;

    /**
     * Stores the amount of stake that will be subracted from the total
     * stake once a new cycle starts.
     */
    uint256 public currentStartedCycle;

    /**
     * Stores the index of the penultimate active cycle plus one.
     */
    uint256 public lastStartedCycle;

    /**
     * Reward token amount allocated for the current cycle.
     */
    uint256 public currentCycleReward;

    /**
     * Reward token amount allocated for the previous cycle.
     */
    uint256 public lastCycleReward;

    /**
     * 
     */
    uint256 public constant SECONDS_IN_DAY = 3_600 * 24;

    /**
     * Upper percentage limit that can be applied as penalty.
     */
    uint256 public constant MAX_PENALTY_PCT = 99;

    /**
     * Basis points representation of 100 percent.
     */
    uint256 public constant MAX_BPS = 10_000_000;

    /**
     * Helper constant used in calculating the fee for locking XENFT.
     */
    uint256 public constant BASE_XEN = 1_000_000_000;

    /**
     * Used to minimise division remainder when earned fees are calculated.
     */
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

    /**
     * The total amount of accrued fees per cycle.
     */
    mapping(uint256 => uint256) public cycleAccruedFees;

    /**
     * Total entry power(in est. Xen reward) in the given cycle.
     */
    mapping(uint256 => uint256) public totalPowerPerCycle;

    /**
     * Updated when staking DXN - used in the calculation of
     * all the extra power that needs to be added to the total
     * power of DBXENFTs.
     */
    mapping(uint256 => uint256) public totalExtraEntryPower;

    /**
     * Entry power(in est. Xen reward) of the given DBXENFT.
     */
    mapping(uint256 => uint256) public tokenEntryPower;

    /**
     * Cycle in which the given DBXENFT was minted.
     */
    mapping(uint256 => uint256) public tokenEntryCycle;

    /**
     * Total entry power(in est. Xen reward) of all DBXENFTs
     * that staked during entry cycle.
     */
    mapping(uint256 => uint256) public tokenEntryPowerWithStake;

    /**
     * Power of DBXENFT counting towards the share of protocolf fees.
     * Equal to base DBXENFT power + (base DBXENFT power * DXN staked) / 100;
     */ 
    mapping(uint256 => uint256) public DBXeNFTPower;

    /**
     * Base power of DBXENFT obtained from the share of
     * reward power of its entry cycle.
     */
    mapping(uint256 => uint256) public baseDBXeNFTPower;

    /**
     * Stores the sum of the total DBXENFT powers from all
     * the previous cycles + the current power reward of the given cycle.
     */
    mapping(uint256 => uint256) public summedCycleStakes;

     /**
     * Sum of previous total cycle accrued fees divided by total DBXENFT powers.
     */
    mapping(uint256 => uint256) public cycleFeesPerStakeSummed;

    /**
     * Total power rewards allocated per cycle.
     */
    mapping(uint256 => uint256) public rewardPerCycle;

    /**
     * Cycle in which a DBXENFT's staked DXN is locked and begins generating fees.
     */
    mapping(uint256 => uint256) public tokenFirstStake;

    /**
     * Same as tokenFirstStake, but stores the second stake seperately 
     * in case DXN is staked for the DBXENFT in two consecutive active cycles.
     */
    mapping(uint256 => uint256) public tokenSecondStake;

    /**
     * DXN amount a DBXENFT has staked and is locked during given cycle.
     */
    mapping(uint256 => mapping(uint256 => uint256)) tokenStakeCycle;

    /**
     * Pending staked DXN helper variable used for
     * updating DBXENFT with the corresponding power.
     */
    mapping(uint256 => uint256) pendingDXN;

    /**
     * DXN amount a DBXENFT has staked and is locked during given cycle.
     */
    mapping(uint256 => uint256) public tokenAccruedFees;

    /**
     * The fee amount that can be withdrawn for the DBXENFT.
     */
    mapping(uint256 => uint256) public precedentStartedCycle;

    /**
     * DXN amount a DBXENFT has staked and is locked during given cycle.
     */
    mapping(uint256 => uint256) public lastFeeUpdateCycle;

    /**
     * DXN amount a DBXENFT can currently withdraw.
     */
    mapping(uint256 => uint256) public tokenWithdrawableStake;

    /**
     * DBXENFT's locked XENFT.
     */
    mapping(uint256 => uint256) public tokenUnderlyingXENFT;

    /**
     * Pending power decrease applied at the start of the next active cycle.
     */
    uint256 public pendingStakeWithdrawal;

    /**
     * Pending fees added into the pool of the next active cycle.
     */
    uint256 public pendingFees;

    /**
     * Pending fees added into the pool of the next active cycle.
     */
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

    /**
     * @dev Used to check if the user owns a certain DBXENFT/XENFT.
     */
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
     * @param dbxAddress DXN contract address.
     * @param _xenCrypto Xen contract address.
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
        dbxenft = new DBXENFT();
        currentCycleReward = 10000 * 1e18;
        summedCycleStakes[0] = 10000 * 1e18;
        rewardPerCycle[0] = 10000 * 1e18;
    }

    /**
     * @dev Locks an owned XENFT inside this contract and mints a DBXENFT.
     * Must pay a protocol fee based on the estimated Xen rewards
     * the XENFT yields at the time of locking. The estimated Xen
     * also determines the entry power that will provide the DBXENFT.
     * a base power from the reward power pool split to all the
     * DBXENFTs created during the cycle.
     * If the XENFT is already redeemed, a DBXENFT that does not take
     * part in the auction of the cycle's reward power nor does it
     * start it is minted and is assigned the base power of 1.
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

        uint256 dbxenftId = dbxenft.mintDBXENFT(msg.sender);
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

    /**
     * @dev Calculates the protocol fee when staking 'dxnAmount' of DXN.
     */
    function calcStakeFee(uint256 dxnAmount) internal pure returns(uint256 stakeFee){
        stakeFee = dxnAmount / 1000;
    }

    /**
     * @dev Used for calculating extra entry power in order to find out
     * the extra total DBXENFT power of all the DBXENFTs that staked,
     * respectively when adding the extra power to an individual DBXENFT.
     */
    function calcExtraPower(uint256 power, uint256 dxnAmount) internal pure returns(uint256 calcPower){
        calcPower = Math.mulDiv(power, dxnAmount, 1e20);
    }

    /**
     * @dev Stake an amount of DXN for the given DBXENFT to give it extra power.
     * Must pay a protocol fee of 0.001 native coin for each DXN.
     * The corresponding DXN is locked until the end of the next cycle.
     */    
    function stake(uint256 amount, uint256 tokenId) external payable nonReentrant onlyNFTOwner(dbxenft, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        require(amount > 0, "DBXen: amount is zero");

        uint256 tokenEntryPowerMem = tokenEntryPower[tokenId];
        require(tokenEntryPowerMem != 0, "DBXeNFT does not exist");

        uint256 stakeFee = calcStakeFee(amount);
        require(msg.value >= stakeFee, "Value less than staking fee");

        uint256 currentCycleMem = currentCycle;
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

        uint256 currentStartedCycleMem = currentStartedCycle;
        if(baseDBXeNFTPower[tokenId] == 0){
            uint256 extraPower = calcExtraPower(amount, tokenEntryPowerMem);
            tokenEntryPowerWithStake[currentStartedCycleMem] += tokenEntryPowerMem;
            totalExtraEntryPower[currentStartedCycleMem] += extraPower;
        } else {
            uint256 extraPower = calcExtraPower(baseDBXeNFTPower[tokenId], amount);
            pendingPower += extraPower;
        }

        dxn.safeTransferFrom(msg.sender, address(this), amount);
        sendViaCall(payable(msg.sender), msg.value - stakeFee);
    }

    /**
     * @dev Unstake an amount of DXN for the given DBXENFT applying a power decrease
     * to the current cycle if it's an active one or beginning with the next active one.
     * Can only withdraw DXN that has completed the corresponding cycle lock-up.
     */ 
    function unstake(uint256 tokenId, uint256 amount) external nonReentrant onlyNFTOwner(dbxenft, tokenId, msg.sender) {
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

    /**
     * @dev Transfers accrued fees of DBXENFT to its owner.
     */
    function claimFees(uint256 tokenId) external nonReentrant() onlyNFTOwner(dbxenft, tokenId, msg.sender){
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);
        uint256 fees = tokenAccruedFees[tokenId];
        require(fees > 0, "dbXENFT: amount is zero");
        tokenAccruedFees[tokenId] = 0;
        sendViaCall(payable(msg.sender), fees);
        emit FeesClaimed(currentCycle, tokenId, fees);
    }

    /**
     * @dev MaturityDays = Days since XENFT was minted - Days until XENFT can be claimed.
     */ 
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
    
    /**
     * @dev Given a DBXENFT, claim the Xen rewards of the underlying XENFT
     * and direct them to its owner. Not permitted during entry cycle of DBXENFT.
     * In doing so, the base power of the DBXENFT will become 1(unless it's already smaller)
     * and the DBXENFT total power is updated acording to the new base power
     * and the existent DXN stake.
     */ 
    function claimXen(uint256 tokenId) external onlyNFTOwner(dbxenft, tokenId, msg.sender) {
        calculateCycle();
        updateCycleFeesPerStakeSummed();
        updateDBXeNFT(tokenId);

        uint256 xenftId = tokenUnderlyingXENFT[tokenId];
        uint256 mintInfo = xenft.mintInfo(xenftId);

        require(!mintInfo.getRedeemed(), "XENFT: Already redeemed");

        require(currentCycle != tokenEntryCycle[tokenId], "Can not claim during entry cycle");

        uint256 DBXenftPow = DBXeNFTPower[tokenId];
        uint256 baseDBXeNFTPow = baseDBXeNFTPower[tokenId];
        if(baseDBXeNFTPow > 1e18) {
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

    /**
     * Calculated according to the following formula:
     * ProtocolFee = MAX( (Xen*MAX( 1-0.0011389 * MAX(MaturityDays,0) , 0.5) )/ BASE_XEN), MinCost).
     * Xen = Estimated Xen to be claimed.
     * BaseXen = The floor amount of Xen for 1 Native coin = 1_000_000_000.
     * MinCost = Minimum amount of Native coin to be paid for minting = 0.001 native coin.
     */
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

    /**
     * @dev calculates withdrawal penalty of Xen rewards depending on lateness.
     */
    function _penalty(uint256 secsLate) private pure returns (uint256) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint256 daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > 7 - 1) return MAX_PENALTY_PCT;
        uint256 penalty = (uint256(1) << (daysLate + 3)) / 7 - 1;
        return penalty < MAX_PENALTY_PCT ? penalty : MAX_PENALTY_PCT;
    }

    /**
     * @dev calculates net Xen Reward (adjusted for Penalty).
     */
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

    /**
     * @dev calculates the estimated total Xen reward of the XENFT.
     */
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
     * @dev Updates the global helper variables related to fee distribution.
     */
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

    /**
     * @dev Set up the new active cycle calculating the new
     * reward power pool with an 1% increase. 
     * Introduce any pending fees in the cycle's fee pool.
     * Calculate the new total power of DBXENFTs based on
     * the ones that have staked DXN.
     * Apply pending power decrease to the total DBXENFT power.
     */
    function setUpNewCycle() internal {
        uint256 currentCycleMemory = currentCycle;
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

            uint256 lastStartedCycleMemory = lastStartedCycle;
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

    /**
     * Update DBXENFT stats:
     * Assign their respective base power if not yet set.
     * Calculate the new DBXENFT power if any new stake was made.
     * Calculate the new fees it has accumulated since last update.
     * Mark any stake that passed the lock-up cycle as withdrawable.
     */
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
            
                if(lastStartedCycleMem != stakeCycle
                    && currentStartedCycle != lastStartedCycleMem) {
                        tokenAccruedFees[tokenId] += (extraPower 
                        * (cycleFeesPerStakeSummed[lastStartedCycleMem + 1] - 
                        cycleFeesPerStakeSummed[stakeCycle + 1])) / SCALING_FACTOR;
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

    /**
     * @dev Updates the index of the cycle.
     */
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
