// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library HookMiner {
    // finds a salt that produces a CREATE2 address with the desired flags
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (address hookAddress, bytes32 salt)
    {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        // Mine until the lowest 14 bits match exactly our flags
        // The mask for the lowest 14 bits is 0x3FFF
        uint160 mask = 0x3FFF;

        for (uint256 i = 0; i < type(uint256).max; i++) {
            salt = bytes32(i);
            bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash));
            address derived = address(uint160(uint256(hash)));
            if (uint160(derived) & mask == flags) {
                return (derived, salt);
            }
        }
    }
}
