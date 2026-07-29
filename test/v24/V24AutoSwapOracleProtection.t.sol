// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../contracts/RobinhoodToken.sol";
import "../../contracts/LotteryEngine.sol";

contract V24Quote {
    bool public ready = true;
    uint256 public quote = 1 ether;

    function setReady(bool value) external {
        ready = value;
    }

    function setQuote(uint256 value) external {
        quote = value;
    }

    function quoteReady() external view returns (bool) {
        return ready;
    }

    function quoteTokenToETH(uint256) external view returns (uint256) {
        return quote;
    }
}

contract V24Pool {
    address public token0;
    address public token1;

    constructor(address token, address other) {
        token0 = token;
        token1 = other;
    }

    function getReserves() external pure returns (uint112, uint112, uint32) {
        return (1, 1, 0);
    }
}

contract V24Router {
    address public immutable WETH;
    uint256 public ethOut;
    uint256 public swaps;
    uint256 public lastMinOut;

    constructor(address weth) {
        WETH = weth;
    }

    function setEthOut(uint256 value) external {
        ethOut = value;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external {
        swaps++;
        lastMinOut = amountOutMin;
        require(ethOut >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        RobinhoodToken(payable(path[0])).transferFrom(msg.sender, address(this), amountIn);
        payable(to).transfer(ethOut);
    }
    receive() external payable {}
}

contract V24AutoSwapOracleProtectionTest is Test {
    RobinhoodToken internal token;
    LotteryEngine internal engine;
    V24Router internal router;
    V24Quote internal quote;
    address internal pool;
    address internal seller = address(0xA11CE);

    function setUp() public {
        token = new RobinhoodToken();
        engine = new LotteryEngine(address(token), address(0xD3E), 100 ether);
        router = new V24Router(address(0xBEEF));
        quote = new V24Quote();
        pool = address(new V24Pool(address(token), address(0xCAFE)));
        vm.deal(address(router), 10 ether);

        token.setLotteryEngine(address(engine));
        token.setTaxSwapRouterOnce(address(router));
        token.setTaxedExternalPool(pool, true);
        token.setAutoSwapConfig(true, 1 ether, 10 ether, 0);
        token.setOfficialPoolQuote(address(quote));
        token.setAutoSwapSlippageBps(300);
        token.setExemptions(address(this), true, true, true);
        token.setExemptions(pool, true, true, true);
        token.activateTrading();
        token.transfer(seller, 10_000 ether);
    }

    function _sell(uint256 amount) internal {
        vm.prank(seller);
        token.transfer(pool, amount);
    }

    function test_AutoSwapSkipsWhenQuoteNotReady() public {
        quote.setReady(false);
        _sell(1_000 ether);
        assertEq(router.swaps(), 0);
        assertEq(token.balanceOf(address(token)), 100 ether);
    }

    function test_AutoSwapSkipsWhenQuoteIsZero() public {
        quote.setQuote(0);
        _sell(1_000 ether);
        assertEq(router.swaps(), 0);
        assertEq(token.balanceOf(address(token)), 100 ether);
    }

    function test_ManipulatedBelowFloorDoesNotRevertSellerTransfer() public {
        router.setEthOut(0.96 ether); // quote floor is 0.97 ETH
        _sell(1_000 ether);
        assertEq(token.balanceOf(pool), 900 ether, "taxed transfer completed");
        assertEq(router.swaps(), 0, "failed self-call rolls router state back");
        assertEq(token.balanceOf(address(token)), 100 ether, "tax tokens retained");
        assertEq(address(engine).balance, 0, "no under-floor ETH accepted");
    }

    function test_WithinSlippageExecutesAndUsesOracleFloor() public {
        router.setEthOut(0.98 ether);
        _sell(1_000 ether);
        assertEq(router.swaps(), 1);
        assertEq(router.lastMinOut(), 0.97 ether);
        assertGe(address(engine).balance, router.lastMinOut());
        assertEq(token.balanceOf(address(token)), 90 ether);
    }

    function test_MaxSwapAmountAndCooldownBoundRepeatedExtraction() public {
        RobinhoodToken fresh = new RobinhoodToken();
        LotteryEngine freshEngine = new LotteryEngine(address(fresh), address(0xD3E), 100 ether);
        V24Router freshRouter = new V24Router(address(0xBEEF));
        V24Quote freshQuote = new V24Quote();
        address freshPool = address(new V24Pool(address(fresh), address(0xCAFE)));
        vm.deal(address(freshRouter), 10 ether);
        fresh.setLotteryEngine(address(freshEngine));
        fresh.setTaxSwapRouterOnce(address(freshRouter));
        fresh.setTaxedExternalPool(freshPool, true);
        fresh.setAutoSwapConfig(true, 1 ether, 5 ether, 1 hours);
        fresh.setOfficialPoolQuote(address(freshQuote));
        fresh.setExemptions(address(this), true, true, true);
        fresh.setExemptions(freshPool, true, true, true);
        fresh.activateTrading();
        fresh.transfer(seller, 10_000 ether);
        vm.warp(block.timestamp + 1 hours);
        router.setEthOut(1 ether);
        freshRouter.setEthOut(1 ether);
        vm.prank(seller);
        fresh.transfer(freshPool, 1_000 ether);
        assertEq(freshRouter.swaps(), 1);
        assertEq(fresh.balanceOf(address(fresh)), 5 ether, "only capped amount swapped");
        vm.prank(seller);
        fresh.transfer(freshPool, 1_000 ether);
        assertEq(freshRouter.swaps(), 1, "cooldown blocks repeat");
    }

    function test_ManualSwapHonorsExplicitMinOut() public {
        token.setAutoSwapEnabled(false);
        _sell(1_000 ether);
        router.setEthOut(0.5 ether);
        vm.expectRevert("INSUFFICIENT_OUTPUT_AMOUNT");
        token.manualSwapTaxTokens(10 ether, 0.6 ether);
        assertEq(token.balanceOf(address(token)), 100 ether);
    }
}
