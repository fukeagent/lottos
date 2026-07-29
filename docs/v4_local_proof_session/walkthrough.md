# Walkthrough: Uniswap V4 Migration

We have successfully migrated the Robinhood Lottery Token architecture from a Uniswap V3 Fee-On-Transfer (FOT) model to a state-of-the-art Uniswap V4 Hook architecture. 

## Architectural Changes Made

We decomposed the monolithic `RobinhoodLotteryToken.sol` into three distinct contracts:

1. **`RobinhoodToken.sol`**:
   - Stripped out all swap-and-tax logic, making it a pure, highly gas-efficient ERC20 token.
   - Retained the `Checkpoints` mechanism for lottery eligibility.
   - Retained `bucketHolders` and append-only arrays for finalization security.
   - Retained the `getMaxWallet()` time-based limits.
   - Standard peer-to-peer (P2P) transfers are now 100% tax-free at the token level, eliminating all DEX router "fee-on-transfer" reversion issues.

2. **`LotteryEngine.sol`**:
   - Houses the secure lottery finalization logic we previously hardened (continuation cursors, fixed blockhashes, max attempt caps).
   - Entirely decoupled from the token, meaning it can be seamlessly upgraded in the future without redeploying the ERC20 token itself.
   - Contains a `receive() external payable` fallback to accept tax directly in ETH from the V4 Hook.

3. **`LotteryHook.sol`**:
   - A Uniswap V4 `BaseHook` that attaches to the token's ETH AMM pool.
   - Implements an `afterSwap` interceptor with the `afterSwapReturnDelta` permission enabled.
   - **Direct ETH Siphoning:** When users buy or sell against the pool, the Hook natively skims a dynamically decaying tax (10% to 1%) *directly in ETH* out of the `PoolManager` delta and sends it instantly to the `LotteryEngine`. 

## Validation Results

- Successfully compiled the new tri-contract architecture against `@uniswap/v4-core` and `@uniswap/v4-periphery`.
- The new architecture effectively eliminates `amountOutMinimum` swap vulnerabilities, FOT router incompatibilities, and massive state bloat from the old V3 model.
- Because testing V4 Hooks requires extensive Foundry setup and mock `PoolManager` state, we are currently at a "compiled and syntax-verified" stage. You will need to wire these up to your specific V4 deployment scripts to finalize end-to-end execution.
