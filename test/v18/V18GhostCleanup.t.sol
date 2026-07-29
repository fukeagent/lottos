// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./V18TestBase.sol";

contract GhostContract {
    constructor(RobinhoodToken token, address from, uint256 amount) {
        token.transferFrom(from, address(this), amount);
    }
}

contract Create2Factory {
    function deploy(bytes32 salt, bytes memory initCode) public returns (address addr) {
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }
}

contract V18GhostCleanupTest is V18TestBase {
    Create2Factory factory;

    function setUp() public override {
        super.setUp();
        factory = new Create2Factory();
    }

    function _getInitCode(address from, uint256 amount) internal view returns (bytes memory) {
        return abi.encodePacked(type(GhostContract).creationCode, abi.encode(address(token), from, amount));
    }

    function test_GhostContractCleanup_RefreshEligibilityBatch() public {
        token.activateTrading();

        bytes memory initCode = _getInitCode(address(this), 1000 ether);
        bytes32 salt = keccak256("ghost_salt");
        address ghostAddr = vm.computeCreate2Address(bytes32(salt), keccak256(initCode), address(factory));

        token.approve(ghostAddr, 1000 ether);

        address deployed = factory.deploy(salt, initCode);

        assertEq(deployed, ghostAddr);
        assertEq(token.balanceOf(ghostAddr), 1000 ether);

        // It bypassed code.length check during constructor!
        assertEq(token.eligibleWeightOf(ghostAddr), 1000 ether);

        // Now code.length > 0
        assertTrue(ghostAddr.code.length > 0);

        // Call refreshEligibilityBatch
        address[] memory arr = new address[](1);
        arr[0] = ghostAddr;
        token.refreshEligibilityBatch(arr);

        // It should be cleaned up!
        assertEq(token.eligibleWeightOf(ghostAddr), 0);
    }

    function test_GhostContractCleanup_PayLottery() public {
        token.activateTrading();

        bytes memory initCode = _getInitCode(address(this), 1000 ether);
        bytes32 salt = keccak256("ghost_salt_2");
        address ghostAddr = vm.computeCreate2Address(bytes32(salt), keccak256(initCode), address(factory));

        token.approve(ghostAddr, 1000 ether);
        address deployed = factory.deploy(salt, initCode);

        assertEq(deployed, ghostAddr);

        // Setup lottery round with ghost as the ONLY eligible
        vm.warp(block.timestamp + 2 hours + 1);
        vm.roll(block.number + 10);
        vm.deal(address(engine), 1 ether);

        engine.startLotteryEpoch();
        uint256 roundId = engine.currentRoundId();

        vm.warp(block.timestamp + 30 minutes + 1);
        engine.triggerDraw(roundId);

        vm.roll(block.number + 601);
        vm.warp(block.timestamp + 1202);

        // Pay lottery
        engine.payLottery(roundId);

        // Ghost should have been bypassed and cleaned up!
        assertEq(token.eligibleWeightOf(ghostAddr), 0);
    }
}
