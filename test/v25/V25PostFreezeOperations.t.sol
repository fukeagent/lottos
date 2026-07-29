// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";
import {V24Quote, V24Pool, V24Router} from "../v24/V24AutoSwapOracleProtection.t.sol";

contract V25PostFreezeOperationsTest is Test {
    RobinhoodToken internal token;
    LotteryEngine internal engine;
    V24Router internal router;
    V24Quote internal quote;
    address internal pool;
    address internal seller = address(0xA11CE);
    address internal caller = address(0xCA11);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(0xD3E), 100 ether);
        router = new V24Router(address(0xBEEF));
        quote = new V24Quote();
        pool = address(new V24Pool(address(token), address(0xCAFE)));
        vm.deal(address(router), 10 ether);

        token.setLotteryEngine(address(engine));
        token.setTaxSwapRouterOnce(address(router));
        token.setTaxedExternalPool(pool, true);
        token.setAutoSwapConfig(false, 1 ether, 10 ether, 15 minutes);
        token.setOfficialPoolQuote(address(quote));
        token.setAutoSwapSlippageBps(300);
        token.setExemptions(address(this), true, true, true);
        token.setExemptions(pool, true, true, true);
        token.activateTrading();
        token.transfer(seller, 10_000 ether);
    }

    function _collectTax() internal {
        vm.prank(seller);
        token.transfer(pool, 1_000 ether);
        assertEq(token.balanceOf(address(token)), 100 ether);
    }

    function test_RenounceRequiresFreezeThenTokenAndEngineCanRenounce() public {
        vm.expectRevert("Settings not frozen");
        token.renounceOwnership();
        vm.expectRevert("Settings not frozen");
        engine.renounceOwnership();

        token.freezeSettingsForever();
        token.renounceOwnership();
        engine.renounceOwnership();

        assertEq(token.owner(), address(0));
        assertEq(engine.owner(), address(0));
        vm.expectRevert();
        token.setAutoSwapEnabled(true);
    }

    function test_PermissionlessSweepWorksAfterFreezeAndUsesStricterFloor() public {
        _collectTax();
        token.freezeSettingsForever();
        router.setEthOut(1 ether);

        vm.prank(caller);
        uint256 received = token.sweepTaxTokens(0.99 ether);

        assertEq(received, 1 ether);
        assertEq(router.lastMinOut(), 0.99 ether, "caller may only strengthen the oracle floor");
        assertEq(address(engine).balance, 1 ether);
        assertEq(token.balanceOf(address(token)), 90 ether, "maxSwapAmount caps the permissionless sweep");
    }

    function test_SweepCannotWeakenComputedFloor() public {
        _collectTax();
        router.setEthOut(0.96 ether);

        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(caller);
        token.sweepTaxTokens(0);

        assertEq(token.lastAutoSwapAttemptAt(), 0, "reverting sweep leaves all state unchanged");
        assertEq(token.lastAutoSwapSuccessAt(), 0);
    }

    function test_SuccessfulSweepStartsCooldown() public {
        _collectTax();
        router.setEthOut(1 ether);
        vm.prank(caller);
        token.sweepTaxTokens(0);

        vm.expectRevert("Swap cooldown");
        vm.prank(caller);
        token.sweepTaxTokens(0);
    }

    function test_FailedAutoSwapSetsAttemptCooldownAndNeverBlocksTrade() public {
        token.setAutoSwapEnabled(true);
        router.setEthOut(0.96 ether);

        vm.prank(seller);
        token.transfer(pool, 1_000 ether);
        uint256 firstAttempt = token.lastAutoSwapAttemptAt();

        assertEq(token.balanceOf(pool), 900 ether);
        assertEq(token.balanceOf(address(token)), 100 ether);
        assertEq(token.lastAutoSwapSuccessAt(), 0);
        assertEq(firstAttempt, block.timestamp);

        vm.prank(seller);
        token.transfer(pool, 1_000 ether);
        assertEq(token.lastAutoSwapAttemptAt(), firstAttempt, "cooldown prevents a second doomed attempt");
        assertEq(token.balanceOf(pool), 1_800 ether, "second user trade still completes");

        vm.warp(block.timestamp + token.swapCooldown());
        router.setEthOut(1 ether);
        vm.prank(seller);
        token.transfer(pool, 1_000 ether);
        assertEq(token.lastAutoSwapSuccessAt(), block.timestamp);
        assertEq(address(engine).balance, 1 ether);
    }
}
