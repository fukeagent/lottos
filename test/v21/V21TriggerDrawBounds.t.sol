// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V21TriggerDrawBoundsTest is V18TestBase {
    function setUp() public override {
        super.setUp();
        vm.deal(address(engine), 100 ether);
        vm.warp(block.timestamp + 10 hours);
        token.activateTrading();
        vm.warp(block.timestamp + 3 hours);

        vm.roll(100);
        vm.prank(owner);
        token.transfer(user1, 1500 ether);
    }

    function testTriggerDrawFailsAfterGracePeriod() public {
        vm.roll(101);
        vm.prank(owner);
        engine.startLotteryEpoch();
        uint256 rId = engine.currentRoundId();

        // Warp past holding duration + grace period
        vm.warp(block.timestamp + 30 minutes + 1 hours + 1 seconds);

        vm.expectRevert("Grace period missed");
        vm.prank(owner);
        engine.triggerDraw(rId);
    }

    function testExpireStartedEpoch() public {
        vm.roll(101);
        vm.prank(owner);
        engine.startLotteryEpoch();
        uint256 rId = engine.currentRoundId();

        // Expire should fail if before grace period
        vm.warp(block.timestamp + 30 minutes + 1 hours - 1 seconds);
        vm.expectRevert("Grace period not missed");
        engine.expireStartedEpoch(rId);

        // Warp past holding duration + grace period
        vm.warp(block.timestamp + 1 seconds);

        engine.expireStartedEpoch(rId);
        assertEq(uint256(engine.getRoundStatus(rId)), uint256(4)); // EXPIRED
    }
}
