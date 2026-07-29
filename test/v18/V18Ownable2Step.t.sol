// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./V18TestBase.sol";

contract V18Ownable2StepTest is V18TestBase {
    function test_Ownable2Step_Token() public {
        address newOwner = address(0x9999);

        token.transferOwnership(newOwner);
        assertEq(token.owner(), address(this)); // Owner hasn't changed yet
        assertEq(token.pendingOwner(), newOwner); // Pending owner is set

        vm.prank(newOwner);
        token.acceptOwnership();

        assertEq(token.owner(), newOwner);
        assertEq(token.pendingOwner(), address(0));
    }

    function test_Ownable2Step_Engine() public {
        address newOwner = address(0x9999);

        engine.transferOwnership(newOwner);
        assertEq(engine.owner(), address(this)); // Owner hasn't changed yet
        assertEq(engine.pendingOwner(), newOwner); // Pending owner is set

        vm.prank(newOwner);
        engine.acceptOwnership();

        assertEq(engine.owner(), newOwner);
        assertEq(engine.pendingOwner(), address(0));
    }
}
