## Goal Description
The objective is to deploy the cross-chain lottery contracts to the Robinhood Chain Testnet and Arbitrum Sepolia, wire them together via Chainlink CCIP, and seed initial liquidity. 

You suggested using **Uniswap V3**, which is officially deployed on the Robinhood Chain.

## User Review Required
> [!CAUTION]
> **Major Architectural Decision: Uniswap V2 vs Uniswap V3**
> 
> The current `RobinhoodLotteryToken` contract is programmed to use **Uniswap V2** for its automatic tax-swaps (`swapExactTokensForETHSupportingFeeOnTransferTokens`). Tax tokens (memecoins, lotteries) overwhelmingly use V2 because it is vastly simpler to pool liquidity across the entire price curve and swap fee-on-transfer tokens.
> 
> **If we switch to Uniswap V3:**
> 1. **Contract Rewrite:** I must completely rewrite the `swapTokensForEth` function in your smart contract to use the V3 `ISwapRouter`, and handle WETH wrapping/unwrapping manually. V3 routers do not inherently support fee-on-transfer tokens as easily as V2.
> 2. **Complex Liquidity Provision:** Adding liquidity in V3 requires picking a specific price range (Concentrated Liquidity) and interacting with the `NonfungiblePositionManager` to mint an NFT position, rather than just dumping tokens into a pool.
> 
> **Recommendation:**
> For a tax/lottery token, **Uniswap V2** is almost universally the standard. Even if Robinhood hasn't officially deployed V2 themselves, a community V2 fork (like SushiSwap or a generic Uniswap V2) will certainly exist on Mainnet. 
> 
> **Option A (Recommended):** Keep the contract as Uniswap V2. I will deploy a quick **Mock Uniswap V2** on the testnet just so we can test the taxes and liquidity. When you move to Mainnet, you simply point it to whatever V2 DEX is popular.
> 
> **Option B (V3 Rewrite):** If you absolutely want this token to trade exclusively on Uniswap V3, I will rewrite the smart contract's tax-swap logic and the deployment script to handle V3 concentrated liquidity math.
> 
> **Please reply with Option A or Option B.**

## Proposed Changes (Assuming Option A)
### `contracts/mocks/MockUniswap.sol`
Deploy a functional mock of the Uniswap V2 Factory and Router to the testnet to enable V2 tax swaps.

### `scripts/deploy-robinhood.js`
1. Deploy `MockUniswapV2Router`.
2. Deploy `RobinhoodLotteryToken`.
3. Add Liquidity (All tokens + 1 ETH) via V2 Router (no lock).
4. Activate Trading.

## Verification Plan
*   Run automated test suite to ensure tax swap logic is intact.
*   Deploy to testnets and run a live lottery cycle via the Keeper bot.
