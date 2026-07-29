// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";

contract V22BlockOpeningHolderMappingTest is Test {
    RobinhoodToken token;
    LotteryEngine engine;

    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address user3 = address(0x3333);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(0x4444), 100 ether);
        token.setLotteryEngine(address(engine));

        token.setExemptions(address(this), true, true, true);
        token.setExemptions(user1, true, false, false);
        token.setExemptions(user2, true, false, false);
        token.setExemptions(user3, true, false, false);

        token.activateTrading();
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);

        // Give the contract some ETH for payouts
        vm.deal(address(engine), 100 ether);
    }

    function test_sameBlockExitResolvesOldHolder() public {
        uint256 minEligible = token.minEligibleAmount();
        token.transfer(user1, minEligible);

        vm.roll(block.number + 1);

        // user1 sends away
        vm.prank(user1);
        token.transfer(user2, minEligible);

        // engine starts round in the SAME block
        vm.prank(address(engine));
        token.beginLotterySnapshot(1);

        // getHolderByEligibleIndexAtRound should resolve to user1 because they were there at the opening of the block
        address holder = token.getHolderByEligibleIndexAtRound(1, 1);
        assertEq(holder, user1);
    }

    function test_indexReuseResolvesToOldHolder() public {
        uint256 minEligible = token.minEligibleAmount();
        token.transfer(user1, minEligible);

        vm.roll(block.number + 1);

        // user1 sends away
        vm.prank(user1);
        token.transfer(user2, minEligible);

        // user3 joins and takes user1's old index
        token.transfer(user3, minEligible);

        // engine starts round in the SAME block
        vm.prank(address(engine));
        token.beginLotterySnapshot(1);

        address holder = token.getHolderByEligibleIndexAtRound(1, 1);
        assertEq(holder, user1);
    }

    function test_openingZeroButLivePositiveRevertsStart() public {
        uint256 minEligible = token.minEligibleAmount();
        // Give token to user1 but in the same block as the snapshot

        vm.prank(address(engine));
        vm.expectRevert("No eligible weight");
        token.beginLotterySnapshot(1);

        // Let's actually give user1 some tokens, but the block opening is 0
        token.transfer(user1, minEligible);

        vm.prank(address(engine));
        vm.expectRevert("No eligible weight");
        token.beginLotterySnapshot(1);
    }

    function test_activeRoundQuarantineStillWorks() public {
        uint256 minEligible = token.minEligibleAmount();
        token.transfer(user1, minEligible);

        vm.roll(block.number + 1);

        vm.prank(address(engine));
        token.beginLotterySnapshot(1);

        // Quarantine by making user1 a contract
        vm.etch(user1, "0x1234");

        address holder = token.getHolderByEligibleIndexAtRound(1, 1);
        assertEq(holder, user1, "round mapping preserves ownership for cleanup");
        assertTrue(token.isLotteryIneligible(holder), "eligibility policy quarantines the contract");
    }
}
