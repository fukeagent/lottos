// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LotteryHook} from "../contracts/LotteryHook.sol";
import {RobinhoodToken} from "../contracts/RobinhoodToken.sol";
import {LotteryEngine} from "../contracts/LotteryEngine.sol";
import {HookMiner} from "./HookMiner.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract Factory {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2 failed");
    }
}

contract DeployLocalV4 is Script {
    function run() external {
        vm.startBroadcast();

        address owner = msg.sender;

        // 1. Deploy PoolManager
        PoolManager manager = new PoolManager(owner);
        console.log("PoolManager deployed at:", address(manager));

        // 2. Deploy RobinhoodToken
        RobinhoodToken token = new RobinhoodToken();
        console.log("Token deployed at:", address(token));

        // 3. Deploy LotteryEngine
        LotteryEngine engine = new LotteryEngine(address(token), owner, 100 ether);
        console.log("Engine deployed at:", address(engine));

        // 4. Mine Hook address
        uint160 flags = uint160(0xCC); // beforeSwap, afterSwap, beforeSwapReturnDelta, afterSwapReturnDelta
        Currency ethCurrency = Currency.wrap(address(0));

        bytes memory creationCode = type(LotteryHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, address(engine), address(token), ethCurrency, owner);

        Factory factory = new Factory();
        console.log("Factory deployed at:", address(factory));

        (address expectedAddress, bytes32 salt) = HookMiner.find(address(factory), flags, creationCode, constructorArgs);

        console.log("Mined salt:", uint256(salt));
        console.log("Expected hook address:", expectedAddress);

        // 5. Deploy Hook using CREATE2
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        address hookAddress = factory.deploy(salt, bytecode);
        require(hookAddress == expectedAddress, "Hook address mismatch");
        console.log("Hook deployed at:", hookAddress);

        LotteryHook hook = LotteryHook(payable(hookAddress));

        // 6. Wire contracts and initialize pool
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        bool zeroForOne = ethCurrency < Currency.wrap(address(token));
        Currency currency0 = zeroForOne ? ethCurrency : Currency.wrap(address(token));
        Currency currency1 = zeroForOne ? Currency.wrap(address(token)) : ethCurrency;

        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddress)
        });

        manager.initialize(key, 79228162514264337593543950336); // 1:1 price

        hook.setOfficialPool(key);
        token.setLotteryEngine(address(engine));

        token.setExemptions(address(manager), true, true, true);
        token.setOfficialTaxExemptPoolOrManager(address(manager), true);
        token.setExemptions(address(modifyLiquidityRouter), true, true, true);
        token.setExemptions(owner, true, true, true);

        // (Trading activation deferred until after liquidity)

        // 7. Add liquidity
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity{value: 100 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100 ether, salt: 0}),
            new bytes(0)
        );
        console.log("Initial liquidity added.");

        token.activateTrading();
        console.log("Trading activated.");

        // Output confirmation
        console.log("Deployment complete.");

        vm.stopBroadcast();
    }
}
