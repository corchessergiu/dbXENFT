// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./XENFT.sol";
import "./interfaces/IXENFT.sol";
import "./interfaces/IXENCrypto.sol";
import "./libs/MintInfo.sol";
import "./XENFT.sol";
import "hardhat/console.sol";

contract dbXENFT is ReentrancyGuard, IBurnRedeemable {
    using MintInfo for uint256;

    XENTorrent public xenft;

    address public xenCrypto;

    uint256 public genesisTime;

    uint256 public currentYear;

    uint256 public constant SECONDS_IN_DAY = 3_600 * 24;

    uint256 public immutable newImagePeriodDuration;

    uint256 public constant MAX_PENALTY_PCT = 99;

    /**
    * Basis points representation of 100 percent.
    */
    uint256 public constant MAX_BPS = 10_000_000;

    // /**
    //  * @param xenftAddress XENFT contract address.
    //  */
    constructor(address xenftAddress, address _xenCrypto) {
        xenft = XENTorrent(xenftAddress);
        xenCrypto = _xenCrypto;
        genesisTime = block.timestamp;
        newImagePeriodDuration = 365 days;
    }

    // IBurnRedeemable IMPLEMENTATION

    /**
        @dev implements IBurnRedeemable interface for burning XEN and completing update for state
     */
    function onTokenBurned(address user, uint256 amount) external{
        
    }

    // /**
    //  * @dev Burn XENFT
    //  * 
    //  */
    function burnNFT(uint256 tokenId)
        external
        payable
        nonReentrant()
    {   
        uint256 mintInfo = xenft.mintInfo(tokenId);
        (uint256 term, uint256 maturityTs, uint256 rank, uint256 amp, uint256 eea, uint256 class, bool apex, bool limited, bool redeemed) = mintInfo.decodeMintInfo();
        require(!redeemed,"dbXENFT: user already claimed tokens!");
        
        uint256 xenBurned = xenft.xenBurned(tokenId);
        uint256 userReward = _calculateUserMintReward(tokenId, mintInfo);
        uint256 fee = _calculateFee(userReward, xenBurned,maturityTs, term);
        console.log(fee);
        
        //IBurnableToken(xen).burn(msg.sender , batchNumber * XEN_BATCH_AMOUNT);
    }

    function _calculateFee(uint256 userReward, uint256 xenBurned, uint256 maturityTs, uint256 term) private returns(uint256){
        uint256 xenDifference;
        uint256 daysTillClaim;
        uint256 daysSinceMinted;
        uint256 daysDifference; 

        if(userReward  > xenBurned){
         xenDifference = userReward - xenBurned;
        } else {
            return 0.01 ether;
        }

        if(block.timestamp < maturityTs){
            daysTillClaim = (maturityTs - block.timestamp) / SECONDS_IN_DAY;
            daysSinceMinted = term - daysTillClaim;
        }

        if(daysSinceMinted > daysTillClaim){
            daysDifference = daysSinceMinted - daysTillClaim;
        }
        uint256 maxValue = daysDifference > 0 ? daysDifference : 0;
        
        if(maxValue != 0){
            uint256 procentageValue = (10000000 - (11389 * maxValue)) / MAX_BPS;
            return xenDifference * procentageValue;
        } else {
            return xenDifference;
        }
    }

    function _calculatePower(uint256 currentTime) private returns(uint256){

    }

    function _calculateCurrentYear(uint256 currentTime) public returns(uint256){
        if(currentYear < 50){
            currentYear = (currentTime - genesisTime) / newImagePeriodDuration;
            return currentYear;
        }
            else{
            return 50;
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
        uint256 secsLate = block.timestamp - maturityTs;
        uint256 penalty = _penalty(secsLate);
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

}