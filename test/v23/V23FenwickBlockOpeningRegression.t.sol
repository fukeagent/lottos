// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V23FenwickBlockOpeningRegressionTest is V18TestBase {
    uint256 internal constant ALICE_OPENING = 100 ether;
    uint256 internal constant BOB_OPENING = 100 ether;

    function setUp() public override {
        super.setUp();
        token.setMinEligibleAmount(100 ether);
    }

    function _allocateOpeningWeights() internal returns (uint256 aliceIndex, uint256 bobIndex) {
        token.transfer(user1, ALICE_OPENING);
        token.transfer(user2, BOB_OPENING);
        aliceIndex = token.eligibleIndexOf(user1);
        bobIndex = token.eligibleIndexOf(user2);
        assertEq(aliceIndex, 1);
        assertEq(bobIndex, 2);
    }

    function _beginSnapshot(uint256 roundId) internal {
        vm.prank(address(engine));
        token.beginLotterySnapshot(roundId);
    }

    function test_PreStartSameBlockTopUpDoesNotCrowdOutBobOpeningOdds() public {
        (, uint256 bobIndex) = _allocateOpeningWeights();
        vm.roll(block.number + 1);

        token.transfer(user1, 100 ether);
        _beginSnapshot(1);

        assertEq(token.getActiveSnapshotTotalWeight(1), 200 ether);
        assertEq(token.getEligibleTotalWeight(), 300 ether);
        assertEq(token.treeFindByCumulativeAtRound(50 ether, 1), token.eligibleIndexOf(user1));
        assertEq(
            token.treeFindByCumulativeAtRound(150 ether, 1),
            bobIndex,
            "same-block Alice top-up must not crowd out Bob's opening odds"
        );
    }

    function testFuzz_PreStartSameBlockTopUpPreservesBobOpeningRange(uint96 addedRaw, uint96 targetRaw) public {
        (, uint256 bobIndex) = _allocateOpeningWeights();
        vm.roll(block.number + 1);

        uint256 added = bound(uint256(addedRaw), 1 ether, 10_000 ether);
        uint256 target = bound(uint256(targetRaw), ALICE_OPENING, ALICE_OPENING + BOB_OPENING - 1);

        token.transfer(user1, added);
        _beginSnapshot(1);

        assertEq(token.getActiveSnapshotTotalWeight(1), ALICE_OPENING + BOB_OPENING);
        assertEq(token.getEligibleTotalWeight(), ALICE_OPENING + BOB_OPENING + added);
        assertEq(token.treeFindByCumulativeAtRound(target, 1), bobIndex);
    }

    function test_PostStartSameBlockTopUpDoesNotCrowdOutBobOpeningOdds() public {
        (, uint256 bobIndex) = _allocateOpeningWeights();
        vm.roll(block.number + 1);

        _beginSnapshot(1);
        token.transfer(user1, 100 ether);

        assertEq(token.getActiveSnapshotTotalWeight(1), 200 ether);
        assertEq(token.getEligibleTotalWeight(), 300 ether);
        assertEq(
            token.treeFindByCumulativeAtRound(150 ether, 1),
            bobIndex,
            "post-start Alice top-up must not crowd out Bob's opening odds"
        );
    }
}
