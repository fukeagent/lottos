// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";

contract V24V2Pool {
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

contract V24V3Pool {
    address public token0;
    address public token1;

    constructor(address a, address b) {
        token0 = a;
        token1 = b;
    }

    function fee() external pure returns (uint24) {
        return 3000;
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (1, 0, 0, 0, 0, 0, true);
    }
}

contract V24NotAPool {}

contract V24TaxedExternalPoolValidationTest is Test {
    RobinhoodToken internal token;
    LotteryEngine internal engine;

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(0xD3E), 100 ether);
        token.setLotteryEngine(address(engine));
    }

    function test_RejectsEOAAndRandomContract() public {
        vm.expectRevert("Not contract");
        token.setTaxedExternalPool(address(0x1234), true);
        address notAPool = address(new V24NotAPool());
        vm.expectRevert("Invalid external pool");
        token.setTaxedExternalPool(notAPool, true);
    }

    function test_ValidatesV2AndV3ContainingTokenAndAllowsRemoval() public {
        address v2 = address(new V24V2Pool(address(token), address(0xB0B)));
        address v3 = address(new V24V3Pool(address(0xB0B), address(token)));
        token.setTaxedExternalPool(v2, true);
        token.setTaxedExternalPool(v3, true);
        assertEq(uint256(token.taxedExternalPoolKind(v2)), uint256(RobinhoodToken.ExternalPoolKind.UniswapV2Like));
        assertEq(uint256(token.taxedExternalPoolKind(v3)), uint256(RobinhoodToken.ExternalPoolKind.UniswapV3Like));
        token.setTaxedExternalPool(v2, false);
        assertFalse(token.isTaxedExternalPool(v2));
    }

    function test_RejectsWrongPairOfficialAndLotteryAllowedContract() public {
        address wrongPair = address(new V24V2Pool(address(0xA), address(0xB)));
        vm.expectRevert("Invalid external pool");
        token.setTaxedExternalPool(wrongPair, true);

        address valid = address(new V24V2Pool(address(token), address(0xB0B)));
        token.setOfficialTaxExemptPoolOrManager(valid, true);
        vm.expectRevert("Official path");
        token.setTaxedExternalPool(valid, true);

        address allowed = address(new V24V2Pool(address(token), address(0xCAFE)));
        token.setContractLotteryAllowed(allowed, true);
        vm.expectRevert("Lottery allowed contract");
        token.setTaxedExternalPool(allowed, true);
    }

    function test_RejectsTokenAndEngineAndFreezesConfiguration() public {
        vm.expectRevert("Token contract");
        token.setTaxedExternalPool(address(token), true);
        vm.expectRevert("Lottery engine");
        token.setTaxedExternalPool(address(engine), true);
        token.freezeSettingsForever();
        address valid = address(new V24V2Pool(address(token), address(1)));
        vm.expectRevert("Settings frozen forever");
        token.setTaxedExternalPool(valid, true);
    }
}
