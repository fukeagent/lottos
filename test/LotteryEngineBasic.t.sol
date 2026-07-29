// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/RobinhoodToken.sol";
import "../contracts/LotteryEngine.sol";

contract LotteryEngineBasicTest is Test {
    RobinhoodToken token;
    LotteryEngine engine;

    address owner = address(this);
    address devFeeReceiver = address(0x3333);
    address user1 = address(0x1111);
    address user2 = address(0x2222);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), devFeeReceiver, 100 ether);
        token.setLotteryEngine(address(engine));

        // ── ALL exemptions MUST be set BEFORE activateTrading() ──
        // Owner (this contract): trading + maxWallet + eligibility exempt
        token.setExemptions(owner, true, true, true);
        // Users: trading exempt (so they can receive tokens pre-trading-activation isn't needed,
        // but we give them trading=true so transfers work). NOT eligibility exempt (eligible for lottery).
        token.setExemptions(user1, true, false, false);
        token.setExemptions(user2, true, false, false);
    }

    /// @notice Sending ETH to the engine increases availableLotteryBalance.
    function test_PrizePoolAccumulation() public {
        vm.deal(address(this), 2 ether);
        (bool success,) = address(engine).call{value: 1 ether}("");
        require(success, "ETH send failed");

        assertEq(engine.availableLotteryBalance(), 1 ether);
        assertEq(address(engine).balance, 1 ether);
    }

    /// @notice startLotteryEpoch reverts when trading has not been activated.
    function test_StartEpochRequiresTrading() public {
        // setUp did NOT call activateTrading(), so tradingActivatedAt == 0
        vm.deal(address(engine), 1 ether);

        vm.expectRevert("Trading not active");
        engine.startLotteryEpoch();
    }

    /// @notice startLotteryEpoch reverts if called before FIRST_LOTTERY_DELAY (2 hours).
    function test_StartEpochRequires2Hours() public {
        token.activateTrading();

        vm.deal(address(engine), 1 ether);

        // Warp only 1 hour — still within the 2-hour delay
        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert("Too early after launch");
        engine.startLotteryEpoch();
    }

    /// @notice Full happy path: activate trading → warp 2hrs → fund engine → startLotteryEpoch succeeds.
    function test_StartEpochSucceeds() public {
        // Give user1 tokens so there's an eligible holder
        uint256 eligibleAmount = token.minEligibleAmount();
        token.transfer(user1, eligibleAmount);

        token.activateTrading();

        // Warp past FIRST_LOTTERY_DELAY (2 hours)
        vm.warp(block.timestamp + 2 hours + 1);
        // Roll forward so getPastBalance has a valid historical block
        vm.roll(block.number + 10);

        // Fund the engine with 1 ETH (needs >= MIN_LOTTERY_BALANCE after payoutBps)
        vm.deal(address(engine), 1 ether);
        assertEq(engine.availableLotteryBalance(), 1 ether);

        // Start the epoch
        engine.startLotteryEpoch();

        // Verify round state
        assertEq(engine.currentRoundId(), 1);
        assertEq(uint256(engine.getRoundStatus(1)), uint256(LotteryEngine.RoundStatus.EPOCH_STARTED));
        assertTrue(engine.isLotteryPending());

        // selectedPrizePool = 1 ether * 2500 / 10000 = 0.25 ether (V18 Tier 1)
        assertEq(engine.getRoundSelectedPrizePool(1), 0.25 ether);
        assertEq(engine.reservedPrizePool(), 0.25 ether);
        // available = 1 ether - 0.25 ether reserved
        assertEq(engine.availableLotteryBalance(), 0.75 ether);
    }

    receive() external payable {}
}

contract HarnessLotteryEngine is LotteryEngine {
    constructor(address _token, address _devFeeReceiver, uint256 _hardMaxPrizePayout)
        LotteryEngine(_token, _devFeeReceiver, _hardMaxPrizePayout)
    {}

    function exposeTryPayout(address to, uint256 amount, PayoutType pType) external returns (bool) {
        return _tryPayout(to, amount, pType);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("I reject ETH");
    }
}

contract LotteryEnginePayoutTest is Test {
    HarnessLotteryEngine engine;

    function setUp() public {
        engine = new HarnessLotteryEngine(address(this), address(this), 100 ether);
        vm.deal(address(engine), 10 ether);
    }

    function test_PayoutFailureReturnsFalse() public {
        RevertingReceiver receiver = new RevertingReceiver();

        bool success = engine.exposeTryPayout(address(receiver), 1 ether, LotteryEngine.PayoutType.Winner);

        assertEq(success, false);
        // Balance should remain in engine
        assertEq(address(engine).balance, 10 ether);
    }
}
