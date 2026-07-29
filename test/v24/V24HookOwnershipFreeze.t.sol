// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LotteryHook} from "../../contracts/LotteryHook.sol";
import {RobinhoodToken} from "../../contracts/RobinhoodToken.sol";
import {HookMiner} from "../../script/HookMiner.sol";

contract V24HookFactory {
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address deployed) {
        assembly { deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt) }
        require(deployed != address(0), "Create2 failed");
    }
}

contract V24HookEngineStub {
    function isLotteryPending() external pure returns (bool) {
        return false;
    }
}

contract V24HookOwnershipFreezeTest is Test {
    using CurrencyLibrary for Currency;

    PoolManager internal manager;
    RobinhoodToken internal token;
    LotteryHook internal hook;
    address internal successor = address(0xB0B);

    function setUp() public {
        manager = new PoolManager(address(this));
        token = new RobinhoodToken();
        token.setLotteryEngine(address(new V24HookEngineStub()));
        V24HookFactory factory = new V24HookFactory();
        Currency eth = Currency.wrap(address(0));
        bytes memory creation = type(LotteryHook).creationCode;
        bytes memory args = abi.encode(manager, address(0xE11), address(token), eth, address(this));
        (address expected, bytes32 salt) = HookMiner.find(address(factory), uint160(0xCC), creation, args);
        hook = LotteryHook(payable(factory.deploy(salt, abi.encodePacked(creation, args))));
        assertEq(address(hook), expected);
    }

    function _setOfficialPool() internal {
        Currency eth = Currency.wrap(address(0));
        Currency tok = Currency.wrap(address(token));
        PoolKey memory key = eth < tok
            ? PoolKey({currency0: eth, currency1: tok, fee: 3000, tickSpacing: 60, hooks: hook})
            : PoolKey({currency0: tok, currency1: eth, fee: 3000, tickSpacing: 60, hooks: hook});
        hook.setOfficialPool(key);
    }

    function test_TwoStepTransferAndFreezeGatedRenounce() public {
        hook.transferOwnership(successor);
        vm.prank(successor);
        hook.acceptOwnership();
        assertEq(hook.owner(), successor);
        vm.expectRevert();
        hook.setAutoLotteryConfig(false);
        vm.prank(successor);
        hook.setAutoLotteryConfig(false);
        vm.prank(successor);
        vm.expectRevert("Settings not frozen");
        hook.renounceOwnership();

        vm.prank(successor);
        _setOfficialPool();
        token.freezeSettingsForever();
        vm.prank(successor);
        hook.renounceOwnership();
        assertEq(hook.owner(), address(0));
        vm.prank(successor);
        vm.expectRevert();
        hook.setAutoLotteryConfig(true);
    }
}
