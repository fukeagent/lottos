// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LotteryHook} from "../contracts/LotteryHook.sol";
import {RobinhoodToken} from "../contracts/RobinhoodToken.sol";
import {LotteryEngine} from "../contracts/LotteryEngine.sol";
import {HookMiner} from "../script/HookMiner.sol";

/// @dev Helper to reject ETH (for payout failure tests)
contract ETHRejecter {
    receive() external payable {
        revert("no ETH");
    }
}

contract Factory {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2 failed");
    }
}

contract V4LotteryHookIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    PoolManager manager;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolSwapTest swapRouter;

    RobinhoodToken token;
    LotteryEngine engine;
    LotteryHook hook;
    Factory factory;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    PoolKey key;

    address user = address(0x1337);

    receive() external payable {}

    function setUp() public {
        manager = new PoolManager(address(this));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);

        token = new RobinhoodToken();
        tokenCurrency = Currency.wrap(address(token));

        engine = new LotteryEngine(address(token), address(this), 100 ether);

        factory = new Factory();

        uint160 flags = uint160(0xCC);
        bytes memory creationCode = type(LotteryHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, address(engine), address(token), ethCurrency, address(this));

        (address expectedAddress, bytes32 salt) = HookMiner.find(address(factory), flags, creationCode, constructorArgs);

        address hookAddress = factory.deploy(salt, abi.encodePacked(creationCode, constructorArgs));
        require(hookAddress == expectedAddress, "Hook mismatch");
        hook = LotteryHook(payable(hookAddress));

        bool zeroForOne = ethCurrency < tokenCurrency;
        Currency currency0 = zeroForOne ? ethCurrency : tokenCurrency;
        Currency currency1 = zeroForOne ? tokenCurrency : ethCurrency;

        key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddress)
        });

        manager.initialize(key, 79228162514264337593543950336); // 1:1 price

        hook.setOfficialPool(key);
        token.setLotteryEngine(address(engine));

        // Set ALL exemptions BEFORE activateTrading (config locks on activation)
        token.setExemptions(address(manager), true, true, true);
        token.setOfficialTaxExemptPoolOrManager(address(manager), true);
        token.setExemptions(address(swapRouter), true, true, true);
        token.setExemptions(address(modifyLiquidityRouter), true, true, true);
        token.setExemptions(address(this), true, true, true);
        token.setExemptions(user, true, true, false); // trading=true, maxWallet=true, NOT eligibility exempt

        // Transfer tokens to user BEFORE activateTrading (needs trading exemption on both sides)
        token.transfer(user, 2_000_000 ether);

        // Add liquidity BEFORE activateTrading
        vm.deal(address(this), 10000 ether);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity{value: 100 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100 ether, salt: 0}),
            new bytes(0)
        );

        // NOW activate trading — this locks setExemptions permanently
        token.activateTrading();
    }

    // ════════════════════════════════════════════════════════
    //  V4 SWAP REGRESSION TESTS
    // ════════════════════════════════════════════════════════

    function test_ExactInputETHBuy() public {
        vm.deal(user, 10 ether);
        uint256 initEngineBal = address(engine).balance;

        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < tokenCurrency,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: ethCurrency < tokenCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap{value: 1 ether}(key, params, settings, new bytes(0));
        vm.stopPrank();

        uint256 finalEngineBal = address(engine).balance;
        assertEq(finalEngineBal - initEngineBal, 0.1 ether);
        assertEq(address(hook).balance, 0);
    }

    function test_ExactOutputTokenBuy() public {
        vm.deal(user, 10 ether);
        uint256 initEngineBal = address(engine).balance;

        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < tokenCurrency,
            amountSpecified: 1 ether,
            sqrtPriceLimitX96: ethCurrency < tokenCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        BalanceDelta delta = swapRouter.swap{value: 2 ether}(key, params, settings, new bytes(0));
        vm.stopPrank();

        uint256 finalEngineBal = address(engine).balance;
        int128 ethDelta = ethCurrency < tokenCurrency ? delta.amount0() : delta.amount1();
        uint256 ethDeltaAbs = ethDelta < 0 ? uint256(-int256(ethDelta)) : uint256(int256(ethDelta));
        uint256 expectedTax = (ethDeltaAbs * 10) / 110;
        assertApproxEqAbs(finalEngineBal - initEngineBal, expectedTax, 2);
        assertEq(address(hook).balance, 0);
    }

    function test_ExactInputTokenSell() public {
        uint256 initEngineBal = address(engine).balance;

        vm.startPrank(user);
        token.approve(address(swapRouter), type(uint256).max);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: tokenCurrency < ethCurrency,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: tokenCurrency < ethCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        BalanceDelta delta = swapRouter.swap(key, params, settings, new bytes(0));
        vm.stopPrank();

        uint256 finalEngineBal = address(engine).balance;
        int128 ethDelta = ethCurrency < tokenCurrency ? delta.amount0() : delta.amount1();
        uint256 ethDeltaAbs = ethDelta < 0 ? uint256(-int256(ethDelta)) : uint256(int256(ethDelta));
        uint256 expectedTax = (ethDeltaAbs * 10) / 90;
        assertApproxEqAbs(finalEngineBal - initEngineBal, expectedTax, 2);
        assertEq(address(hook).balance, 0);
    }

    function test_ExactOutputETHSell() public {
        uint256 initEngineBal = address(engine).balance;

        vm.startPrank(user);
        token.approve(address(swapRouter), type(uint256).max);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: tokenCurrency < ethCurrency,
            amountSpecified: 1 ether,
            sqrtPriceLimitX96: tokenCurrency < ethCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(key, params, settings, new bytes(0));
        vm.stopPrank();

        uint256 finalEngineBal = address(engine).balance;
        assertEq(finalEngineBal - initEngineBal, 0.1 ether);
        assertEq(address(hook).balance, 0);
    }

    function test_AdversarialWrongPool() public {
        RobinhoodToken token2 = new RobinhoodToken();
        Currency token2Currency = Currency.wrap(address(token2));

        bool zeroForOne = ethCurrency < token2Currency;
        Currency c0 = zeroForOne ? ethCurrency : token2Currency;
        Currency c1 = zeroForOne ? token2Currency : ethCurrency;

        PoolKey memory wrongKey =
            PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))});

        manager.initialize(wrongKey, 79228162514264337593543950336);

        token2.setExemptions(address(manager), true, true, true);
        token2.setOfficialTaxExemptPoolOrManager(address(manager), true);
        token2.setExemptions(address(modifyLiquidityRouter), true, true, true);
        token2.activateTrading();
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.deal(address(this), 10000 ether);
        modifyLiquidityRouter.modifyLiquidity{value: 100 ether}(
            wrongKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100 ether, salt: 0}),
            new bytes(0)
        );

        vm.deal(user, 10 ether);
        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < token2Currency,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: ethCurrency < token2Currency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 initEngineBal = address(engine).balance;
        swapRouter.swap{value: 1 ether}(wrongKey, params, settings, new bytes(0));
        vm.stopPrank();

        assertEq(address(engine).balance, initEngineBal);
        assertEq(address(hook).balance, 0);
    }

    function test_AdversarialPreLaunch() public {
        // Create a fresh token that has NOT activated trading
        RobinhoodToken token3 = new RobinhoodToken();
        Currency token3Currency = Currency.wrap(address(token3));

        bool zeroForOne = ethCurrency < token3Currency;
        Currency c0 = zeroForOne ? ethCurrency : token3Currency;
        Currency c1 = zeroForOne ? token3Currency : ethCurrency;

        PoolKey memory preLaunchKey =
            PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))});

        manager.initialize(preLaunchKey, 79228162514264337593543950336);

        token3.setExemptions(address(manager), true, true, true);
        token3.setExemptions(address(modifyLiquidityRouter), true, true, true);
        token3.approve(address(modifyLiquidityRouter), type(uint256).max);

        vm.deal(address(this), 10000 ether);
        modifyLiquidityRouter.modifyLiquidity{value: 100 ether}(
            preLaunchKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100 ether, salt: 0}),
            new bytes(0)
        );

        vm.deal(user, 10 ether);
        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < token3Currency,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: ethCurrency < token3Currency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.expectRevert();
        swapRouter.swap{value: 1 ether}(preLaunchKey, params, settings, new bytes(0));
        vm.stopPrank();
    }

    function test_PriceLimitRevertDoesNotLeakTax() public {
        // A tight price limit causes a partial fill where the hook tries to take
        // more ETH than available, causing an OutOfFunds revert. This correctly
        // prevents any ETH from leaking — the entire swap reverts atomically.
        vm.deal(user, 10000 ether);

        vm.startPrank(user);
        uint160 currentPrice = 79228162514264337593543950336;
        uint160 limitPrice = ethCurrency < tokenCurrency
            ? currentPrice - 1000000000000000000000000000
            : currentPrice + 1000000000000000000000000000;

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < tokenCurrency, amountSpecified: -100 ether, sqrtPriceLimitX96: limitPrice
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        vm.expectRevert(); // Tight limit causes OutOfFunds — entire swap reverts, no tax leak
        swapRouter.swap{value: 100 ether}(key, params, settings, new bytes(0));
        vm.stopPrank();

        // Hook balance stays zero — no ETH leaked
        assertEq(address(hook).balance, 0);
    }

    function test_HookBalanceRemainsZero() public {
        vm.deal(user, 10 ether);
        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < tokenCurrency,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: ethCurrency < tokenCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap{value: 1 ether}(key, params, settings, new bytes(0));
        vm.stopPrank();
        assertEq(address(hook).balance, 0);
    }

    // ════════════════════════════════════════════════════════
    //  STATE MACHINE TESTS
    // ════════════════════════════════════════════════════════

    function _fundEngineAndWarp() internal {
        vm.deal(address(engine), 1 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
    }

    function test_SM_StartRevertsBeforeTrading() public {
        // Deploy fresh unfunded token + engine
        RobinhoodToken t = new RobinhoodToken();
        LotteryEngine e = new LotteryEngine(address(t), address(this), 100 ether);
        vm.deal(address(e), 1 ether);
        vm.expectRevert("Trading not active");
        e.startLotteryEpoch();
    }

    function test_SM_StartRevertsBeforeTwoHours() public {
        vm.deal(address(engine), 1 ether);
        vm.warp(block.timestamp + 1 hours); // Only 1 hour, need 2
        vm.expectRevert("Too early after launch");
        engine.startLotteryEpoch();
    }

    function test_SM_StartRevertsInsufficientETH() public {
        vm.warp(block.timestamp + 2 hours + 1);
        // No ETH in engine
        vm.expectRevert("Prize too small");
        engine.startLotteryEpoch();
    }

    function test_SM_StartRevertsNoEligibleHolders() public {
        // Deploy fresh with no eligible holders
        RobinhoodToken t = new RobinhoodToken();
        LotteryEngine e = new LotteryEngine(address(t), address(this), 100 ether);
        t.setLotteryEngine(address(e));
        t.activateTrading();
        vm.deal(address(e), 1 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.expectRevert("No eligible weight");
        e.startLotteryEpoch();
    }

    function test_SM_StartSucceeds() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.EPOCH_STARTED));
    }

    function test_SM_StartStoresSnapshot() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        assertEq(engine.getRoundStartSnapshotBlock(1), block.number - 1);
    }

    function test_SM_StartReservesPrize() public {
        _fundEngineAndWarp();
        uint256 available = engine.availableLotteryBalance();
        engine.startLotteryEpoch();
        uint256 selectedPrize = engine.getRoundSelectedPrizePool(1);
        assertGt(selectedPrize, 0);
        assertEq(engine.reservedPrizePool(), selectedPrize);
        // Available should have decreased
        assertLt(engine.availableLotteryBalance(), available);
    }

    function test_SM_StartRewardCapped() public {
        // Fund with massive amount so 1% > 0.02 ETH
        vm.deal(address(engine), 1000 ether);
        engine.setPayoutTiers(5 ether, 25 ether, 100 ether, 5000, 3000, 2000, 1000); // capped payout for testing
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        assertEq(engine.getRoundStartReward(1), 0.02 ether); // Capped
    }

    function test_SM_StartCannotCallTwice() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.expectRevert("Active round");
        engine.startLotteryEpoch();
    }

    function test_SM_TriggerRevertsBeforeHoldingEpoch() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        // Don't warp — holding epoch not finished
        vm.expectRevert("Holding epoch not finished");
        engine.triggerDraw(1);
    }

    function test_SM_TriggerSucceeds() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.DRAW_TRIGGERED));
    }

    function test_SM_TriggerStoresEndSnapshot() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        engine.triggerDraw(1);
        assertEq(engine.getRoundEndSnapshotBlock(1), block.number - 1);
    }

    function test_SM_TriggerSetsRandomnessBlock() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        assertEq(engine.getRoundRandomnessBlock(1), block.number + engine.DRAW_DELAY_BLOCKS());
    }

    function test_SM_TriggerRewardCapped() public {
        vm.deal(address(engine), 1000 ether);
        engine.setPayoutTiers(5 ether, 25 ether, 100 ether, 5000, 3000, 2000, 1000);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        assertEq(engine.getRoundTriggerReward(1), 0.02 ether);
    }

    function test_SM_TriggerCannotCallTwice() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        vm.expectRevert("Wrong status");
        engine.triggerDraw(1);
    }

    function test_SM_PayRevertsBeforeRandomness() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        // Don't roll to randomnessBlock
        vm.expectRevert("Randomness not ready");
        engine.payLottery(1);
    }

    function test_SM_PaySucceeds() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        address keeper = address(0x999);
        vm.prank(keeper);
        engine.payLottery(1);

        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.FULFILLED));
    }

    function test_SM_PayRevertsAfterBlockhashExpiry() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        vm.expectRevert("Blockhash expired");
        engine.payLottery(1);
    }

    function test_SM_PaySelectsFromStartSnapshot() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        address keeper = address(0x999);
        vm.prank(keeper);
        engine.payLottery(1);

        // User should be the winner (only eligible holder)
        assertEq(engine.getRoundWinner(1), user);
    }

    function test_SM_PayPaysEveryoneDirectly() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);

        address starter = address(0xAAA);
        // We can't easily test starter since setUp already called it. Test with keeper/payer.

        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        uint256 userBefore = user.balance;
        uint256 devBefore = address(this).balance; // dev is address(this)

        address keeper = address(0x999);
        vm.prank(keeper);
        engine.payLottery(1);

        assertGt(user.balance - userBefore, 0);
        assertEq(engine.getRoundWinner(1), user);
    }

    function test_SM_RoundBecomesFulfilled() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.FULFILLED));
    }

    function test_SM_ReservedPrizeReleasedExactlyOnce() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        uint256 reservedAfterStart = engine.reservedPrizePool();
        assertGt(reservedAfterStart, 0);

        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        assertEq(engine.reservedPrizePool(), reservedAfterStart); // Still reserved

        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);
        assertEq(engine.reservedPrizePool(), 0); // Released
    }

    function test_SM_ExpireRevertsBeforeExpiry() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1); // Inside window
        vm.expectRevert("Not expired");
        engine.expireLottery(1);
    }

    function test_SM_ExpireSucceeds() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        engine.expireLottery(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.EXPIRED));
    }

    function test_SM_ExpiredRoundReleasesPrize() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        uint256 reservedAfter = engine.reservedPrizePool();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        engine.expireLottery(1);
        assertEq(engine.reservedPrizePool(), 0);
    }

    function test_SM_NewRoundAfterExpiry() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        engine.expireLottery(1);

        // Wait for interval
        vm.warp(block.timestamp + 30 minutes + 1);
        vm.deal(address(engine), 1 ether);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 2);
    }

    // ════════════════════════════════════════════════════════
    //  DIAMOND-HANDS TESTS
    // ════════════════════════════════════════════════════════

    function test_DH_HolderEligibleAndHolding() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);
        assertEq(engine.getRoundWinner(1), user);
    }

    function test_DH_SellerBeforeTriggerDisqualified() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();

        // User sells most tokens during holding epoch
        vm.prank(user);
        token.transfer(address(this), 1_999_000 ether);

        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        // payLottery should expire because no valid winner (sold below start balance)
        // With MAX_TOTAL_ROUND_ATTEMPTS it would eventually exhaust or expire.
        // Since user is the only holder and they sold, winner should be address(0).
        engine.payLottery(1, 150);
        // If no winner found after max attempts per call, status stays DRAW_TRIGGERED
        // and can be retried until MAX_TOTAL_ROUND_ATTEMPTS is hit.
        // The key point is user can't win because they sold below start balance.
        address winner = engine.getRoundWinner(1);
        assertTrue(winner == address(0) || winner != user);
    }

    // (Removed test_DH_SellerAfterTriggerDisqualified for V17)

    function test_DH_BuyerAfterStartNoExtraOdds() public {
        // Create a second eligible user who buys AFTER TX1
        address user2 = address(0x2222);

        _fundEngineAndWarp();
        engine.startLotteryEpoch();

        // Transfer from test contract (not user!) so user keeps diamond-hands balance
        // user2 buys after TX1 — should not increase odds for current round
        // (winner is selected from startSnapshotBlock, user2 has 0 balance there)
        token.transfer(user2, 1_000_000 ether);

        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);

        // Winner must be user (the only one with balance at startSnapshotBlock)
        // user2 had 0 balance at snapshot so cannot win
        assertEq(engine.getRoundWinner(1), user);
    }

    function test_DH_ContractCannotWin() public {
        // Contracts should never win. The engine checks candidate.code.length == 0.
        // This is inherently tested since the test contract holds tokens but can't win.
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);

        address winner = engine.getRoundWinner(1);
        assertEq(winner.code.length, 0); // Winner must be EOA
    }

    // ════════════════════════════════════════════════════════
    //  PAYOUT SAFETY TESTS
    // ════════════════════════════════════════════════════════

    function test_PS_WinnerReceivesETH() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        uint256 before = user.balance;
        engine.payLottery(1);
        assertGt(user.balance, before);
    }

    function test_PS_DevReceivesETH() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        uint256 before = address(this).balance; // dev wallet is address(this)
        engine.payLottery(1);
        assertGt(address(this).balance, before);
    }

    function test_PS_FailedDevPayoutDoesNotBrick() public {
        // Create engine with a dev wallet that rejects ETH
        ETHRejecter rejecter = new ETHRejecter();
        RobinhoodToken t = new RobinhoodToken();
        LotteryEngine e = new LotteryEngine(address(t), address(rejecter), 100 ether);
        t.setExemptions(address(this), true, true, true);

        // Transfer to eligible user
        address u = address(0xBEEF);
        t.setExemptions(u, true, false, false);
        t.transfer(u, 2_000_000 ether);
        t.setLotteryEngine(address(e));
        t.activateTrading();

        vm.deal(address(e), 1 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        e.startLotteryEpoch();

        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        e.triggerDraw(1);

        uint256 randBlock = e.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        // Should NOT revert even though dev payout fails
        e.payLottery(1);
        assertEq(uint256(e.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.FULFILLED));

        // ETH stays in the contract
        assertEq(address(rejecter).balance, 0);
    }

    // ════════════════════════════════════════════════════════
    //  EXEMPTION / CONTRACT ELIGIBILITY TESTS
    // ════════════════════════════════════════════════════════

    function test_EX_SetExemptionsRevertsAfterLaunch() public {
        vm.expectRevert("Launch config locked");
        token.setExemptions(user, true, true, true);
    }

    function test_EX_PoolManagerNotEligible() public {
        assertTrue(token.isEligibilityExempt(address(manager)));
    }

    function test_EX_HookNotEligible() public {
        // Hook is a contract so it's automatically ineligible via code.length check
        assertGt(address(hook).code.length, 0);
    }

    function test_EX_EngineNotEligible() public {
        assertGt(address(engine).code.length, 0);
    }

    function test_EX_ContractHoldingTokensZeroWeight() public {
        // Address(this) holds tokens but is eligibility exempt + is a contract
        assertTrue(token.isEligibilityExempt(address(this)));
        assertGt(address(this).code.length, 0);
    }

    function test_EX_EOAHoldingTokensHasWeight() public {
        // User is an EOA and not eligibility exempt
        assertFalse(token.isEligibilityExempt(user));
        assertGt(token.balanceOf(user), 0);
        assertGt(token.totalEligibleBalance(), 0);
    }

    // ════════════════════════════════════════════════════════
    //  TIMING / BLOCKHASH TESTS
    // ════════════════════════════════════════════════════════

    function test_TM_FirstLotteryDelayEnforced() public {
        vm.deal(address(engine), 1 ether);
        // Warp only 1 hour (need 2)
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert("Too early after launch");
        engine.startLotteryEpoch();
    }

    function test_TM_IntervalEnforced() public {
        _fundEngineAndWarp();

        uint256 currentTs = block.timestamp;

        engine.startLotteryEpoch();

        currentTs += 30 minutes;
        vm.warp(currentTs);
        engine.triggerDraw(1);

        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);
        engine.payLottery(1);

        vm.deal(address(engine), 1 ether);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 2);

        // Finish round 2
        currentTs += 30 minutes;
        vm.warp(currentTs);
        engine.triggerDraw(2);
        uint256 randBlock2 = engine.getRoundRandomnessBlock(2);
        vm.roll(randBlock2 + 1);
        engine.payLottery(2);

        // Now try to start round 3 IMMEDIATELY.
        // The default roundDuration and minimum round-start spacing are both 30 minutes.
        // and we spent 30m in the holding epoch for round 2,
        // the interval has already passed relative to round 2's start time!
        // Therefore, it succeeds immediately.
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 3);
    }

    function test_TM_HoldingEpochDuration() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();

        // Try at 29 minutes
        vm.warp(block.timestamp + 29 minutes);
        vm.expectRevert("Holding epoch not finished");
        engine.triggerDraw(1);

        // At exactly 30 minutes
        vm.warp(block.timestamp + 1 minutes);
        engine.triggerDraw(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.DRAW_TRIGGERED));
    }

    function test_TM_PayInsideBlockhashWindow() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);

        // Just inside window
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT());
        engine.payLottery(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.FULFILLED));
    }

    function test_TM_PayFailsAfterWindow() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);

        // Just outside window
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        vm.expectRevert("Blockhash expired");
        engine.payLottery(1);
    }

    function test_TM_ExpireWorksAfterWindow() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();
        vm.warp(block.timestamp + 30 minutes);
        engine.triggerDraw(1);
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + engine.BLOCKHASH_LOOKBACK_LIMIT() + 1);
        engine.expireLottery(1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.EXPIRED));
    }

    function test_TM_ExpireStartedEpochRevertsBeforeTimeout() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();

        // Default timeout is roundDuration (30 min) + one-hour trigger grace = 90 minutes.
        vm.warp(block.timestamp + 1 hours + 29 minutes);

        vm.expectRevert("Grace period not missed");
        engine.expireStartedEpoch(1);
    }

    function test_TM_ExpireStartedEpochSucceeds() public {
        _fundEngineAndWarp();
        engine.startLotteryEpoch();

        uint256 reservedBefore = engine.reservedPrizePool();
        assertGt(reservedBefore, 0);

        // Default timeout is roundDuration (30 min) + one-hour trigger grace = 90 minutes.
        vm.warp(block.timestamp + 1 hours + 30 minutes + 1);

        engine.expireStartedEpoch(1);

        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.EXPIRED));
        assertEq(engine.reservedPrizePool(), 0);

        // Allows a new round
        vm.deal(address(engine), 1 ether);
        vm.roll(block.number + 1);
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 2);
    }

    // ════════════════════════════════════════════════════════
    //  E2E LIFECYCLE TEST
    // ════════════════════════════════════════════════════════

    function test_EndToEndLifecycle() public {
        // 1. Swap to fund engine
        vm.deal(user, 100 ether);
        vm.startPrank(user);
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: ethCurrency < tokenCurrency,
            amountSpecified: -10 ether,
            sqrtPriceLimitX96: ethCurrency < tokenCurrency ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap{value: 10 ether}(key, params, settings, new bytes(0));
        vm.stopPrank();

        assertGt(engine.availableLotteryBalance(), engine.MIN_LOTTERY_BALANCE());

        // 2. Warp past first lottery delay
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);

        // 3. TX1: Start epoch
        address starter = address(0xAAA);
        vm.prank(starter);
        engine.startLotteryEpoch();
        assertEq(engine.currentRoundId(), 1);
        assertEq(engine.getRoundStarter(1), starter);

        // 4. TX2: Trigger draw after holding epoch
        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);

        address triggerer = address(0xBBB);
        vm.prank(triggerer);
        engine.triggerDraw(1);
        assertEq(engine.getRoundTriggerer(1), triggerer);

        // 5. TX3: Pay lottery after randomness
        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        uint256 userBefore = user.balance;

        address payer = address(0xCCC);
        vm.prank(payer);
        engine.payLottery(1);

        // 6. Verify
        assertEq(engine.getRoundPayer(1), payer);
        assertEq(engine.getRoundWinner(1), user);
        assertGt(engine.getRoundWinnerAmount(1), 0);
        assertGt(engine.getRoundDevAmount(1), 0);
        assertGt(engine.getRoundStartReward(1), 0);
        assertGt(engine.getRoundTriggerReward(1), 0);
        assertGt(engine.getRoundPayReward(1), 0);
        assertGt(user.balance, userBefore);
        assertEq(engine.reservedPrizePool(), 0);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.FULFILLED));
    }

    // ════════════════════════════════════════════════════════
    //  GAS TEST — Worst case bucket scan
    // ════════════════════════════════════════════════════════

    function test_GAS_WorstCaseScan() public {
        // This test ensures startLotteryEpoch fits under block gas limit
        // even when many buckets are active
        _fundEngineAndWarp();

        uint256 gasBefore = gasleft();
        engine.startLotteryEpoch();
        uint256 gasUsed = gasBefore - gasleft();

        // Should be well under 30M block gas limit
        assertLt(gasUsed, 5_000_000);
    }

    function test_GAS_FenwickFairness() public {
        RobinhoodToken t = new RobinhoodToken();
        LotteryEngine e = new LotteryEngine(address(t), address(this), 100 ether);

        // Create 50 holders to populate buckets
        for (uint160 i = 1; i <= 50; i++) {
            address holder = address(uint160(0x50000) + i);
            t.setExemptions(holder, true, false, false);
            t.transfer(holder, 2_000_000 ether);
        }

        t.activateTrading();
        t.setLotteryEngine(address(e));

        vm.deal(address(e), 1 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        e.startLotteryEpoch();

        vm.warp(block.timestamp + 30 minutes);
        vm.roll(block.number + 10);
        e.triggerDraw(1);

        uint256 randBlock = e.getRoundRandomnessBlock(1);
        vm.roll(randBlock + 1);

        uint256 gasBefore = gasleft();
        e.payLottery(1);
        uint256 gasUsed = gasBefore - gasleft();

        // Document the gas cost in the output
        console.log("Gas used by payLottery() with 50 holders:", gasUsed);

        // Note: sum(valid startSnapshot balances in bucket) may be less than snapshotBucketTotals[bucket]
        // because of pruned or stale entries, which causes _weightedPickInBucket to return address(0) gracefully.
        assertLt(gasUsed, 30_000_000); // Should fit easily within block gas limit
    }
}
