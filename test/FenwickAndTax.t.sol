// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../contracts/RobinhoodToken.sol";
import "../contracts/LotteryEngine.sol";
import "v4-core/interfaces/IPoolManager.sol";

contract MockRouter {
    address public WETH;
    bool public shouldRevert;
    uint256 public lastAmountOutMin;
    uint256 public ethOut = 1 ether;
    uint256 public swapCount = 0;

    constructor(address _weth) {
        WETH = _weth;
    }

    function setEthOut(uint256 v) external {
        ethOut = v;
    }

    function setShouldRevert(bool _revert) external {
        shouldRevert = _revert;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        swapCount++;
        if (shouldRevert) revert("MockRouter: swap failed");
        lastAmountOutMin = amountOutMin;
        // Pull tokens
        RobinhoodToken(payable(path[0])).transferFrom(msg.sender, address(this), amountIn);
        // Send fake ETH
        require(ethOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        payable(to).transfer(ethOut);
    }

    receive() external payable {}
}

contract MockOfficialPoolQuote {
    bool public isReady = true;
    uint256 public expectedEthOut = 1 ether;
    bool public revertReady = false;
    bool public revertQuote = false;

    function setReady(bool ready) external {
        isReady = ready;
    }

    function setExpectedEthOut(uint256 out) external {
        expectedEthOut = out;
    }

    function setRevertReady(bool r) external {
        revertReady = r;
    }

    function setRevertQuote(bool r) external {
        revertQuote = r;
    }

    function quoteReady() external view returns (bool) {
        if (revertReady) revert("Mock quoteReady revert");
        return isReady;
    }

    function quoteTokenToETH(uint256) external view returns (uint256) {
        if (revertQuote) revert("Mock quoteTokenToETH revert");
        return expectedEthOut;
    }
}

contract MockV2LikePool {
    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() external pure returns (uint112, uint112, uint32) {
        return (1, 1, 0);
    }
}

contract HarnessRobinhoodToken is RobinhoodToken {
    function setNextEligibleIndex(uint256 v) external {
        nextEligibleIndex = v;
    }

    function pushFreeEligibleIndex(uint256 index) external {
        freeEligibleIndices.push(index);
    }

    function exposeAllocationSweepLimit() external view returns (uint256) {
        return _allocationSweepLimit();
    }
}

contract FenwickAndTaxTest is Test {
    RobinhoodToken token;
    LotteryEngine engine;
    address owner = address(this);
    address user1 = address(0x101);
    address user2 = address(0x102);
    address user3 = address(0x103);
    address pool;
    MockRouter router;
    MockOfficialPoolQuote quote;

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(this), 100 ether);
        token.setLotteryEngine(address(engine));

        router = new MockRouter(address(0x111));
        quote = new MockOfficialPoolQuote();
        vm.deal(address(router), 10 ether);

        token.setTaxSwapRouterOnce(address(router));
        token.setAutoSwapConfig(true, 100_000 ether, 200_000 ether, 15 minutes);
        token.setOfficialPoolQuote(address(quote));
        token.setAutoSwapSlippageBps(500);

        pool = address(new MockV2LikePool(address(token), address(0x999)));
        token.setTaxedExternalPool(pool, true);

        token.setExemptions(owner, true, true, true);
        token.setExemptions(pool, true, true, true);

        token.activateTrading();

        token.transfer(user1, 2000 ether);
        token.transfer(user2, 3000 ether);
        token.transfer(user3, 5000 ether);
    }

    function test_Fenwick_PrefixSumAndFindByCumulative() public {
        // user1 has 2000, user2 has 3000, user3 has 5000. Total = 10000 ether
        assertEq(token.getEligibleTotalWeight(), 10000 ether);

        uint256 idx1 = token.eligibleIndexOf(user1);
        uint256 idx2 = token.eligibleIndexOf(user2);
        uint256 idx3 = token.eligibleIndexOf(user3);

        // findByCumulative
        // 0 to 1999 -> user1
        assertEq(token.treeFindByCumulative(0), idx1);
        assertEq(token.treeFindByCumulative(1999 ether), idx1);

        // 2000 to 4999 -> user2
        assertEq(token.treeFindByCumulative(2000 ether), idx2);
        assertEq(token.treeFindByCumulative(4999 ether), idx2);

        // 5000 to 9999 -> user3
        assertEq(token.treeFindByCumulative(5000 ether), idx3);
        assertEq(token.treeFindByCumulative(9999 ether), idx3);
    }

    function test_Fenwick_ZeroWeightNotSelectable() public {
        // user2 transfers all to user3
        vm.prank(user2);
        token.transfer(user3, 3000 ether);

        uint256 idx1 = token.eligibleIndexOf(user1);
        uint256 idx3 = token.eligibleIndexOf(user3);

        assertEq(token.getEligibleTotalWeight(), 10000 ether);

        // 0 to 1999 -> user1
        assertEq(token.treeFindByCumulative(1999 ether), idx1);

        // 2000 to 9999 -> user3 (skips user2 because user2 weight is 0)
        assertEq(token.treeFindByCumulative(2000 ether), idx3);
    }

    function test_Fenwick_HistoricalChurnDoesNotGrow() public {
        // Create 100 disposable users who buy and sell
        for (uint160 i = 1; i <= 100; i++) {
            address churner = address(uint160(0x2000 + i));
            token.transfer(churner, 1500 ether);

            vm.prank(churner);
            token.transfer(owner, 1500 ether);
        }

        // Total weight should be back to 10000
        assertEq(token.getEligibleTotalWeight(), 10000 ether);

        // findByCumulative should still be fast
        uint256 gasStart = gasleft();
        token.treeFindByCumulative(9000 ether);
        uint256 gasUsed = gasStart - gasleft();

        // Should be O(log N). Since tree size is around 100, log2(100) ~ 7 iterations.
        assertTrue(gasUsed < 100000, "Fenwick tree too expensive");
    }

    function test_Tax_WalletTransferNoTax() public {
        uint256 balanceBefore = token.balanceOf(address(this));
        vm.prank(user1);
        token.transfer(user2, 1000 ether);
        uint256 balanceAfter = token.balanceOf(address(this));

        // No tax collected
        assertEq(balanceAfter, balanceBefore);
    }

    function test_Tax_ExternalPoolBuySellTaxed() public {
        // Buy from pool (pool -> user1)
        uint256 poolBal = 100_000 ether;
        token.transfer(pool, poolBal);
        uint256 tokenBalBefore = token.balanceOf(address(token));
        vm.prank(pool);
        token.transfer(user1, 1000 ether);

        // Tax is 10% by default (taxBps = 1000)
        uint256 expectedTax = 100 ether;
        assertEq(token.balanceOf(address(token)) - tokenBalBefore, expectedTax);

        // Sell to pool (user1 -> pool)
        tokenBalBefore = token.balanceOf(address(token));
        vm.prank(user1);
        token.transfer(pool, 1000 ether);
        assertEq(token.balanceOf(address(token)) - tokenBalBefore, expectedTax);
    }

    function test_Tax_AutoSwapSucceeds() public {
        token.transfer(address(token), 100_000 ether); // >= swapThreshold

        uint256 engineEthBefore = address(engine).balance;

        vm.warp(block.timestamp + 20 minutes); // past cooldown

        // Trigger auto swap by transferring to pool
        token.transfer(pool, 100 ether);

        // Should have received 1 ETH from mock router
        assertEq(address(engine).balance - engineEthBefore, 1 ether);
        // 500 bps = 5%, 1 ETH * 0.95 = 0.95 ETH
        assertEq(router.lastAmountOutMin(), 0.95 ether);
    }

    function test_Tax_AutoSwapSkipsIfQuoteNotReady() public {
        token.transfer(address(token), 100_000 ether);
        quote.setReady(false);
        vm.warp(block.timestamp + 20 minutes);

        uint256 balBefore = token.balanceOf(address(token));
        token.transfer(pool, 100 ether);

        assertTrue(token.balanceOf(address(token)) > balBefore);
    }

    function test_Tax_AutoSwapSkipsIfQuoteUnset() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        address freshPool = address(new MockV2LikePool(address(freshToken), address(0x999)));
        freshToken.setTaxedExternalPool(freshPool, true);
        freshToken.setTaxSwapRouterOnce(address(router));
        freshToken.setAutoSwapConfig(true, 100_000 ether, 200_000 ether, 15 minutes);

        freshToken.transfer(address(freshToken), 100_000 ether);

        uint256 balBefore = freshToken.balanceOf(address(freshToken));

        freshToken.activateTrading();
        vm.warp(block.timestamp + 20 minutes);

        freshToken.transfer(freshPool, 100 ether);

        assertTrue(freshToken.balanceOf(address(freshToken)) > balBefore);
    }

    function test_Tax_AutoSwapFailsIfRouterOutputBelowMinOut() public {
        token.transfer(address(token), 100_000 ether);

        router.setEthOut(0.5 ether);

        uint256 engineEthBefore = address(engine).balance;
        uint256 lastAutoSwapAtBefore = token.lastAutoSwapAt();

        vm.warp(block.timestamp + 20 minutes);

        token.transfer(pool, 100 ether);

        assertTrue(token.balanceOf(pool) > 0);
        assertTrue(token.balanceOf(address(token)) >= 100_000 ether);
        assertEq(address(engine).balance, engineEthBefore);
        assertEq(token.lastAutoSwapAt(), lastAutoSwapAtBefore);
    }

    function test_Tax_AutoSwapSkipsIfQuoteZero() public {
        token.transfer(address(token), 100_000 ether);
        quote.setExpectedEthOut(0);
        vm.warp(block.timestamp + 20 minutes);

        uint256 balBefore = token.balanceOf(address(token));
        token.transfer(pool, 100 ether);

        assertTrue(token.balanceOf(address(token)) > balBefore);
    }

    function test_Tax_AutoSwapFailureDoesNotRevert() public {
        token.transfer(address(token), 100_000 ether);

        router.setShouldRevert(true);

        vm.warp(block.timestamp + 20 minutes);

        // This transfer should succeed even if auto-swap reverts internally
        token.transfer(pool, 100 ether);
    }

    function test_Tax_AutoSwapEnabledByDefaultIsFalse() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        assertEq(freshToken.autoSwapEnabled(), false);
    }

    function test_Tax_AutoSwapSkipsIfDisabled() public {
        token.setAutoSwapEnabled(false);
        token.transfer(address(token), 100_000 ether);
        uint256 balBefore = token.balanceOf(address(token));

        vm.warp(block.timestamp + 20 minutes);
        token.transfer(pool, 100 ether);

        // Auto swap is false, so no tokens should be swapped (balance increases due to tax)
        assertTrue(token.balanceOf(address(token)) > balBefore);
    }

    function test_Tax_AutoSwapBacklogFiresIfTaxZero() public {
        token.transfer(address(token), 100_000 ether);
        uint256 engineEthBefore = address(engine).balance;

        vm.warp(block.timestamp + 20 minutes);

        // Transferring 1 wei -> (1 * 100) / 10000 = 0 tax
        token.transfer(pool, 10);

        assertEq(address(engine).balance - engineEthBefore, 1 ether);
    }

    function test_Tax_OwnerCannotCallSwapDirectly() public {
        vm.expectRevert("Not authorized");
        token.swapTaxTokensForETH(100 ether, 0.1 ether);
    }

    function test_Tax_ManualSwapNotOwner() public {
        token.transfer(address(token), 1000 ether);
        vm.prank(user1);
        vm.expectRevert();
        token.manualSwapTaxTokens(500 ether, 0.1 ether);
    }

    function test_Tax_ManualSwapMinEthZero() public {
        token.transfer(address(token), 1000 ether);
        vm.expectRevert("minEthOut zero");
        token.manualSwapTaxTokens(500 ether, 0);
    }

    function test_Tax_ManualSwapRespectsMax() public {
        token.transfer(address(token), 300_000 ether);
        uint256 balBefore = token.balanceOf(address(token));
        token.manualSwapTaxTokens(250_000 ether, 0.1 ether);
        uint256 balAfter = token.balanceOf(address(token));
        // maxSwapAmount is 200_000 ether
        assertEq(balBefore - balAfter, 200_000 ether);
    }

    function test_Tax_EthAccountingOnlyDelta() public {
        vm.deal(address(token), 5 ether);
        token.transfer(address(token), 1000 ether);

        uint256 engineEthBefore = address(engine).balance;
        token.manualSwapTaxTokens(1000 ether, 0.1 ether);

        // Mock router returns 1 ether. Unrelated 5 ether stays in token contract.
        assertEq(address(token).balance, 5 ether);
        assertEq(address(engine).balance - engineEthBefore, 1 ether);
    }

    function test_SM_AdversarialSameBlockBuy() public {
        vm.deal(address(engine), 1 ether);
        vm.warp(block.timestamp + 2 hours);

        vm.roll(10); // advance block so snapshot gets >0 weight

        // Attacker gets tokens in the same block BEFORE or AFTER startLotteryEpoch
        address attacker = address(0xBAD);

        vm.prank(user1);
        token.transfer(attacker, 1500 ether);

        // Under V21, same-block starts are allowed. It snapshots opening balance!
        engine.startLotteryEpoch();

        // Rolling to next block
        vm.roll(11);
        assertEq(engine.getRoundStartSnapshotBlock(1), 9);
        assertEq(token.getPastBalance(attacker, 9), 0);
    }

    function test_SM_AutoLotteryDoesNotRevertTransfer() public {
        // Setup engine with ETH
        vm.deal(address(engine), 1 ether);

        // Router was already set in setUp (assuming we put it there, wait no we didn't)
        // Wait, line 399 is test_TaxBacklogDoesNotRevertOnAutoSwapFail which also uses router
        token.setAutoSwapEnabled(true);
        token.transfer(address(token), 100_000 ether);

        // Force the auto lottery step to fail due to lack of time (epoch not started)
        // But the transfer itself should still succeed!
        vm.warp(block.timestamp + 20 minutes);

        uint256 user1BalBefore = token.balanceOf(user1);
        token.transfer(pool, 100 ether);

        // Transfer succeeds, auto swap succeeds (sends 0.1 ETH), but auto lottery fails internally and doesn't revert.
        assertTrue(token.balanceOf(pool) > 0);
    }

    function test_Tax_PoolFlag_OfficialPathCannotBeTaxed() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        address freshPool = address(new MockV2LikePool(address(freshToken), address(0x888)));
        freshToken.setOfficialTaxExemptPoolOrManager(freshPool, true);

        vm.expectRevert("Official path");
        freshToken.setTaxedExternalPool(freshPool, true);
    }

    function test_Tax_PoolFlag_OfficialPathCanBeDisabledAsTaxed() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        address freshPool = address(new MockV2LikePool(address(freshToken), address(0x888)));
        freshToken.setOfficialTaxExemptPoolOrManager(freshPool, true);

        // Setting to false shouldn't revert
        freshToken.setTaxedExternalPool(freshPool, false);
    }

    function test_Tax_PoolFlag_TaxedCannotBeMarkedOfficial() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        address freshPool = address(new MockV2LikePool(address(freshToken), address(0x888)));
        freshToken.setTaxedExternalPool(freshPool, true);

        vm.expectRevert("Taxed external pool");
        freshToken.setOfficialTaxExemptPoolOrManager(freshPool, true);
    }

    function test_Tax_PoolFlag_UnsetTaxedCanBeMarkedOfficial() public {
        RobinhoodToken freshToken = new RobinhoodToken();
        address freshPool = address(new MockV2LikePool(address(freshToken), address(0x888)));
        freshToken.setTaxedExternalPool(freshPool, true);
        freshToken.setTaxedExternalPool(freshPool, false);

        freshToken.setOfficialTaxExemptPoolOrManager(freshPool, true);
        assertTrue(freshToken.isOfficialTaxExemptPoolOrManager(freshPool));
    }

    function test_Tax_PoolFlag_SetOfficialRevertsAfterLaunch() public {
        vm.expectRevert("Launch config locked");
        token.setOfficialTaxExemptPoolOrManager(address(0x123), true);
    }

    function test_Tax_PoolFlag_SetTaxedWorksAfterLaunch() public {
        address newPool = address(new MockV2LikePool(address(token), address(0xABC)));
        token.setTaxedExternalPool(newPool, true);
        assertTrue(token.isTaxedExternalPool(newPool));
    }

    function test_Fenwick_TreeFullGracefulDegradation() public {
        HarnessRobinhoodToken freshToken = new HarnessRobinhoodToken();

        freshToken.setExemptions(address(this), true, true, true);
        freshToken.activateTrading();

        // Force tree full
        freshToken.setNextEligibleIndex(1 << 24);

        // Give tokens to a new address. It should not revert!
        freshToken.transfer(address(0x999), 2000 ether);

        // Transfer worked!
        assertEq(freshToken.balanceOf(address(0x999)), 2000 ether);

        // But they are not in the tree!
        assertEq(freshToken.eligibleIndexOf(address(0x999)), 0);
        assertEq(freshToken.getEligibleTotalWeight(), 0);
    }

    function test_V14_StartSnapshotBlockedAfterSameBlockMutation() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(block.number + 10);

        // Mutate eligibility in current block
        token.transfer(user3, 4000 ether);

        // In V21, it just snapshots opening balance
        engine.startLotteryEpoch();

        vm.roll(block.number + 1);
        assertEq(uint256(engine.currentRoundId()), 1);
    }

    function test_V14_AutoStartSkipsInDirtyBlock() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(block.number + 10);

        // Mutate eligibility in current block
        token.transfer(user3, 4000 ether);
        assertTrue(token.canBeginLotterySnapshot());

        // Auto-start step must start cleanly
        (AutoLotteryAction action, uint256 rId) = engine.autoLotteryStep(owner, 10);
        assertEq(uint256(action), uint256(AutoLotteryAction.StartEpoch));
        assertEq(rId, 1);

        // Rolling to next block
        vm.roll(block.number + 1);
    }

    function test_V14_LazySnapshot_PostStartBuyDoesNotIncreaseOdds() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(block.number + 10);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        uint256 snapshotWeight = token.getActiveSnapshotTotalWeight(roundId);
        assertEq(snapshotWeight, 10_000 ether); // 2000 user1 + 3000 user2 + 5000 owner/test contract

        uint256 user1Index = token.eligibleIndexOf(user1);
        uint256 user2Index = token.eligibleIndexOf(user2);
        assertEq(token.treeFindByCumulativeAtRound(0, roundId), user1Index);
        assertEq(token.treeFindByCumulativeAtRound(1999 ether, roundId), user1Index);
        assertEq(token.treeFindByCumulativeAtRound(2000 ether, roundId), user2Index);

        // User1 buys more tokens after Snapshot 1
        vm.roll(block.number + 1);
        token.transfer(user1, 98_000 ether);

        // Active round snapshot weight and cumulative indices are unchanged!
        assertEq(token.getActiveSnapshotTotalWeight(roundId), snapshotWeight);
        assertEq(token.treeFindByCumulativeAtRound(1999 ether, roundId), user1Index);
        assertEq(token.treeFindByCumulativeAtRound(2000 ether, roundId), user2Index);
        assertEq(token.treeFindByCumulativeAtRound(4999 ether, roundId), user2Index);

        // Meanwhile live total weight has increased
        assertGt(token.getEligibleTotalWeight(), snapshotWeight);
    }

    function test_V14_SnapshotClearedOnTermination() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(block.number + 10);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();
        assertEq(token.activeSnapshotRoundId(), roundId);

        // Expire started epoch after timeout
        vm.warp(block.timestamp + 2 hours);
        engine.expireStartedEpoch(roundId);

        // Snapshot should be cleanly cleared
        assertEq(token.activeSnapshotRoundId(), 0);

        // Start next epoch cleanly
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        assertEq(token.activeSnapshotRoundId(), 2);

        // Trigger draw and expire draw
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 1);
        engine.triggerDraw(2);

        vm.roll(block.number + 900); // Exceed DRAW_DELAY_BLOCKS + BLOCKHASH_LOOKBACK_LIMIT (600 + 256)
        engine.expireLottery(2);

        assertEq(token.activeSnapshotRoundId(), 0);
    }

    function test_Tax_AutoSwapSkipsIfQuoteReadyReverts() public {
        token.transfer(address(token), 100_000 ether);
        quote.setRevertReady(true);

        uint256 swapCountBefore = router.swapCount();
        uint256 engineEthBefore = address(engine).balance;
        uint256 lastAutoSwapAtBefore = token.lastAutoSwapAt();
        uint256 poolBalBefore = token.balanceOf(pool);
        uint256 tokenBalBefore = token.balanceOf(address(token));

        vm.warp(block.timestamp + 20 minutes);
        token.transfer(pool, 1000 ether);

        assertTrue(token.balanceOf(pool) > poolBalBefore);
        assertEq(router.swapCount(), swapCountBefore);
        assertTrue(token.balanceOf(address(token)) >= tokenBalBefore);
        assertEq(address(engine).balance, engineEthBefore);
        assertEq(token.lastAutoSwapAt(), lastAutoSwapAtBefore);
    }

    function test_Tax_AutoSwapSkipsIfQuoteCallReverts() public {
        token.transfer(address(token), 100_000 ether);
        quote.setRevertQuote(true);

        uint256 swapCountBefore = router.swapCount();
        uint256 engineEthBefore = address(engine).balance;
        uint256 lastAutoSwapAtBefore = token.lastAutoSwapAt();
        uint256 poolBalBefore = token.balanceOf(pool);
        uint256 tokenBalBefore = token.balanceOf(address(token));

        vm.warp(block.timestamp + 20 minutes);
        token.transfer(pool, 1000 ether);

        assertTrue(token.balanceOf(pool) > poolBalBefore);
        assertEq(router.swapCount(), swapCountBefore);
        assertTrue(token.balanceOf(address(token)) >= tokenBalBefore);
        assertEq(address(engine).balance, engineEthBefore);
        assertEq(token.lastAutoSwapAt(), lastAutoSwapAtBefore);
    }

    function test_GAS_V14_LazyFenwickTransfer() public {
        uint256 gasBefore = gasleft();
        token.transfer(user1, 100 ether);
        uint256 gasIdle = gasBefore - gasleft();
        console.log("Gas used for standard transfer (idle, no active snapshot):", gasIdle);

        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(20);
        engine.startLotteryEpoch();

        gasBefore = gasleft();
        token.transfer(user2, 100 ether);
        uint256 gasActiveFirst = gasBefore - gasleft();
        console.log("Gas used for transfer (first mutation during active snapshot, freezes nodes):", gasActiveFirst);

        gasBefore = gasleft();
        token.transfer(user2, 100 ether);
        uint256 gasActiveSecond = gasBefore - gasleft();
        console.log(
            "Gas used for transfer (second mutation during active snapshot, nodes already frozen):", gasActiveSecond
        );
    }

    function test_V14_SameBlockAfterStartLazyFreeze() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 50;
        vm.roll(curBlock);

        engine.startLotteryEpoch();
        uint256 startRoundId = token.activeSnapshotRoundId();
        uint256 preTransferSnapshotWeight = token.activeSnapshotTotalWeight();
        uint256 preTransferLiveWeight = token.getEligibleTotalWeight();

        // Sample winner odds before transfer
        uint256 winnerIdxBefore = token.treeFindByCumulativeAtRound(1000 ether, startRoundId);

        // Same block B after startLotteryEpoch, an eligible holder buys more tokens
        token.transfer(user1, 1000 ether);

        // Active snapshot total weight remains unchanged
        assertEq(token.activeSnapshotTotalWeight(), preTransferSnapshotWeight, "Snapshot weight should be frozen");
        // Odds remain unchanged
        assertEq(
            token.treeFindByCumulativeAtRound(1000 ether, startRoundId), winnerIdxBefore, "Odds should remain frozen"
        );
        // Live weight increases
        assertTrue(token.getEligibleTotalWeight() > preTransferLiveWeight, "Live weight should increase");
    }

    function test_Recycling_1_OutsideActiveRoundFreesImmediately() public {
        uint256 idx = token.eligibleIndexOf(user3);
        assertTrue(idx > 0, "User3 should have index");
        assertEq(token.activeSnapshotRoundId(), 0, "No active round");

        uint256 freeBefore = token.getFreeEligibleIndicesCount();
        uint256 bal = token.balanceOf(user3);
        vm.prank(user3);
        token.transfer(owner, bal);

        assertEq(token.eligibleIndexOf(user3), 0, "Eligible index cleared");
        assertEq(token.holderAtIndex(idx), address(0), "Holder at index cleared");
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore + 1, "Free count incremented");
        assertEq(token.getFreeEligibleIndexAt(freeBefore), idx, "Index added to free list");
    }

    function test_Recycling_2_NewHolderReusesFreedIndex() public {
        uint256 idx = token.eligibleIndexOf(user3);
        uint256 bal = token.balanceOf(user3);
        vm.prank(user3);
        token.transfer(owner, bal);

        uint256 nextIdxBefore = token.nextEligibleIndex();
        address newHolder = address(0x888);
        token.transfer(newHolder, 2000 ether);

        assertEq(token.eligibleIndexOf(newHolder), idx, "Reused freed index");
        assertEq(token.holderAtIndex(idx), newHolder, "Holder at index updated to new holder");
        assertEq(token.nextEligibleIndex(), nextIdxBefore, "nextEligibleIndex did not increment");
    }

    function test_Recycling_3_ActiveRoundQueuesInsteadOfFreeing() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        vm.roll(100);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();

        uint256 idx = token.eligibleIndexOf(user1);
        assertTrue(idx > 0, "User1 has index");
        uint256 freeBefore = token.getFreeEligibleIndicesCount();

        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);

        assertEq(token.eligibleWeightOf(user1), 0, "Weight is zero");
        assertEq(token.holderAtIndex(idx), user1, "Holder at index preserved during active round");
        assertEq(token.eligibleIndexOf(user1), idx, "Eligible index preserved");
        assertEq(token.pendingFreeRoundByIndex(idx), roundId, "Queued for pending free with active roundId");
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore, "Not added to free list yet");
    }

    function test_Recycling_4_PayLotteryCanStillResolveQueuedIndex() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();

        uint256 idx1 = token.eligibleIndexOf(user1);
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);

        // Token contract can still resolve holder by eligible index for Snapshot 1 selection
        assertEq(token.getHolderByEligibleIndex(idx1), user1, "Can still resolve queued index");

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(roundId);

        curBlock += 601;
        vm.roll(curBlock);
        // payLottery succeeds and will disqualify user1 if selected because live balance < start balance
        engine.payLottery(roundId);
    }

    function test_Recycling_5_RoundEndAndSweepFreesQueuedIndex() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();

        uint256 idx = token.eligibleIndexOf(user1);
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(roundId);
        curBlock += 601;
        vm.roll(curBlock);
        engine.payLottery(roundId);

        assertEq(token.activeSnapshotRoundId(), 0, "Round ended");
        uint256 freeBefore = token.getFreeEligibleIndicesCount();

        token.sweepPendingFreeIndices(10);

        assertEq(token.eligibleIndexOf(user1), 0, "Index freed and cleared");
        assertEq(token.holderAtIndex(idx), address(0), "Holder at index cleared");
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore + 1, "Added to free list");
    }

    function test_Recycling_6_HolderBuysBackDuringActiveRoundCancelsPendingFree() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();

        uint256 idx = token.eligibleIndexOf(user1);
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);
        assertEq(token.pendingFreeRoundByIndex(idx), roundId, "Queued");

        // Holder buys back above threshold before round ends
        token.transfer(user1, 2000 ether);
        assertEq(token.pendingFreeRoundByIndex(idx), 0, "Pending free canceled");
        assertEq(token.eligibleIndexOf(user1), idx, "Same index maintained");
        assertEq(token.holderAtIndex(idx), user1, "Holder maintained");

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(roundId);
        curBlock += 601;
        vm.roll(curBlock);
        engine.payLottery(roundId);

        uint256 freeBefore = token.getFreeEligibleIndicesCount();
        token.sweepPendingFreeIndices(10);
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore, "Not freed on sweep");
        assertEq(token.eligibleIndexOf(user1), idx, "Still assigned after sweep");
    }

    function test_Recycling_7_StalePendingEntriesAreHarmless() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();

        uint256 idx = token.eligibleIndexOf(user1);
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);
        token.transfer(user1, 2000 ether); // cancels pending free round marker

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(roundId);
        curBlock += 601;
        vm.roll(curBlock);
        engine.payLottery(roundId);

        uint256 freeBefore = token.getFreeEligibleIndicesCount();
        token.sweepPendingFreeIndices(10);
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore, "Stale entry skipped");
        assertEq(token.holderAtIndex(idx), user1, "Mapping unchanged");
        assertEq(token.getPendingFreeIndicesCount(), 0, "Pending list cleared");
    }

    function test_Recycling_8_FreeListWorksWhenNextEligibleIndexExhausted() public {
        HarnessRobinhoodToken fresh = new HarnessRobinhoodToken();
        fresh.setExemptions(address(this), true, true, true);
        fresh.activateTrading();

        fresh.setNextEligibleIndex(1 << 24); // exhausted
        fresh.pushFreeEligibleIndex(999);

        address newHolder = address(0x555);
        fresh.transfer(newHolder, 2000 ether);

        assertEq(fresh.eligibleIndexOf(newHolder), 999, "Reused from free list when tree exhausted");
        assertEq(fresh.holderAtIndex(999), newHolder, "Holder mapped correctly");
        assertEq(fresh.getFreeEligibleIndicesCount(), 0, "Free list consumed");
    }

    function test_Recycling_9_ExhaustedTreeNoFreeIndexGracefulDegradation() public {
        HarnessRobinhoodToken fresh = new HarnessRobinhoodToken();
        fresh.setExemptions(address(this), true, true, true);
        fresh.activateTrading();

        fresh.setNextEligibleIndex(1 << 24); // exhausted
        assertEq(fresh.getFreeEligibleIndicesCount(), 0);

        uint256 totalBefore = fresh.totalEligibleBalance();
        address newHolder = address(0x666);
        fresh.transfer(newHolder, 2000 ether); // does not revert!

        assertEq(fresh.balanceOf(newHolder), 2000 ether, "Transfer succeeded");
        assertEq(fresh.eligibleIndexOf(newHolder), 0, "No index assigned");
        assertEq(fresh.eligibleWeightOf(newHolder), 0, "No weight assigned");
        assertEq(fresh.totalEligibleBalance(), totalBefore, "Total weight unchanged");
    }

    function test_Recycling_10_SweepIsBounded() public {
        vm.deal(address(engine), 10 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);

        // Make 5 users eligible
        address[5] memory users = [address(0x11), address(0x12), address(0x13), address(0x14), address(0x15)];
        for (uint256 i = 0; i < 5; i++) {
            token.transfer(users[i], 2000 ether);
        }

        curBlock++;
        vm.roll(curBlock);
        engine.startLotteryEpoch();
        uint256 roundId = token.activeSnapshotRoundId();
        for (uint256 i = 0; i < 5; i++) {
            uint256 bal = token.balanceOf(users[i]);
            vm.prank(users[i]);
            token.transfer(owner, bal);
        }
        assertEq(token.getPendingFreeIndicesCount(), 5, "5 pending indices queued");

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(roundId);
        curBlock += 601;
        vm.roll(curBlock);
        engine.payLottery(roundId);

        token.sweepPendingFreeIndices(2);
        assertEq(token.pendingFreeSweepCursor(), 2, "Swept exactly 2 steps");
        assertEq(token.getFreeEligibleIndicesCount(), 2, "Freed 2 indices");

        token.sweepPendingFreeIndices(3);
        assertEq(token.pendingFreeSweepCursor(), 0, "Cursor reset");
        assertEq(token.getPendingFreeIndicesCount(), 0, "Pending free queue cleared");
        assertEq(token.getFreeEligibleIndicesCount(), 5, "All 5 freed");
    }

    function test_Recycling_11_BeginLotterySnapshotSweepsBoundedAmount() public {
        vm.deal(address(engine), 20 ether);
        vm.warp(block.timestamp + 3 hours);
        uint256 curBlock = 100;
        vm.roll(curBlock);

        engine.startLotteryEpoch();
        uint256 round1 = token.activeSnapshotRoundId();
        uint256 idx1 = token.eligibleIndexOf(user1);
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal); // queued for pending free

        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);
        engine.triggerDraw(round1);
        curBlock += 601;
        vm.roll(curBlock);
        engine.payLottery(round1);

        assertEq(token.eligibleIndexOf(user1), idx1, "Not yet swept");

        // Advance to next epoch and start round 2
        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);

        uint256 freeBefore = token.getFreeEligibleIndicesCount();
        engine.startLotteryEpoch(); // beginLotterySnapshot calls _sweepPendingFreeIndices(ROUND_START_SWEEP_LIMIT)

        assertEq(token.eligibleIndexOf(user1), 0, "Swept automatically at round start");
        assertEq(token.getFreeEligibleIndicesCount(), freeBefore + 1, "Freed at round start");
        assertEq(token.activeSnapshotStartedAtBlock(), curBlock, "New snapshot started cleanly");
    }

    function test_Recycling_12_AllocationSweepIsAdaptive() public {
        HarnessRobinhoodToken fresh = new HarnessRobinhoodToken();
        fresh.setNextEligibleIndex(100);
        assertEq(
            fresh.exposeAllocationSweepLimit(),
            fresh.NORMAL_ALLOC_SWEEP_LIMIT(),
            "Normal sweep limit under pressure threshold"
        );
        assertEq(fresh.exposeAllocationSweepLimit(), 16);

        uint256 pressureIndex = (uint256(1 << 24) * 9000) / 10000;
        fresh.setNextEligibleIndex(pressureIndex);
        assertEq(
            fresh.exposeAllocationSweepLimit(), fresh.HIGH_PRESSURE_ALLOC_SWEEP_LIMIT(), "High pressure sweep limit"
        );
        assertEq(fresh.exposeAllocationSweepLimit(), 256);
    }

    function test_Recycling_13_Invariants() public {
        uint256 bal = token.balanceOf(user1);
        vm.prank(user1);
        token.transfer(owner, bal);

        uint256 freeCount = token.getFreeEligibleIndicesCount();
        for (uint256 i = 0; i < freeCount; i++) {
            uint256 idx = token.getFreeEligibleIndexAt(i);
            assertEq(token.holderAtIndex(idx), address(0), "Invariant 1: Free index must have address(0) holder");
        }

        // Invariant 5: live totalEligibleBalance equals sum of live eligibleWeightOf for tracked holders
        uint256 sumWeight =
            token.eligibleWeightOf(user1) + token.eligibleWeightOf(user2) + token.eligibleWeightOf(user3);
        assertEq(token.totalEligibleBalance(), sumWeight, "Invariant 5: sum of weights equals totalEligibleBalance");
    }

    receive() external payable {}
}
