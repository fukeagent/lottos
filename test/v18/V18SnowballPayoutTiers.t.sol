// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./V18TestBase.sol";

contract V18SnowballPayoutTiersTest is V18TestBase {
    function test_PayoutTiersLogic() public {
        token.activateTrading();

        // Check defaults
        assertEq(engine.tier1MaxBalance(), 2 ether);
        assertEq(engine.tier2MaxBalance(), 10 ether);
        assertEq(engine.tier3MaxBalance(), 50 ether);
        assertEq(engine.tier1PayoutBps(), 2500);
        assertEq(engine.tier2PayoutBps(), 1500);
        assertEq(engine.tier3PayoutBps(), 1000);
        assertEq(engine.tier4PayoutBps(), 500);

        // Tier 1: < 2 ETH (25%)
        vm.deal(address(engine), 1 ether);
        assertEq(engine.getCurrentPayoutBps(), 2500);
        assertEq(engine.getCurrentPrizeAmount(), 0.25 ether);

        // Tier 2: 2 - 10 ETH (15%)
        vm.deal(address(engine), 5 ether);
        assertEq(engine.getCurrentPayoutBps(), 1500);
        assertEq(engine.getCurrentPrizeAmount(), 0.75 ether); // 5 * 15%

        // Tier 3: 10 - 50 ETH (10%)
        vm.deal(address(engine), 20 ether);
        assertEq(engine.getCurrentPayoutBps(), 1000);
        assertEq(engine.getCurrentPrizeAmount(), 2 ether); // 20 * 10%

        // Tier 4: >= 50 ETH (5%)
        vm.deal(address(engine), 100 ether);
        assertEq(engine.getCurrentPayoutBps(), 500);
        assertEq(engine.getCurrentPrizeAmount(), 5 ether); // 100 * 5%

        // 0.05 ETH floor logic
        // If we have 0.1 ETH, 25% is 0.025 ETH, which is below 0.05 floor
        vm.deal(address(engine), 0.1 ether);
        assertEq(engine.getCurrentPrizeAmount(), 0.05 ether);

        // Below 0.05 total balance
        vm.deal(address(engine), 0.04 ether);
        assertEq(engine.getCurrentPrizeAmount(), 0);
    }

    function test_SetPayoutTiersLimits() public {
        // Can only be set by owner
        vm.prank(user1);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        engine.setPayoutTiers(3 ether, 15 ether, 60 ether, 3000, 2000, 1500, 1000);

        // Test bad limits (below initial max balance)
        vm.expectRevert("Tier1 below initial");
        engine.setPayoutTiers(1 ether, 10 ether, 50 ether, 2500, 1500, 1000, 500);

        // Test bad limits (too high max balance)
        vm.expectRevert("Tier1 too high");
        engine.setPayoutTiers(6 ether, 10 ether, 50 ether, 2500, 1500, 1000, 500);

        // Test bad slope (tier1 bps < tier2 bps)
        vm.expectRevert("Bad payout slope");
        engine.setPayoutTiers(2 ether, 10 ether, 50 ether, 2500, 3000, 1000, 500);

        // Valid update
        engine.setPayoutTiers(3 ether, 15 ether, 60 ether, 3000, 2000, 1500, 1000);
        assertEq(engine.tier1MaxBalance(), 3 ether);
        assertEq(engine.tier1PayoutBps(), 3000);
    }
}
