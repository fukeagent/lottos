// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./V18TestBase.sol";

contract DummyRouter {}

contract V18ConfigLocksTest is V18TestBase {
    function test_ConfigLocks() public {
        DummyRouter router = new DummyRouter();
        token.setTaxSwapRouterOnce(address(router)); // required for config

        token.activateTrading();
        assertTrue(token.launchConfigLocked());

        vm.expectRevert("Launch config locked");
        token.setAutoSwapConfig(true, 1, 1, 1);

        token.setAutoSwapEnabled(true);
        assertTrue(token.autoSwapEnabled());
    }

    function test_DevFeeReceiverSnapshotted() public {
        token.transfer(user1, token.minEligibleAmount());
        token.activateTrading();

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        // Change the dev fee receiver globally
        engine.setDevFeeReceiver(address(0x9999));

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);

        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);

        uint256 oldDevBal = devFeeReceiver.balance;
        uint256 newDevBal = address(0x9999).balance;

        engine.payLottery(roundId);

        // the original devFeeReceiver should receive the dev fee since it was snapshotted
        assertTrue(devFeeReceiver.balance > oldDevBal, "Original dev fee receiver should get paid");
        assertEq(address(0x9999).balance, newDevBal, "New dev fee receiver should NOT get paid for old round");
    }
}
