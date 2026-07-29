// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract V22FenwickOpeningFuzzTest is V18TestBase {
    function testFuzz_SameBlockMutationPreservesActiveSnapshotTotalWeight(uint96 addedRaw) public {
        uint256 openingWeight = token.minEligibleAmount();
        token.transfer(user1, openingWeight);
        vm.roll(block.number + 1);

        uint256 added = bound(uint256(addedRaw), 1, 10_000 ether);
        token.transfer(user1, added);

        vm.prank(address(engine));
        token.beginLotterySnapshot(1);

        assertEq(token.getActiveSnapshotTotalWeight(1), openingWeight);
        assertEq(token.getEligibleTotalWeight(), openingWeight + added, "live weight should still update");
    }
}
