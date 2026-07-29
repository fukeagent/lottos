// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V25StrictDiamondHandsForfeitureTest is V18TestBase {
    uint256 internal startWeight;

    function setUp() public override {
        super.setUp();
        startWeight = token.minEligibleAmount();
    }

    function _fundAndStart(address[] memory holders, uint256[] memory weights) internal returns (uint256 roundId) {
        for (uint256 i; i < holders.length; ++i) {
            token.transfer(holders[i], weights[i]);
        }
        token.activateTrading();
        vm.deal(address(engine), 1 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        roundId = engine.currentRoundId();
    }

    function _startTwoEqualHolders() internal returns (uint256 roundId, uint256 aliceIndex, uint256 bobIndex) {
        address[] memory holders = new address[](2);
        holders[0] = user1;
        holders[1] = user2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = startWeight;
        weights[1] = startWeight;
        roundId = _fundAndStart(holders, weights);
        aliceIndex = token.eligibleIndexOf(user1);
        bobIndex = token.eligibleIndexOf(user2);
    }

    function _trigger(uint256 roundId) internal {
        vm.warp(block.timestamp + engine.roundDuration() + 1);
        vm.roll(block.number + 1);
        engine.triggerDraw(roundId);
    }

    function test_DipForfeitsFullStartWeightAndResidualFinderSelectsBob() public {
        (uint256 roundId, uint256 aliceIndex, uint256 bobIndex) = _startTwoEqualHolders();

        vm.prank(user1);
        token.transfer(owner, 1);

        assertEq(engine.forfeitedRoundByIndex(aliceIndex), roundId);
        assertEq(engine.roundRemainingWeight(roundId), startWeight);
        assertEq(engine.treeFindByCumulativeRemaining(0, roundId), bobIndex);
        assertEq(engine.treeFindByCumulativeRemaining(startWeight - 1, roundId), bobIndex);

        _trigger(roundId);
        vm.roll(block.number + engine.DRAW_DELAY_BLOCKS() + 1);
        engine.payLottery(roundId);

        assertEq(engine.getRoundWinner(roundId), user2);
        assertEq(engine.roundAttemptsCursor(roundId), 1, "residual sampling must not retry Alice");
    }

    function test_BuyingMoreDoesNotIncreaseCurrentRoundWeight() public {
        (uint256 roundId,, uint256 bobIndex) = _startTwoEqualHolders();

        token.transfer(user2, startWeight);

        assertEq(engine.roundRemainingWeight(roundId), startWeight * 2);
        assertEq(token.getEligibleWeightAtRound(bobIndex, roundId), startWeight);
        assertEq(token.getEligibleTotalWeight(), startWeight * 3);
    }

    function test_DipAndRebuyDoesNotRestoreForfeitedWeight() public {
        (uint256 roundId, uint256 aliceIndex, uint256 bobIndex) = _startTwoEqualHolders();

        vm.prank(user1);
        token.transfer(owner, 1);
        token.transfer(user1, 1);

        assertEq(engine.forfeitedRoundByIndex(aliceIndex), roundId);
        assertEq(engine.roundRemainingWeight(roundId), startWeight);
        assertEq(engine.treeFindByCumulativeRemaining(0, roundId), bobIndex);
    }

    function test_TransferAfterTriggerDoesNotForfeitCurrentRound() public {
        (uint256 roundId, uint256 aliceIndex,) = _startTwoEqualHolders();
        _trigger(roundId);

        vm.prank(user1);
        token.transfer(owner, 1);

        assertEq(engine.forfeitedRoundByIndex(aliceIndex), 0);
        assertEq(engine.roundRemainingWeight(roundId), startWeight * 2);
        assertFalse(token.diamondHandsEpochActive());
    }

    function test_ForfeitureIsIdempotentAndReceiverIsNotChecked() public {
        (uint256 roundId, uint256 aliceIndex, uint256 bobIndex) = _startTwoEqualHolders();

        vm.prank(user1);
        token.transfer(user2, 1);
        uint256 remainingAfterFirst = engine.roundRemainingWeight(roundId);

        vm.prank(user1);
        token.transfer(user2, 1);

        assertEq(engine.forfeitedRoundByIndex(aliceIndex), roundId);
        assertEq(engine.forfeitedRoundByIndex(bobIndex), 0, "receiver must never forfeit by receiving");
        assertEq(engine.roundRemainingWeight(roundId), remainingAfterFirst);
    }

    function test_SoleHolderForfeitExpiresAndReleasesPrize() public {
        address[] memory holders = new address[](1);
        holders[0] = user1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = startWeight;
        uint256 roundId = _fundAndStart(holders, weights);
        uint256 reserved = engine.reservedPrizePool();

        vm.prank(user1);
        token.transfer(owner, 1);
        assertEq(engine.roundRemainingWeight(roundId), 0);

        engine.expireZeroRemainingWeight(roundId);

        assertEq(uint256(engine.getRoundStatus(roundId)), uint256(LotteryEngine.RoundStatus.EXPIRED));
        assertEq(engine.reservedPrizePool(), 0);
        assertEq(engine.totalPendingWinnerPayouts(), 0);
        assertEq(engine.availableLotteryBalance(), address(engine).balance);
        assertGt(reserved, 0);
    }

    function testFuzz_ResidualFinderMatchesNaiveTwoHolderModel(uint96 aliceDipRaw, uint96 targetRaw) public {
        (uint256 roundId,, uint256 bobIndex) = _startTwoEqualHolders();
        uint256 dip = bound(uint256(aliceDipRaw), 1, startWeight);

        vm.prank(user1);
        token.transfer(owner, dip);

        uint256 target = bound(uint256(targetRaw), 0, startWeight - 1);
        assertEq(engine.treeFindByCumulativeRemaining(target, roundId), bobIndex);
    }

    function testFuzz_ResidualFinderMatchesNaiveEightHolderModel(uint8 forfeitureMask, uint96 targetRaw) public {
        address[] memory holders = new address[](8);
        uint256[] memory weights = new uint256[](8);
        for (uint256 i; i < 8; ++i) {
            holders[i] = address(uint160(0x1000 + i));
            weights[i] = startWeight;
            token.setExemptions(holders[i], true, false, false);
        }
        uint256 roundId = _fundAndStart(holders, weights);

        // Keep the final holder to guarantee a non-empty residual model.
        uint256 mask = uint256(forfeitureMask) & 0x7f;
        uint256 survivors;
        for (uint256 i; i < 8; ++i) {
            if ((mask & (1 << i)) != 0) {
                vm.prank(holders[i]);
                token.transfer(owner, 1);
            } else {
                survivors++;
            }
        }

        uint256 target = bound(uint256(targetRaw), 0, survivors * startWeight - 1);
        uint256 cursor;
        uint256 expectedIndex;
        for (uint256 i; i < 8; ++i) {
            if ((mask & (1 << i)) == 0) {
                if (target < cursor + startWeight) {
                    expectedIndex = token.eligibleIndexOf(holders[i]);
                    break;
                }
                cursor += startWeight;
            }
        }

        assertEq(engine.roundRemainingWeight(roundId), survivors * startWeight);
        assertEq(engine.treeFindByCumulativeRemaining(target, roundId), expectedIndex);
    }

    function test_Gas_PayLotteryWith90PercentForfeitedUsesOneAttempt() public {
        _assertDominantHolderForfeitUsesOneAttempt(9);
    }

    function test_Gas_PayLotteryWith99Point9PercentForfeitedUsesOneAttempt() public {
        _assertDominantHolderForfeitUsesOneAttempt(999);
    }

    function _assertDominantHolderForfeitUsesOneAttempt(uint256 dominantMultiple) internal {
        address[] memory holders = new address[](2);
        holders[0] = user1;
        holders[1] = user2;
        uint256[] memory weights = new uint256[](2);
        weights[0] = startWeight * dominantMultiple;
        weights[1] = startWeight;
        uint256 roundId = _fundAndStart(holders, weights);

        vm.prank(user1);
        token.transfer(owner, 1);
        assertEq(engine.roundRemainingWeight(roundId), startWeight);

        _trigger(roundId);
        vm.roll(block.number + engine.DRAW_DELAY_BLOCKS() + 1);
        engine.payLottery(roundId);

        assertEq(engine.getRoundWinner(roundId), user2);
        assertEq(engine.roundAttemptsCursor(roundId), 1);
    }

    function test_Gas_TransferWithoutActiveRound() public {
        token.transfer(user1, startWeight * 2);
        token.activateTrading();
        uint256 gasBefore = gasleft();
        vm.prank(user1);
        token.transfer(owner, 1);
        emit log_named_uint("transfer without active round", gasBefore - gasleft());
    }

    function test_Gas_ActiveRoundSenderNotInSnapshot() public {
        address[] memory holders = new address[](1);
        holders[0] = user1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = startWeight;
        _fundAndStart(holders, weights);
        token.transfer(user3, startWeight * 2);

        uint256 gasBefore = gasleft();
        vm.prank(user3);
        token.transfer(owner, 1);
        emit log_named_uint("active round sender absent from snapshot", gasBefore - gasleft());
    }

    function test_Gas_SnapshotSenderStillAboveStartThenFirstAndRepeatedForfeit() public {
        address[] memory holders = new address[](1);
        holders[0] = user1;
        uint256[] memory weights = new uint256[](1);
        weights[0] = startWeight * 2;
        _fundAndStart(holders, weights);
        token.transfer(user1, startWeight);

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        token.transfer(owner, 1);
        emit log_named_uint("snapshot sender remains above start", gasBefore - gasleft());

        gasBefore = gasleft();
        vm.prank(user1);
        token.transfer(owner, startWeight);
        emit log_named_uint("first forfeiture", gasBefore - gasleft());

        gasBefore = gasleft();
        vm.prank(user1);
        token.transfer(owner, 1);
        emit log_named_uint("repeated transfer after forfeiture", gasBefore - gasleft());
    }

    function test_Gas_10Forfeitures() public {
        _measureManyForfeitures(10);
    }

    function test_Gas_50Forfeitures() public {
        _measureManyForfeitures(50);
    }

    function _measureManyForfeitures(uint256 count) internal {
        address[] memory holders = new address[](count);
        uint256[] memory weights = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            holders[i] = address(uint160(0x5000 + i));
            weights[i] = startWeight;
            token.setExemptions(holders[i], true, false, false);
        }
        uint256 roundId = _fundAndStart(holders, weights);

        uint256 gasBefore = gasleft();
        for (uint256 i; i < count; ++i) {
            vm.prank(holders[i]);
            token.transfer(owner, 1);
        }
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint(count == 10 ? "10 forfeitures" : "50 forfeitures", gasUsed);
        assertEq(engine.roundRemainingWeight(roundId), 0);
    }
}
