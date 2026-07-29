## Goal Description
We are upgrading `RobinhoodLotteryToken` to use **Uniswap V3** exclusively. We will stick with **Choice 1**, meaning the contract will automatically swap small batches of collected token taxes into WETH (and instantly unwrap it to Native ETH) during normal user trades. After deploying the contracts to the testnets, the deployment scripts will automatically write the new contract addresses directly into your `.env` file.

## User Review Required
> [!TIP]
> **Small Batch Tax Swaps:** I will lower the `swapTokensAtAmount` threshold. This ensures the contract swaps taxes in smaller chunks more frequently, which prevents giant market-sells on the chart and accumulates ETH steadily into the contract's vault.

## Proposed Changes

---

### `contracts/RobinhoodLotteryToken.sol`
We will rewrite the contract to use V3 routing while keeping the auto-swap mechanic.

#### [MODIFY] `contracts/RobinhoodLotteryToken.sol`
1.  **Interfaces:** Remove V2 Router. Add V3 `ISwapRouter` and `IWETH9`.
2.  **State:** Add `address public v3SwapRouter;` and `address public WETH;`. 
3.  **`_update()`:** Keep the auto-swap block, but lower the threshold to `100_000 * 1e18` tokens.
4.  **`swapTokensForEth()`:** 
    ```solidity
    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        if (v3SwapRouter == address(0)) return;
        
        _approve(address(this), v3SwapRouter, tokenAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: WETH,
            fee: 3000, 
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        try ISwapRouter(v3SwapRouter).exactInputSingle(params) returns (uint256 amountOut) {
            IWETH9(WETH).withdraw(amountOut);
            emit TaxesSwapped(tokenAmount, amountOut);
        } catch {}
    }
    ```

---

### Deployment Scripts & Mocks
#### [NEW] `contracts/mocks/MockUniswapV3.sol`
*   Create a simple Mock V3 ecosystem (Router, Factory, PositionManager) to run testnet liquidity.

#### [MODIFY] `scripts/deploy-robinhood.js` & `scripts/deploy-arbitrum.js`
*   Deploy the contracts (including the Mock V3 environment on Robinhood Testnet).
*   Add the full-range V3 liquidity.
*   **NEW:** Read the local `.env` file and use Node.js `fs` to automatically replace `ROBINHOOD_LOTTERY_ADDRESS=` and `ARBITRUM_VRF_REQUESTER_ADDRESS=` with the newly deployed addresses!

## Verification Plan
### Automated Tests
*   Update `CCIPRandomness.test.js` to simulate the V3 pool.
*   Run the Hardhat test suite to ensure the taxes are correctly swapped into Native ETH.

### Manual Verification
*   We will deploy everything.
*   We will check that your `.env` file has been automatically populated with the new addresses.
