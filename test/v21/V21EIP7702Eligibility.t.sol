// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../v18/V18TestBase.sol";

contract NormalContract {}

contract V21EIP7702EligibilityTest is V18TestBase {
    function testEIP7702Eligibility() public {
        // Create an EIP-7702 EOA mock (23 bytes, starts with 0xef0100)
        address eip7702Account = address(0x7702);
        bytes memory eip7702Code = hex"ef01000000000000000000000000000000000000000000"; // 23 bytes exactly
        vm.etch(eip7702Account, eip7702Code);

        // Create a normal contract
        NormalContract normal = new NormalContract();

        // 1. EIP7702 account should be valid
        assertTrue(token.isEip7702DelegatedEOA(eip7702Account));

        // 2. Normal contract should be invalid
        assertFalse(token.isEip7702DelegatedEOA(address(normal)));

        // 3. EOA should be valid
        assertFalse(token.isEip7702DelegatedEOA(user1));
    }
}
