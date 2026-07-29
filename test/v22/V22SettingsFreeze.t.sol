// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";
import "../v18/V18TestBase.sol";

contract V22SettingsFreezeTest is V18TestBase {
    function setUp() public override {
        super.setUp();
        token.activateTrading();
    }

    function test_FreezeSettings() public {
        vm.prank(owner);
        token.freezeSettingsForever();
        assertTrue(token.settingsFrozenForever());
    }

    function test_FreezeSettingsRevertsIfAlreadyFrozen() public {
        vm.prank(owner);
        token.freezeSettingsForever();

        vm.prank(owner);
        vm.expectRevert("Already frozen");
        token.freezeSettingsForever();
    }

    function test_CannotFreezeDuringPendingLottery() public {
        token.transfer(user1, 2000 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();

        vm.prank(owner);
        vm.expectRevert("Lottery pending");
        token.freezeSettingsForever();
    }

    function test_SettersRevertAfterFreeze() public {
        vm.prank(owner);
        token.freezeSettingsForever();

        vm.prank(owner);
        vm.expectRevert("Settings frozen forever");
        token.setTaxedExternalPool(address(0x123), true);

        vm.prank(owner);
        vm.expectRevert("Settings frozen forever");
        token.setContractLotteryAllowed(address(0x123), true);

        vm.prank(owner);
        vm.expectRevert("Settings frozen forever");
        engine.setDevFeeReceiver(address(0x123));

        vm.prank(owner);
        vm.expectRevert("Settings frozen forever");
        engine.setPayoutTiers(1 ether, 2 ether, 3 ether, 10, 5, 2, 1);

        vm.prank(owner);
        vm.expectRevert("Settings frozen forever");
        token.setAutoSwapEnabled(false);
    }

    function test_PermissionlessOpsWorkAfterFreeze() public {
        token.transfer(user1, 2000 ether);
        vm.prank(owner);
        token.freezeSettingsForever();

        token.transfer(user1, 100 ether);
        token.refreshEligibility(user1);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);
    }
}
