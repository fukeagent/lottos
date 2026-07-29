// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V22RoundAwareWinnerResolutionTest is V18TestBase {
    function test_SameBlockIndexReusePaysBlockOpeningHolderWithoutBurningAttempts() public {
        uint256 eligibleAmount = token.minEligibleAmount();
        token.transfer(user1, eligibleAmount);
        token.activateTrading();

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);

        uint256 reusedIndex = token.eligibleIndexOf(user1);
        assertEq(reusedIndex, 1);

        // Alice exits, Bob reuses index 1, and Alice re-enters at a new live index.
        // All mutations and the round start occur in one block.
        vm.prank(user1);
        token.transfer(user2, eligibleAmount);
        token.transfer(user1, eligibleAmount);

        assertEq(token.getHolderByEligibleIndex(reusedIndex), user2, "guard: live lookup now points to Bob");

        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        assertEq(token.getHolderByEligibleIndexAtRound(reusedIndex, roundId), user1, "round lookup must preserve Alice");

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);
        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);

        engine.payLottery(roundId);

        assertEq(engine.getRoundWinner(roundId), user1);
        assertEq(engine.roundAttemptsCursor(roundId), 1, "live mismatch must not burn attempts");
        assertEq(uint256(engine.getRoundStatus(roundId)), uint256(LotteryEngine.RoundStatus.FULFILLED));
    }

    function test_Guard_LiveLookupWouldSelectBobWhoHadNoOpeningBalance() public {
        uint256 eligibleAmount = token.minEligibleAmount();
        token.transfer(user1, eligibleAmount);
        token.activateTrading();
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);

        uint256 reusedIndex = token.eligibleIndexOf(user1);
        uint256 openingBlock = block.number - 1;

        vm.prank(user1);
        token.transfer(user2, eligibleAmount);
        token.transfer(user1, eligibleAmount);
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();

        address liveCandidate = token.getHolderByEligibleIndex(reusedIndex);
        address roundCandidate = token.getHolderByEligibleIndexAtRound(reusedIndex, engine.currentRoundId());

        assertEq(liveCandidate, user2);
        assertEq(token.getPastBalance(liveCandidate, openingBlock), 0, "old engine candidate would fail");
        assertEq(roundCandidate, user1);
        assertEq(token.getPastBalance(roundCandidate, openingBlock), eligibleAmount);
    }
}
