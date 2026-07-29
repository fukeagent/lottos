// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";
import "../v18/V18TestBase.sol";

contract MockContract {
    receive() external payable {}
}

contract V22ContractLotteryWhitelistTest is V18TestBase {
    MockContract mockContract;
    MockContract mockPool;

    function setUp() public override {
        super.setUp();
        mockContract = new MockContract();
        mockPool = new MockContract();
        token.activateTrading();
    }

    function test_NormalContractIneligibleByDefault() public {
        token.transfer(address(mockContract), 2000 ether);
        assertTrue(token.isLotteryIneligible(address(mockContract)));
    }

    function test_OwnerCanWhitelistContract() public {
        token.transfer(address(mockContract), 2000 ether);

        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), true);

        assertTrue(token.contractLotteryAllowed(address(mockContract)));
        assertFalse(token.isLotteryIneligible(address(mockContract)));
    }

    function test_WhitelistedContractBecomesEligible() public {
        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), true);

        token.transfer(address(mockContract), 2000 ether);
        assertFalse(token.isLotteryIneligible(address(mockContract)));
    }

    function test_WhitelistedContractCanResolveAndReceiveWinnerPayout() public {
        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), true);
        token.transfer(address(mockContract), token.minEligibleAmount());

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);
        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);
        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);
        engine.payLottery(roundId);

        assertEq(engine.getRoundWinner(roundId), address(mockContract));
        assertEq(address(mockContract).balance, engine.getRoundWinnerAmount(roundId));
    }

    function test_RemovingWhitelistClearsEligibility() public {
        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), true);
        token.transfer(address(mockContract), 2000 ether);
        assertFalse(token.isLotteryIneligible(address(mockContract)));

        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), false);
        assertTrue(token.isLotteryIneligible(address(mockContract)));
    }

    function test_CannotWhitelistEOA() public {
        vm.prank(owner);
        vm.expectRevert("Not contract");
        token.setContractLotteryAllowed(user1, true);
    }

    function test_CannotChangeWhitelistDuringPendingLottery() public {
        token.transfer(user1, 2000 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();

        vm.prank(owner);
        vm.expectRevert("Lottery pending");
        token.setContractLotteryAllowed(address(mockContract), true);
    }

    function test_WhitelistChangeAffectsFutureOnly() public {
        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), true);
        token.transfer(address(mockContract), 2000 ether);

        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        assertEq(token.getHolderByEligibleIndexAtRound(1, roundId), address(mockContract));

        vm.warp(block.timestamp + 3 hours);
        engine.expireStartedEpoch(roundId);

        vm.prank(owner);
        token.setContractLotteryAllowed(address(mockContract), false);

        assertTrue(token.isLotteryIneligible(address(mockContract)));
    }

    function test_EIP7702DelegatedEOARemainsEligible() public {
        address userEOA = address(0x999);
        vm.etch(userEOA, abi.encodePacked(bytes3(0xef0100), address(0x123)));

        token.transfer(userEOA, 2000 ether);
        assertFalse(token.isLotteryIneligible(userEOA));
    }
}
