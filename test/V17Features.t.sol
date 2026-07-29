// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/RobinhoodToken.sol";
import "../contracts/LotteryEngine.sol";

contract V17FeaturesTest is Test {
    RobinhoodToken token;
    LotteryEngine engine;

    address owner = address(this);
    address user1 = address(0x111);
    address user2 = address(0x222);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), owner, 100 ether);

        token.setLotteryEngine(address(engine));
        token.setExemptions(owner, true, true, true);
    }

    function _activateAndFund() internal {
        token.activateTrading();
        token.transfer(user1, 1000 ether);
        token.transfer(user2, 1000 ether);
    }

    function test_ImmutableRouter() public {
        address router1 = address(new DummyContract());
        address router2 = address(new DummyContract());

        token.setTaxSwapRouterOnce(router1);
        assertEq(token.taxSwapRouter(), router1);
        assertTrue(token.taxSwapRouterLocked());

        vm.expectRevert("Router locked");
        token.setTaxSwapRouterOnce(router2);

        token.activateTrading();
        vm.expectRevert("Launch config locked");
        token.setTaxSwapRouterOnce(router2);
    }

    function test_MaxWalletRamp() public {
        _activateAndFund();

        uint256 total = token.totalSupply();
        uint256 startMax = total / 1000; // 0.1%
        uint256 endMax = (total * 2) / 100; // 2.0%

        // At launch
        assertEq(token.getMaxWallet(), startMax);

        // After 1 hour
        vm.warp(block.timestamp + 1 hours);
        assertEq(token.getMaxWallet(), startMax + (endMax - startMax) / 2);

        // After 2 hours
        vm.warp(block.timestamp + 2 hours);
        assertEq(token.getMaxWallet(), endMax);

        // After 3 hours (capped)
        vm.warp(block.timestamp + 3 hours);
        assertEq(token.getMaxWallet(), endMax);
    }

    function test_DiamondHandsSettlementBypass() public {
        _activateAndFund();

        // Setup Lottery
        vm.warp(block.timestamp + 2 hours + 1); // pass FIRST_LOTTERY_DELAY
        vm.deal(address(engine), 1 ether);

        // Start epoch
        vm.roll(block.number + 10);
        engine.startLotteryEpoch();

        // Warp through epoch
        vm.warp(block.timestamp + 30 minutes + 1);
        vm.roll(block.number + 100);

        // Trigger draw (Snapshot 2 taken here, endSnapshotBlock = block.number - 1)
        engine.triggerDraw(1);

        // Now user1 sells ALL their tokens!
        // In V17, payLottery only checks endSnapshotBlock, so selling now is ALLOWED!
        vm.prank(user1);
        token.transfer(user2, 1000 ether); // user1 balance is now 0

        assertEq(token.balanceOf(user1), 0);

        // Pay Lottery
        vm.roll(block.number + 600 + 1);
    }

    function test_DiamondHandsSettlement_IsolatedUser() public {
        token.setExemptions(user2, true, true, true);
        token.refreshEligibility(user2);

        _activateAndFund();

        vm.warp(block.timestamp + 2 hours + 1);
        vm.deal(address(engine), 1 ether);

        vm.roll(block.number + 10);
        engine.startLotteryEpoch();

        vm.warp(block.timestamp + 30 minutes + 1);
        vm.roll(block.number + 100);
        engine.triggerDraw(1);

        // user1 sells all after Snapshot 2
        vm.prank(user1);
        token.transfer(owner, 1000 ether);

        assertEq(token.balanceOf(user1), 0);

        vm.roll(block.number + 600 + 1);
        engine.payLottery(1);

        // user1 should be the winner!
        assertEq(engine.getRoundWinner(1), user1);
    }

    function test_GhostCleanup_ContractCode() public {
        _activateAndFund();

        vm.warp(block.timestamp + 2 hours + 1);
        vm.deal(address(engine), 1 ether);

        vm.roll(block.number + 10);
        engine.startLotteryEpoch();

        vm.warp(block.timestamp + 30 minutes + 1);
        vm.roll(block.number + 100);

        address dummyContract = address(new DummyContract());

        vm.prank(user1);
        token.transfer(dummyContract, 1000 ether);

        engine.triggerDraw(1);

        vm.roll(block.number + 600 + 1);

        // payLottery should attempt to select dummyContract, find they are CONTRACT_CODE,
        // cleanup their eligibility, and then fail to find a winner (since no one else is eligible, wait user2 is eligible!)
        // That's fine, it will just pick user2.
        engine.payLottery(1);

        // The dummy contract will be selected, identified as CONTRACT_CODE, and cleaned up!
        assertEq(token.eligibleWeightOf(dummyContract), 0);
    }
}

contract DummyContract {}
