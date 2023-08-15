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
contract DBXeNFTFactory3Test is Test {
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
 Bob = makeAddr("Bob");
 vm.label(Bob, "Bob");
 Tom = makeAddr("Tom");
 vm.label(Tom, "Tom");
 deal(Bob, 100 ether);
 deal(Tom, 100 ether);
 deal(address(dxn), Bob, 1e6 * 1e18);
 deal(address(dxn), Tom, 1e6 * 1e18);
 deal(address(xenCrypto), Bob, 1000 * 1e18);
 deal(address(xenCrypto), Tom, 1000 * 1e18);
 vm.prank(Bob);
 dxn.approve(address(factory), type(uint256).max);
 vm.prank(Tom);
 dxn.approve(address(factory), type(uint256).max);
 vm.roll(block.number + 100);
 }
 function test_mintDBXENFT() public {
 //showInfo(dBxenftId1, false);
 vm.startPrank(Bob);
 xenftId1 = xenft.bulkClaimRank(5, 10);
 xenft.setApprovalForAll(address(factory), true);
 console2.log("xenftId1 = %d", xenftId1);
 vm.stopPrank();
 vm.startPrank(Bob);
 assertEq(factory.lastStartedCycle(), 0);
 factory.mintDBXENFT{value: 1 ether}(xenftId1);
 dBxenftId1 = counter;
 counter++;
 vm.stopPrank();
 console2.log("dBxenftId1 = %d", dBxenftId1);
 showInfo(dBxenftId1, true);
 }
 function test_mintDBXENFT_stake_unstake_revert() public {
 test_mintDBXENFT();
 vm.startPrank(Bob);
 vm.warp(block.timestamp + 1 days);
 console2.log("Bob stakes 10000 XEN on dBxenftId1");
 factory.stake{value: 10 ether}(10000 ether, dBxenftId1);
 vm.warp(block.timestamp + 2 days);
 vm.stopPrank();
 console2.log("Bob unstakes 1000 XEN on dBxenftId1");
 vm.warp(block.timestamp + 6 days);
 vm.startPrank(Bob);
 vm.expectRevert();
 factory.unstake(dBxenftId1, 1000 ether);
 vm.stopPrank();
 }
 function showCycleInfo() internal view {
 console2.log("---------------Cycle Info--------------");
 console2.log("currentCycle = %d", factory.currentCycle());
 console2.log("previousStartedCycle = %d", factory.previousStartedCycle());
 console2.log("currentStartedCycle = %d", factory.currentStartedCycle());
 console2.log("lastStartedCycle = %d", factory.lastStartedCycle());
 console2.log("currentCycleReward = %d", factory.currentCycleReward());
 console2.log("lastCycleReward = %d", factory.lastCycleReward());
 }
 function showPendingInfo() internal view {
 console2.log("---------------Pending Info--------------");
 console2.log("pendingFees = %d", factory.pendingFees());
 console2.log("pendingPower = %d", factory.pendingPower());
 console2.log("pendingStakeWithdrawal = %d",
factory.pendingStakeWithdrawal());
 }
 function showCycleFeeAndPower() internal view {
 console2.log("~~~~~~~~~~~~~~~Fee and Power in Cycles~~~~~~~~~~~~~~~");
 uint256 curCycle = factory.currentCycle();
 for (uint i = curCycle; i <= curCycle; i++) {
 console2.log("---------------Fee and Power in Cycle#%d--------------",
i);
 console2.log("cycleAccruedFees in cycle#%d is %d", i,
factory.cycleAccruedFees(i));
 console2.log("totalExtraEntryPower in cycle#%d is %d", i,
factory.totalExtraEntryPower(i));
 console2.log("cycleFeesPerPowerSummed in cycle#%d is %d", i,
factory.cycleFeesPerPowerSummed(i));
 console2.log("rewardPerCycle in cycle#%d is %d", i,
factory.rewardPerCycle(i));
 console2.log("dbxenftEntryPowerWithStake in cycle#%d is %d", i,
factory.dbxenftEntryPowerWithStake(i));
 }
 }
 function showInfoByDBXeNFT(uint256 tokenId) internal view {
 console2.log("---------------Show Info In DBXeNFT#%d--------------",
tokenId);
 console2.log("dbxenftEntryPower of DBXeNFT#%d is %d", tokenId,
factory.dbxenftEntryPower(tokenId));
 console2.log("tokenEntryCycle is DBXeNFT#%d", tokenId,
factory.tokenEntryCycle(tokenId));
 console2.log("baseDBXeNFTPower of DBXeNFT#%d is %d", tokenId,
factory.baseDBXeNFTPower(tokenId));
 console2.log("summedCyclePowers of DBXeNFT#%d is %d", tokenId,
factory.summedCyclePowers(tokenId));
 console2.log("cycleFeesPerPowerSummed of DBXeNFT#%d is %d", tokenId,
factory.cycleFeesPerPowerSummed(tokenId));
console2.log("dbxenftFirstStake of DBXeNFT#%d is %d", tokenId,
factory.dbxenftFirstStake(tokenId));
 console2.log("dbxenftSecondStake of DBXeNFT#%d is %d", tokenId,
factory.dbxenftSecondStake(tokenId));
 console2.log("dbxenftAccruedFees of DBXeNFT#%d is %d", tokenId,
factory.dbxenftAccruedFees(tokenId));
 console2.log("lastFeeUpdateCycle of DBXeNFT#%d is %d", tokenId,
factory.lastFeeUpdateCycle(tokenId));
 console2.log("dbxenftWithdrawableStake of DBXeNFT#%d is %d DXN", tokenId,
factory.dbxenftWithdrawableStake(tokenId)/1e18);
 console2.log("dbxenftUnderlyingXENFT of DBXeNFT#%d is %d", tokenId,
factory.dbxenftUnderlyingXENFT(tokenId));
 }
 function showInfo(uint256 tokenId, bool showNFT) internal view {
 showCycleInfo();
 showCycleFeeAndPower();
 showPendingInfo();
 if (showNFT) {
 showInfoByDBXeNFT(tokenId);
 }
 }
}