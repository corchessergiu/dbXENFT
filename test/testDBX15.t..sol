// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import {DBXeNFTFactory, DBXENFT} from "../contracts/DBXeNFTFactory.sol";
import "../contracts/DBXenERC20.sol";
import "../contracts/DBXenERC20.sol";
import "../contracts/XENCrypto.sol";
import {XENTorrent} from "../contracts/XENFT.sol";
contract CycleAccruedFeesTest is Test {
 DBXeNFTFactory public factory;
 XENTorrent public xenft;
 DBXENFT public dBXENFT;
 DBXenERC20 public dxn;
 XENCrypto public xenCrypto;
 address public forwarder;
 address public royaltyReceiver;
 uint256[] burnRates = [10, 20];
 uint256[] tokenLimits = [10, 20];
 address public Bob;
 address public Tom;
 uint256 public xenftId1;
 uint256 public xenftId2;
 uint256 public dBxenftId1;
 uint256 public dBxenftId2;
 uint256 private counter;
 function setUp() public {
 dxn = new DBXenERC20();
 xenCrypto = new XENCrypto();
 dBXENFT = new DBXENFT();
 forwarder = makeAddr("forwarder");
 royaltyReceiver = makeAddr("royaltyReceiver");
 xenft = new XENTorrent(
 address(xenCrypto), burnRates, tokenLimits, block.number, forwarder,
royaltyReceiver
 );
 factory = new DBXeNFTFactory(address(dxn), address(xenft),
address(xenCrypto));
 vm.roll(block.number + 100);
 }
 function testIncorrectCycleAccruedFees() public {
 console.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 vm.warp(block.timestamp + 1 days);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 mintDBXENFTForUserWithRedeemedXNFT(1, false);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
console.log(factory.getCurrentCycle());

 vm.warp(block.timestamp + 1 days);
 console.log(factory.getCurrentCycle());

 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 mintDBXENFTForUserWithRedeemedXNFT(2, true);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));

console.log(factory.getCurrentCycle());
 vm.warp(block.timestamp + 1 days);
 console.log(factory.getCurrentCycle());

 console2.log("cycleAccruedFees in cycle# %d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
console.log(factory.getCurrentCycle());
 mintDBXENFTForUserWithRedeemedXNFT(3, true);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));

 vm.warp(block.timestamp + 1 days);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 mintDBXENFTForUserWithRedeemedXNFT(4, true);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));

 vm.warp(block.timestamp + 1 days);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 mintDBXENFTForUserWithRedeemedXNFT(5, false);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 
 vm.warp(block.timestamp + 1 days);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 mintDBXENFTForUserWithRedeemedXNFT(6, false);
 console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));
 console.log(factory.pendingFees());

 vm.warp(block.timestamp + 1 days);

console2.log("cycleAccruedFees in cycle#%d is %d",
factory.getCurrentCycle(), factory.cycleAccruedFees(factory.getCurrentCycle()));

 }


function  testGetCurrentCycle() public{
    console.log("sssssssssssssssssssssssss");
    console.log(factory.getCurrentCycle());
     vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());
         vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());

     vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());

     vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());

     vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());

     vm.warp(block.timestamp + 1 days);
    console.log(factory.getCurrentCycle());



}

 function mintDBXENFTForUserWithRedeemedXNFT(uint user, bool isRedeemed) public {
 address userAddress = vm.addr(user);
 deal(userAddress, 100 ether);
 deal(address(dxn), userAddress, 1e6 * 1e18);
 deal(address(xenCrypto), userAddress, 1000 * 1e18);

 // Get XENFT
 vm.startPrank(userAddress);
 xenftId1 = xenft.bulkClaimRank(5, 10);
 xenft.setApprovalForAll(address(factory), true);
 console2.log("xenftId1 = %d", xenftId1);
 vm.stopPrank();
 // Redeem XENFT
 if (isRedeemed) {
 vm.warp(block.timestamp + 11 days);
 vm.startPrank(userAddress);
 xenft.bulkClaimMintReward(xenftId1, userAddress);
 vm.stopPrank();
 }
 // Mint DBXENFT
 // log the ether balance of the user
 console2.log("userAddress balance = %d", userAddress.balance);
 vm.startPrank(userAddress);
 factory.mintDBXENFT{value: 1 ether}(xenftId1);
 dBxenftId1 = counter;
 counter++;
 vm.stopPrank();
 console2.log("userAddress balance = %d", userAddress.balance);
 console2.log("dBxenftId1 = %d", dBxenftId1);
 }
}