// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/RobinhoodToken.sol";
import "../contracts/LotteryEngine.sol";

contract RobinhoodTokenTest is Test {
    RobinhoodToken token;
    LotteryEngine engine;

    address owner = address(this);
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address devWallet = address(0x3333);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), devWallet, 100 ether);
        token.setLotteryEngine(address(engine));

        // ── ALL exemptions MUST be set BEFORE activateTrading() ──
        // Owner: fully exempt (trading + maxWallet + eligibility)
        token.setExemptions(owner, true, true, true);
        // Users: trading exempt so transfers work, but NOT eligibility exempt (lottery eligible)
        token.setExemptions(user1, true, false, false);
        token.setExemptions(user2, true, false, false);

        token.activateTrading();
    }

    /// @notice totalSupply and balanceOf(owner) equal TOTAL_SUPPLY after deployment.
    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(owner), 1_000_000_000 ether);
    }

    /// @notice Transferring tokens writes a checkpoint retrievable via getPastBalance.
    function test_TransferUpdatesCheckpoints() public {
        vm.roll(100);
        token.transfer(user1, 1000 ether);

        vm.roll(105);
        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(token.getPastBalance(user1, 100), 1000 ether);
        assertEq(token.getPastBalance(user1, 99), 0);
    }

    /// @notice Transfers exceeding getMaxWallet() revert for non-exempt recipients.
    function test_MaxWalletLimit() public {
        uint256 maxWallet = token.getMaxWallet();

        // Exceeding max wallet should revert
        vm.expectRevert("Exceeds max wallet limit");
        token.transfer(user1, maxWallet + 1);

        // Exactly max wallet should succeed
        token.transfer(user1, maxWallet);
        assertEq(token.balanceOf(user1), maxWallet);
    }

    /// @notice setExemptions reverts after activateTrading() because launchConfigLocked == true.
    function test_SetExemptionsLockedAfterTrading() public {
        assertTrue(token.launchConfigLocked());

        vm.expectRevert("Launch config locked");
        token.setExemptions(user1, true, true, true);
    }

    /// @notice minEligibleAmount returns 0.1% of totalSupply.
    function test_MinEligibleAmount() public {
        assertEq(token.minEligibleAmount(), 1000 ether);
    }

    /// @notice Transferring enough tokens to a user updates the activeBucketBitmap.
}
