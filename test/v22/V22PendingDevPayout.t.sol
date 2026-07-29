// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract ToggleDevReceiver {
    bool public rejects = true;

    function setRejects(bool value) external {
        rejects = value;
    }

    receive() external payable {
        require(!rejects, "reject dev payout");
    }
}

contract V22PendingDevPayoutTest is V18TestBase {
    ToggleDevReceiver receiver;

    function setUp() public override {
        super.setUp();
        receiver = new ToggleDevReceiver();
        engine.setDevFeeReceiver(address(receiver));
    }

    function _completeRoundWithRejectedDevPayout() internal returns (uint256 roundId, uint256 devAmount) {
        token.transfer(user1, token.minEligibleAmount());
        token.activateTrading();
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        roundId = engine.currentRoundId();
        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);
        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);
        engine.payLottery(roundId);

        devAmount = engine.getRoundDevAmount(roundId);
        assertGt(devAmount, 0);
    }

    function test_FailedDevPayoutIsReservedAndCannotBeRedirectedOrReused() public {
        (, uint256 devAmount) = _completeRoundWithRejectedDevPayout();

        assertEq(engine.pendingDevPayout(address(receiver)), devAmount);
        assertEq(engine.totalPendingDevPayouts(), devAmount);
        uint256 availableBeforeNextRound = address(engine).balance - devAmount;
        assertEq(engine.availableLotteryBalance(), availableBeforeNextRound);

        engine.setDevFeeReceiver(user3);
        assertEq(engine.pendingDevPayout(address(receiver)), devAmount, "old receiver retains its debt");
        assertEq(engine.pendingDevPayout(user3), 0);

        vm.warp(block.timestamp + 31 minutes);
        engine.startLotteryEpoch();
        uint256 selectedPrize = engine.getRoundSelectedPrizePool(engine.currentRoundId());
        assertEq(selectedPrize, (availableBeforeNextRound * engine.INITIAL_TIER1_BPS()) / 10_000);
        assertEq(
            engine.availableLotteryBalance(),
            availableBeforeNextRound - selectedPrize,
            "new round must not reserve dev debt again"
        );
    }

    function test_PermissionlessRetryLeavesFailureUnchangedThenPaysExactDebt() public {
        (, uint256 devAmount) = _completeRoundWithRejectedDevPayout();
        uint256 balanceBefore = address(engine).balance;

        vm.prank(user2);
        engine.payPendingDevPayout(address(receiver));
        assertEq(engine.pendingDevPayout(address(receiver)), devAmount);
        assertEq(engine.totalPendingDevPayouts(), devAmount);
        assertEq(address(engine).balance, balanceBefore);
        uint256 availableBeforeRetry = balanceBefore - devAmount;
        assertEq(engine.availableLotteryBalance(), availableBeforeRetry);

        receiver.setRejects(false);
        vm.prank(user2);
        engine.payPendingDevPayout(address(receiver));

        assertEq(engine.pendingDevPayout(address(receiver)), 0);
        assertEq(engine.totalPendingDevPayouts(), 0);
        assertEq(address(receiver).balance, devAmount);
        assertEq(address(engine).balance, balanceBefore - devAmount);
        assertEq(engine.availableLotteryBalance(), availableBeforeRetry, "clearing debt does not create surplus");
    }

    function test_ReceiverCanClaimWithManualGasBudget() public {
        (, uint256 devAmount) = _completeRoundWithRejectedDevPayout();
        receiver.setRejects(false);

        vm.prank(address(receiver));
        engine.claimPendingDevPayout();

        assertEq(engine.pendingDevPayout(address(receiver)), 0);
        assertEq(address(receiver).balance, devAmount);
        assertEq(engine.MANUAL_PAYOUT_GAS(), 300_000);
    }
}
