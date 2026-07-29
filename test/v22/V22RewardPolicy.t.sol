// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract RejectingActionActor {
    function start(LotteryEngine engine) external {
        engine.startLotteryEpoch();
    }

    function trigger(LotteryEngine engine, uint256 roundId) external {
        engine.triggerDraw(roundId);
    }

    function pay(LotteryEngine engine, uint256 roundId) external {
        engine.payLottery(roundId);
    }

    receive() external payable {
        revert("reject action reward");
    }
}

contract V22RewardPolicyTest is V18TestBase {
    function _prepareLottery() internal {
        token.transfer(user1, token.minEligibleAmount());
        token.activateTrading();
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);
    }

    function test_ActionRewardsOnlyAttemptAfterSuccessfulCompletionAndNeverCreateDebt() public {
        _prepareLottery();
        RejectingActionActor actor = new RejectingActionActor();

        actor.start(engine);
        uint256 roundId = engine.currentRoundId();
        assertEq(address(actor).balance, 0, "start reward must be deferred");

        vm.warp(block.timestamp + 30 minutes + 1);
        actor.trigger(engine, roundId);
        assertEq(address(actor).balance, 0, "trigger reward must be deferred");

        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);
        actor.pay(engine, roundId);

        assertEq(uint256(engine.getRoundStatus(roundId)), uint256(LotteryEngine.RoundStatus.FULFILLED));
        assertGt(engine.getRoundStartReward(roundId), 0);
        assertGt(engine.getRoundTriggerReward(roundId), 0);
        assertGt(engine.getRoundPayReward(roundId), 0);
        assertEq(address(actor).balance, 0, "failed action rewards are best effort");
        assertEq(engine.totalPendingWinnerPayouts(), 0);
        assertEq(engine.totalPendingDevPayouts(), 0);
    }

    function test_ExpiredRoundPaysNoActionRewards() public {
        _prepareLottery();

        vm.prank(user2);
        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();
        vm.warp(block.timestamp + 30 minutes + 1);
        vm.prank(user3);
        engine.triggerDraw(roundId);

        uint256 starterBalance = user2.balance;
        uint256 triggererBalance = user3.balance;
        vm.roll(engine.getRoundRandomnessBlock(roundId) + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        engine.expireLottery(roundId);

        assertEq(uint256(engine.getRoundStatus(roundId)), uint256(LotteryEngine.RoundStatus.EXPIRED));
        assertEq(user2.balance, starterBalance);
        assertEq(user3.balance, triggererBalance);
        assertEq(engine.totalPendingWinnerPayouts(), 0);
        assertEq(engine.totalPendingDevPayouts(), 0);
    }
}
