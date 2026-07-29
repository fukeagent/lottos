// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RobinhoodToken} from "../contracts/RobinhoodToken.sol";
import {LotteryEngine} from "../contracts/LotteryEngine.sol";

import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LotteryHook} from "../contracts/LotteryHook.sol";
import {HookMiner} from "../script/HookMiner.sol";

contract Factory {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2 failed");
    }
}

contract DeepSimulationTest is Test {
    using CurrencyLibrary for Currency;

    PoolManager manager;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PoolSwapTest swapRouter;

    RobinhoodToken token;
    LotteryEngine engine;
    LotteryHook hook;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    PoolKey poolKey;

    address devWallet = address(0xDEF);
    address[] users;
    Factory factory;

    receive() external payable {}

    function setUp() public {
        console.log("========================================");
        console.log("   INITIALIZING DEEP ANVIL SIMULATION   ");
        console.log("========================================");

        // 1. Core V4 Setup
        manager = new PoolManager(address(0));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);

        // 2. Deploy Token & Engine
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), devWallet, 100 ether);

        factory = new Factory();
        uint160 flags = uint160(0xCC);
        bytes memory creationCode = type(LotteryHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, address(engine), address(token), ethCurrency, address(this));

        (address expectedAddress, bytes32 salt) = HookMiner.find(address(factory), flags, creationCode, constructorArgs);

        address hookAddress = factory.deploy(salt, abi.encodePacked(creationCode, constructorArgs));
        hook = LotteryHook(payable(hookAddress));
        hook.setAutoLotteryConfig(false);

        tokenCurrency = Currency.wrap(address(token));

        // 4. Setup Exemptions & Users
        console.log("Configuring 50 simulated users...");
        for (uint160 i = 1; i <= 50; i++) {
            address u = address(uint160(0x50000) + i);
            users.push(u);
            vm.deal(u, 1000 ether); // give them ETH for swaps
            token.setExemptions(u, true, false, false); // allow them to receive tokens pre-launch
            token.transfer(u, 2_000_000 ether); // give them enough tokens to be eligible!
        }

        token.setExemptions(address(manager), true, true, true);
        token.setOfficialTaxExemptPoolOrManager(address(manager), true);
        token.setExemptions(address(swapRouter), true, true, true);
        token.setExemptions(address(modifyLiquidityRouter), true, true, true);
        token.setExemptions(address(this), true, true, true);

        // 5. Initialize Pool
        poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, hook);
        manager.initialize(poolKey, 79228162514264337593543950336); // 1:1 price

        // 6. Launch & Configure
        token.activateTrading();
        token.setLotteryEngine(address(engine));
        hook.setOfficialPool(poolKey);

        // 7. Add Liquidity
        vm.deal(address(this), 500_000_000 ether);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        modifyLiquidityRouter.modifyLiquidity{value: 200_000_000 ether}(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887220, tickUpper: 887220, liquidityDelta: 100_000_000 ether, salt: 0
            }),
            new bytes(0)
        );

        console.log("Initialization Complete. Environment Ready.");
    }

    function _randomSwap(address user, bool isBuy, uint256 amount) internal {
        vm.startPrank(user);
        if (isBuy) {
            swapRouter.swap{value: amount}(
                poolKey,
                IPoolManager.SwapParams({
                    zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                new bytes(0)
            );
        } else {
            token.approve(address(swapRouter), type(uint256).max);
            swapRouter.swap(
                poolKey,
                IPoolManager.SwapParams({
                    zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                new bytes(0)
            );
        }
        vm.stopPrank();
    }

    function test_DeepLiveSimulation() public {
        console.log("\n========================================");
        console.log("   PHASE 1: ORGANIC TRADING & START     ");
        console.log("========================================");

        uint256 curBlock = 11;
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(curBlock);

        console.log("Simulating 50 random buys...");
        for (uint256 i = 0; i < 50; i++) {
            _randomSwap(users[i], true, 0.1 ether + (i * 0.01 ether));
        }

        uint256 engineBal = address(engine).balance;
        console.log("Engine accrued tax (ETH):", engineBal);

        curBlock += 1;
        vm.roll(curBlock);
        console.log("User 0 starting the epoch...");
        vm.prank(users[0]);
        engine.startLotteryEpoch();

        console.log("Round Status: EPOCH_STARTED");

        console.log("\n========================================");
        console.log("   PHASE 2: THE HOLDING EPOCH (DIAMOND) ");
        console.log("========================================");

        // Advance 15 mins (halfway through holding)
        vm.warp(block.timestamp + 15 minutes);
        curBlock += 50;
        vm.roll(curBlock);

        console.log("Users 10-15 panic sell their bags...");
        for (uint256 i = 10; i < 15; i++) {
            _randomSwap(users[i], false, token.balanceOf(users[i]));
        }

        console.log("Users 20-25 buy more...");
        for (uint256 i = 20; i < 25; i++) {
            _randomSwap(users[i], true, 0.5 ether);
        }

        // Finish holding epoch
        vm.warp(block.timestamp + 15 minutes + 1);
        curBlock += 50;
        vm.roll(curBlock);

        console.log("\n========================================");
        console.log("   PHASE 3: TRIGGER DRAW & PAYOUT       ");
        console.log("========================================");

        console.log("User 1 triggers the draw...");
        vm.prank(users[1]);
        engine.triggerDraw(1);

        uint256 randBlock = engine.getRoundRandomnessBlock(1);
        console.log("Waiting for randomness block:", randBlock);

        curBlock = randBlock + 1;
        vm.roll(curBlock);

        console.log("User 2 pays the lottery...");
        vm.prank(users[2]);
        engine.payLottery(1);

        address winner = engine.getRoundWinner(1);
        console.log("WINNER CHOSEN:", winner);

        if (winner != address(0)) {
            console.log("Winner Prize (ETH):", engine.getRoundWinnerAmount(1));
            console.log(
                "Winner Starting Balance (Tokens):", token.getPastBalance(winner, engine.getRoundStartSnapshotBlock(1))
            );
        }

        console.log("\n========================================");
        console.log("   PHASE 4: STUCK EPOCH SIMULATION      ");
        console.log("========================================");

        // Next round
        vm.warp(block.timestamp + 30 minutes);
        curBlock += 10;
        vm.roll(curBlock);

        console.log("Starting Round 2...");
        engine.startLotteryEpoch();

        // Abandon the round for 4 hours!
        vm.warp(block.timestamp + 4 hours);
        curBlock += 500;
        vm.roll(curBlock);

        console.log("Round 2 is stuck. User 5 expires the started epoch...");
        vm.prank(users[5]);
        engine.expireStartedEpoch(2);

        require(uint256(engine.getRoundStatus(2)) == uint256(LotteryEngine.RoundStatus.EXPIRED), "Not expired");
        console.log("Round 2 successfully expired. Funds unlocked.");

        console.log("\n========================================");
        console.log("   PHASE 5: MISSED BLOCKHASH SIMULATION ");
        console.log("========================================");

        vm.warp(block.timestamp + 4 hours);
        curBlock += 10;
        vm.roll(curBlock);

        console.log("Starting Round 3...");
        engine.startLotteryEpoch();

        vm.warp(block.timestamp + 30 minutes + 1);
        curBlock += 50;
        vm.roll(curBlock);

        console.log("Triggering Draw for Round 3...");
        engine.triggerDraw(3);

        uint256 missedBlock = engine.getRoundRandomnessBlock(3);
        console.log("Blockhash window starts at:", missedBlock);

        // Advance MORE than 256 blocks!
        curBlock = missedBlock + 300;
        vm.roll(curBlock);

        console.log("Too late! Window missed. User 6 expires the lottery...");
        vm.prank(users[6]);
        engine.expireLottery(3);

        require(uint256(engine.getRoundStatus(3)) == uint256(LotteryEngine.RoundStatus.EXPIRED), "Not expired 3");
        console.log("Round 3 successfully expired. Funds unlocked.");

        console.log("\n========================================");
        console.log("   SIMULATION COMPLETE                  ");
        console.log("========================================");
    }
}
