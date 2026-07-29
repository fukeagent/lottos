// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract EngineHarness is LotteryEngine {
    constructor(address _token, address _dev, uint256 _cap) LotteryEngine(_token, _dev, _cap) {}

    function storePendingWinnerPayout(address winner, uint256 amount) public {
        _storePendingWinnerPayout(winner, amount);
    }
}

contract GasHog {
    uint256 public count;

    receive() external payable {
        // Burn gas
        for (uint256 i = 0; i < 200; i++) {
            count += i;
        }
    }
}

contract V21PendingPayoutGasTest is Test {
    RobinhoodToken token;
    EngineHarness engine;

    address owner = address(this);
    address devFeeReceiver = address(0x3333);

    GasHog hog;

    function setUp() public {
        token = new RobinhoodToken();
        engine = new EngineHarness(address(token), devFeeReceiver, 100 ether);
        token.setLotteryEngine(address(engine));

        vm.deal(address(engine), 100 ether);
        hog = new GasHog();
    }

    function testAutoPayoutFailsGasHog() public {
        engine.storePendingWinnerPayout(address(hog), 1 ether);

        // Auto retry uses 50,000 gas, so GasHog should fail
        engine.processPendingWinnerPayouts(1);

        assertEq(engine.pendingWinnerPayout(address(hog)), 1 ether);
        assertEq(engine.pendingWinnerRetryCount(address(hog)), 1);
    }

    function testManualPayoutSucceedsGasHog() public {
        engine.storePendingWinnerPayout(address(hog), 1 ether);

        vm.prank(address(hog));
        engine.claimPendingWinnerPayout();

        assertEq(engine.pendingWinnerPayout(address(hog)), 0);
        assertEq(address(hog).balance, 1 ether);
    }
}
