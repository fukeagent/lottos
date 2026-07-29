// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LotteryHook} from "../../contracts/LotteryHook.sol";
import {RobinhoodToken} from "../../contracts/RobinhoodToken.sol";
import {HookMiner} from "../../script/HookMiner.sol";

contract Factory {
    function deploy(bytes32 salt, bytes memory bytecode) public returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2 failed");
    }
}

contract MockEngine {
    bool public processCalled;
    bool public autoCalled;
    bool public processCalledBeforeAuto;

    receive() external payable {}

    function processPendingWinnerPayouts(uint256 maxCount) external {
        processCalled = true;
    }

    function autoLotteryStep(address rewardTo, uint256 maxPayAttempts)
        external
        returns (uint8 action, uint256 roundId)
    {
        if (processCalled) {
            processCalledBeforeAuto = true;
        }
        autoCalled = true;
        return (0, 0);
    }
}

contract V21HookPendingPayoutRetryTest is Test {
    using CurrencyLibrary for Currency;

    PoolManager manager;
    RobinhoodToken token;
    MockEngine engine;
    LotteryHook hook;
    Factory factory;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    PoolKey key;

    function setUp() public {
        manager = new PoolManager(address(this));
        token = new RobinhoodToken();
        tokenCurrency = Currency.wrap(address(token));
        engine = new MockEngine();
        factory = new Factory();

        uint160 flags = uint160(0xCC);
        bytes memory creationCode = type(LotteryHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, address(engine), address(token), ethCurrency, address(this));

        (address expectedAddress, bytes32 salt) = HookMiner.find(address(factory), flags, creationCode, constructorArgs);

        address hookAddress = factory.deploy(salt, abi.encodePacked(creationCode, constructorArgs));
        hook = LotteryHook(payable(hookAddress));

        vm.prank(address(this));
        token.activateTrading();
    }

    function testHookCallsProcessBeforeAuto() public {
        if (ethCurrency < tokenCurrency) {
            key = PoolKey({currency0: ethCurrency, currency1: tokenCurrency, fee: 3000, tickSpacing: 60, hooks: hook});
        } else {
            key = PoolKey({currency0: tokenCurrency, currency1: ethCurrency, fee: 3000, tickSpacing: 60, hooks: hook});
        }
        hook.setOfficialPool(key);
        vm.deal(address(hook), 1 ether);

        // Mock pool manager take
        vm.mockCall(address(manager), abi.encodeWithSelector(manager.take.selector), abi.encode(""));

        IPoolManager.SwapParams memory params;
        params.amountSpecified = -10000;
        params.zeroForOne = (ethCurrency < tokenCurrency); // ETH is currency0

        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, params, new bytes(0));

        assertTrue(engine.processCalled());
        assertTrue(engine.autoCalled());
        assertTrue(engine.processCalledBeforeAuto());
    }
}
