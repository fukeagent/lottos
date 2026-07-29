// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";

contract V24CheckpointPool {
    address public token0;
    address public token1;

    constructor(address a, address b) {
        token0 = a;
        token1 = b;
    }

    function getReserves() external pure returns (uint112, uint112, uint32) {
        return (1, 1, 0);
    }
}

contract V24CheckpointTest is Test {
    RobinhoodToken internal token;
    LotteryEngine internal engine;
    address internal pool;
    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(0xD3E), 100 ether);
        pool = address(new V24CheckpointPool(address(token), address(0xB0B)));
        token.setLotteryEngine(address(engine));
        token.setTaxedExternalPool(pool, true);
        token.setExemptions(address(this), true, true, true);
        token.setExemptions(pool, true, true, true);
        token.activateTrading();
        token.transfer(alice, 10_000 ether);
    }

    function test_TaxSkimsCheckpointTokenContractAndOverwritesSameBlock() public {
        vm.startPrank(alice);
        token.transfer(pool, 1_000 ether);
        token.transfer(pool, 2_000 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(address(token)), 300 ether);
        assertTrue(token.isEligibilityExempt(address(token)));
        vm.roll(block.number + 2);
        assertEq(token.getPastBalance(address(token), block.number - 2), 300 ether);
        assertEq(token.eligibleWeightOf(address(token)), 0);
    }

    function test_RoundDurationBoundsPendingAndFreeze() public {
        assertEq(engine.roundDuration(), 30 minutes);
        engine.setRoundDuration(10 minutes);
        assertEq(engine.roundDuration(), 10 minutes);
        engine.setRoundDuration(24 hours);
        vm.expectRevert("Duration too short");
        engine.setRoundDuration(10 minutes - 1);
        vm.expectRevert("Duration too long");
        engine.setRoundDuration(24 hours + 1);

        token.transfer(address(0xB0B), 2_000 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        vm.expectRevert("Lottery pending");
        engine.setRoundDuration(10 minutes);
    }

    function test_TriggerDrawUsesConfiguredDuration() public {
        engine.setRoundDuration(10 minutes);
        token.transfer(address(0xB0B), 2_000 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 1);
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();
        vm.warp(block.timestamp + 10 minutes - 1);
        vm.expectRevert("Holding epoch not finished");
        engine.triggerDraw(roundId);
        vm.warp(block.timestamp + 1);
        engine.triggerDraw(roundId);
    }
}
