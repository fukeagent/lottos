// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract TokenHarness is RobinhoodToken {
    function tryAutoLotteryStepHarness(address rewardTo) external {
        _tryAutoLotteryStep(rewardTo);
    }
}

contract V20AutoStepPendingPayoutTest is V18TestBase {
    address winner = user1;
    TokenHarness harness;

    function setUp() public override {
        super.setUp();

        // Replace token with harness
        harness = new TokenHarness();
        engine = new LotteryEngine(address(harness), devFeeReceiver, 100 ether);
        harness.setLotteryEngine(address(engine));
        harness.setExemptions(owner, true, true, true);
        harness.setExemptions(user1, true, false, false);
        harness.activateTrading();

        harness.transfer(winner, 1000 ether);

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

        assertTrue(engine.pendingWinnerPayout(winner) > 0);
    }

    function test_V20_TokenSideBestEffortRetrySuccess() public {
        uint256 amount = engine.pendingWinnerPayout(winner);
        vm.clearMockedCalls();
        vm.deal(winner, 0);

        vm.mockCallRevert(
            address(engine),
            abi.encodeWithSelector(ILotteryEngine.autoLotteryStep.selector),
            bytes("autoLotteryStep reverted")
        );

        harness.tryAutoLotteryStepHarness(address(0xdead));

        assertEq(engine.pendingWinnerPayout(winner), 0);
        assertEq(winner.balance, amount);
    }

    function test_V20_TokenSideBestEffortRetryFailure() public {
        // Mock revert is still active on winner
        harness.tryAutoLotteryStepHarness(address(0xdead));
        assertTrue(engine.pendingWinnerPayout(winner) > 0);
    }
}
