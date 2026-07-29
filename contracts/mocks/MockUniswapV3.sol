// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract MockWETH is ERC20, IWETH9 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
    }
}

contract MockUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        pool = address(new MockUniswapV3Pool(tokenA, tokenB, fee));
        getPool[tokenA][tokenB][fee] = pool;
        getPool[tokenB][tokenA][fee] = pool;
    }
}

contract MockUniswapV3Pool {
    address public token0;
    address public token1;
    uint24 public fee;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    function initialize(uint160 sqrtPriceX96) external {}
}

contract MockNonfungiblePositionManager {
    address public factory;
    address public WETH9;

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (params.token0 != WETH9) {
            IERC20(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        }
        if (params.token1 != WETH9) {
            IERC20(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        }
        return (1, 1000, params.amount0Desired, params.amount1Desired);
    }

    function refundETH() external payable {
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }
}

contract MockSwapRouter {
    address public factory;
    address public WETH9;

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn / 1000000000000000; // tiny mock conversion rate to avoid needing huge ETH

        if (params.tokenOut == WETH9) {
            MockWETH(WETH9).deposit{value: amountOut}();
            IERC20(WETH9).transfer(params.recipient, amountOut);
        } else {
            IERC20(params.tokenOut).transfer(params.recipient, amountOut);
        }
        return amountOut;
    }

    receive() external payable {}
}
