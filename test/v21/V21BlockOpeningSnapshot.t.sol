// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";
import "forge-std/console.sol";

contract V21BlockOpeningSnapshotTest is V18TestBase {
    function testBlockOpeningSnapshot() public {
        vm.deal(address(engine), 100 ether);
        vm.warp(block.timestamp + 10 hours);
        token.activateTrading();
        vm.warp(block.timestamp + 3 hours);

        vm.roll(100);
        vm.prank(owner);
        token.transfer(user1, 1500 ether);

        console.log("After block 100 transfer:");
        console.log("Total Eligible Balance:", token.totalEligibleBalance());

        vm.roll(101);

        // Within block 101, user1 transfers to user2
        vm.prank(user1);
        token.transfer(user2, 500 ether);

        console.log("After block 101 transfer:");
        console.log("Total Eligible Balance:", token.totalEligibleBalance());

        // Same block: start lottery
        vm.prank(owner);
        engine.startLotteryEpoch();

        uint256 rId = engine.currentRoundId();
        uint256 startBlock = engine.getRoundStartSnapshotBlock(rId);

        assertEq(startBlock, 100);

        uint256 weight = token.getActiveSnapshotTotalWeight(rId);
        assertEq(weight, 1500 ether);
    }
}
