// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V20PendingWinnerRetryQueueTest is V18TestBase {
    address winner = user1;

    function setUp() public override {
        super.setUp();
        token.activateTrading();

        token.transfer(winner, 1000 ether);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);

        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);

        vm.mockCallRevert(winner, bytes(""), bytes("mock revert"));
        vm.etch(winner, bytes(""));
        engine.payLottery(roundId);
    }

    function test_V20_StoresDebtAndQueues() public {
        uint256 amount = engine.pendingWinnerPayout(winner);
        assertTrue(amount > 0);
        assertTrue(engine.pendingWinnerQueued(winner));
        assertEq(engine.pendingWinnerQueue(0), winner);
        assertEq(engine.pendingWinnerRetryCount(winner), 0);
        assertFalse(engine.pendingWinnerAutoRetryDisabled(winner));
    }

    function test_V20_RepeatedFailedAutoRetries() public {
        uint256 amount = engine.pendingWinnerPayout(winner);

        // Retry 1
        engine.processPendingWinnerPayouts(1);
        assertEq(engine.pendingWinnerRetryCount(winner), 1);
        assertTrue(engine.pendingWinnerQueued(winner));

        // Retry 2
        engine.processPendingWinnerPayouts(1);
        assertEq(engine.pendingWinnerRetryCount(winner), 2);
        assertTrue(engine.pendingWinnerQueued(winner));

        // Retry 3 (Max)
        engine.processPendingWinnerPayouts(1);
        assertEq(engine.pendingWinnerRetryCount(winner), 3);
        assertFalse(engine.pendingWinnerQueued(winner));
        assertEq(engine.pendingWinnerQueuedCount(), 0, "disabled winner must leave active queue count");
        assertTrue(engine.pendingWinnerAutoRetryDisabled(winner));

        // Debt remains
        assertEq(engine.pendingWinnerPayout(winner), amount);

        // availableLotteryBalance still excludes debt
        uint256 expectedAvailable = address(engine).balance - engine.reservedPrizePool() - amount;
        assertEq(engine.availableLotteryBalance(), expectedAvailable);

        // Retry 4 (Should be skipped by processor)
        engine.processPendingWinnerPayouts(1);
        assertEq(engine.pendingWinnerRetryCount(winner), 3); // No increase
        assertFalse(engine.pendingWinnerQueued(winner));

        // Still can claim
        vm.clearMockedCalls();
        vm.deal(winner, 0);

        vm.prank(winner);
        engine.claimPendingWinnerPayout();

        assertEq(engine.pendingWinnerPayout(winner), 0);
        assertFalse(engine.pendingWinnerAutoRetryDisabled(winner));
        assertEq(engine.pendingWinnerRetryCount(winner), 0);
        assertEq(winner.balance, amount);
    }

    function test_V20_DirectRetryFailureKeepsDebt() public {
        uint256 amount = engine.pendingWinnerPayout(winner);

        vm.prank(winner);
        engine.claimPendingWinnerPayout(); // Will fail due to mockCallRevert still active

        assertEq(engine.pendingWinnerPayout(winner), amount);
        // Retry count should NOT increase on manual retry
        assertEq(engine.pendingWinnerRetryCount(winner), 0);
    }

    function test_V20_NoDuplicateSpam() public {
        // Setup another failed payout for same winner
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);

        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);

        engine.payLottery(roundId); // Fails again

        // Queue length should still be 1 (we don't push duplicates!)
        assertEq(engine.pendingWinnerQueue(0), winner);
        vm.expectRevert();
        engine.pendingWinnerQueue(1);
    }
}
