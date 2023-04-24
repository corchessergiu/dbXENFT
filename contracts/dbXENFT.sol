// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./XENFT.sol";

contract dbXENFT is ReentrancyGuard, IBurnRedeemable {

    XENTorrent public xenft;

    // /**
    //  * @param xenftAddress XENFT contract address.
    //  */
    constructor(address xenftAddress) {
        xenft = XENTorrent(xenftAddress);
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
    function burnNFT(
    )
        external
        payable
        nonReentrant()
    {
        //IBurnableToken(xen).burn(msg.sender , batchNumber * XEN_BATCH_AMOUNT);
    }

    // /**
    //     @dev confirms support for IBurnRedeemable interfaces
    // */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == type(IBurnRedeemable).interfaceId;
    }

}