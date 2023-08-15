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
contract DBXeNFTFactoryTest is Test {
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
 deal(address(dxn), Bob, 1000 * 1e18);
 deal(address(dxn), Tom, 1000 * 1e18);
 deal(address(xenCrypto), Bob, 1000 * 1e18);
 deal(address(xenCrypto), Tom, 1000 * 1e18);
 vm.prank(Bob);
 dxn.approve(address(factory), type(uint256).max);
 vm.prank(Tom);
 dxn.approve(address(factory), type(uint256).max);
 vm.roll(block.number + 100);
 }
 function test_mintXeNFT() public {
 vm.startPrank(Bob);
 console2.log("Bob Claims Rank");
 xenftId1 = xenft.bulkClaimRank(5, 10);
 xenft.setApprovalForAll(address(factory), true);
 console2.log("xenftId1 = %d", xenftId1);
 vm.stopPrank();
 }
 function test_mintXeNFT_redeem_mintDBXeNFT_stake_revert() public {
 test_mintXeNFT();
 vm.warp(block.timestamp + 2 days);
 vm.startPrank(Bob);
 console2.log("Bob redeems XeNFT#0");
 vm.warp(block.timestamp + 10 days);
 xenft.bulkClaimMintReward(xenftId1, Bob);
 console2.log("Bob mints DBXeNFT by locking XeNFT");
 factory.mintDBXENFT{value: 1 ether}(xenftId1);
 dBxenftId1 = counter;
 counter++;
 vm.warp(block.timestamp + 3 days);
 console2.log("Bob stakes 10 XEN on DBXeNFT#0");
 // if fixed this should be commented and work;
 vm.expectRevert();
 factory.stake{value: 1 ether}(10 ether, dBxenftId1);
 vm.stopPrank();
 }
}