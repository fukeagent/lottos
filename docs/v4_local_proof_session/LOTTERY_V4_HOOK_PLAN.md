## Goal Description
The current implementation of the Robinhood Lottery Token relies on an ERC20 "fee-on-transfer" (FOT) mechanism combined with Uniswap V3. As identified, Uniswap V3 does not natively support fee-on-transfer tokens gracefully, leading to complex exemptions, manual swap triggering, and potential routing reversions. 

The goal of this rebuild is to upgrade the architecture to **Uniswap V4**. By leveraging V4 Hooks, we can completely strip the tax logic out of the ERC20 token and place it directly into the AMM liquidity pool. This guarantees 100% router compatibility, seamless dynamic fees, and zero friction for standard wallet-to-wallet transfers.

## User Feedback Addressed
1. **No Chainlink VRF:** The target ecosystem ("Robinhood") does not support Chainlink VRF. The lottery will continue to use the hardened, fixed-future blockhash model we recently perfected.
2. **Direct ETH Tax Collection:** Instead of taking tax in RHT and manually swapping it to ETH, the V4 Hook will be designed to **exclusively siphon ETH** during swaps. On buys (ETH -> RHT), it takes a cut of the input ETH. On sells (RHT -> ETH), it takes a cut of the output ETH. The Lottery Pool is funded directly in native ETH instantly.

## Proposed Changes

---

### Phase 1: The Base Token (RobinhoodToken.sol)
We will completely gut the FOT logic. The token becomes highly gas efficient.

**Features:**
- Standard ERC20.
- `_update` logic maintains the historical `Checkpoints` arrays for lottery snapshots.
- `_update` logic enforces the dynamic `getMaxWallet()` rules.
- **NO** tax logic, no `inSwap`, no `isExempt` arrays.

#### [MODIFY] `RobinhoodLotteryToken.sol` -> `RobinhoodToken.sol`
*Diff summary:*
```diff
- function isExempt(address account) public view returns (bool)
- bool inSwap;
- uint256 public swapTokensAtAmount;
- function manualSwapTaxes() external
... (Entire tax block removed) ...
```

---

### Phase 2: The Uniswap V4 Hook (LotteryHook.sol)
This is a standard V4 `BaseHook` that attaches to the ETH/RHT pool.

**Features:**
- Implements the `afterSwap` hook.
- Implements a dynamic fee that replicates the `TAX_DECAY_DURATION` (Starts at 10%, decays to minimum over 30 minutes).
- **Direct ETH Collection:** By calculating the tax against the ETH delta of the swap (whether it's the input or the output), the Hook natively collects ETH and transfers it directly to the `LotteryEngine`.

#### [NEW] `LotteryHook.sol`
*Snippet:*
```solidity
import {BaseHook} from "v4-periphery/BaseHook.sol";

contract LotteryHook is BaseHook {
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false, 
            afterSwap: true, // Intercept after swap to take ETH cut
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true, // Allow Hook to modify deltas
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external override returns (bytes4, int128) {
        
        // 1. Calculate dynamic tax based on launch time
        // 2. Inspect the ETH delta (positive or negative depending on buy/sell)
        // 3. Extract the tax amount directly in ETH from the PoolManager
        // 4. Send the ETH directly to LotteryEngine
        
        return (BaseHook.afterSwap.selector, ethTaxDelta);
    }
}
```

---

### Phase 3: The Standalone Lottery Engine (LotteryEngine.sol)
Because the lottery is now isolated, it doesn't clutter the token. It receives pure ETH funding directly from the Hook.

**Features:**
- Retains the exact secure selection mechanics we just built (Append-only candidate arrays, continuation cursor, threshold pruning).
- Snapshots are pulled by reading `token.getPastBalance(user, block)`.
- Relies on the fixed-future blockhash model (No VRF).

#### [NEW] `LotteryEngine.sol`

## Verification Plan

### Automated Tests
1. Install Uniswap V4 Core and Periphery dependencies via Hardhat/Foundry.
2. Build a local V4 `PoolManager` fixture.
3. Test that normal P2P transfers cost zero tax and do not interact with the hook.
4. Test that swaps through the V4 PoolManager trigger the hook, properly assess the decayed tax.
5. **CRITICAL TEST:** Verify that both Buys and Sells result in the `LotteryEngine` receiving ETH, and the `RobinhoodToken` balance in the pool remains strictly balanced.
