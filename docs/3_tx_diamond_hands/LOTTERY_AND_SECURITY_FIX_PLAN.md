## Goal Description
This plan addresses the final medium/critical issues in the `RobinhoodLotteryToken` contract:
1. **Live Fenwick Tree Usage during Finalize (Critical):** Prevents the lottery from using live arrays that may have shifted since the snapshot.
2. **Zero Slippage Swap (Critical):** Removes the sandwichable auto-swap and replaces it with a manual keeper-protected swap function.
3. **WETH Withdraw Revert (Medium):** Protects the tax swap mechanism from unhandled `withdraw` reverts.
4. **V3 Pool Permissions (Medium):** Locks the `setV3Pool` function once trading is activated.
5. **Hardcoded Fenwick Tree Loops (Medium):** Dynamically calculates the minimum eligible Fenwick tree instead of hardcoding `70`.

## Proposed Changes

---
### 1. Snapshotting Holder Order (Append-Only Arrays)
To allow O(1) freezing of holder order without copying massive arrays, we will convert `Fenwick treeHolders` to **append-only arrays**. Users will be added to a Fenwick tree's array at most once in their lifetime (tracked via a mapping). Since elements are never removed or shifted, snapshotting the `length` of the array perfectly freezes the candidate pool for a given round.

#### [MODIFY] `RobinhoodLotteryToken.sol`
*   Add `mapping(address => mapping(uint8 => bool)) public inFenwick TreeArray;`
*   Add `uint256[256] snapshotFenwick TreeLengths;` to the `Round` struct.
*   Update `_updateEligibility()` to use append-only logic:
```solidity
// Instead of swap-and-pop:
if (newFenwick Tree != 0) {
    if (!inFenwick TreeArray[account][newFenwick Tree]) {
        Fenwick treeHolders[newFenwick Tree].push(account);
        inFenwick TreeArray[account][newFenwick Tree] = true;
    }
}
```
*   Update `triggerLottery()` to snapshot lengths:
```solidity
uint8 minFenwick Tree = minEligibleFenwick Tree();
for (uint8 i = minFenwick Tree; i < 255; i++) {
    if (Fenwick treeTotalBalance[i] > 0) {
        rounds[nextRoundId].snapshotFenwick TreeTotals[i] = Fenwick treeTotalBalance[i];
        rounds[nextRoundId].snapshotFenwick TreeLengths[i] = Fenwick treeHolders[i].length;
    }
}
```
*   Update `finalizeLottery()` to use the snapshotted lengths for selection:
```solidity
uint256 frozenLength = r.snapshotFenwick TreeLengths[winningFenwick Tree];
if (frozenLength == 0) continue;

uint256 candidateIndex = currentSeed % frozenLength;
address candidate = Fenwick treeHolders[winningFenwick Tree][candidateIndex];
```

---
### 2. Manual Protected Tax Swaps
Auto-swapping with zero slippage is highly vulnerable to sandwiches. We will remove the auto-swap from `_update` and transition exclusively to manual keeper swaps.

#### [MODIFY] `RobinhoodLotteryToken.sol`
*   Remove auto-swap block from `_update()`.
*   Replace `manualSwapTaxes` with:
```solidity
function manualSwapTaxes(uint256 tokenAmount, uint256 amountOutMinimum) external onlyOwner {
    require(balanceOf(address(this)) >= tokenAmount, "Insufficient tokens");
    swapTokensForEth(tokenAmount, amountOutMinimum);
}
```

---
### 3. WETH Withdraw Safe Catch
`IWETH9(WETH).withdraw()` can revert outside the router's try/catch block if the contract doesn't have the expected balance (e.g. if the swap returns less WETH than expected or the router behaves maliciously). 

#### [MODIFY] `RobinhoodLotteryToken.sol`
*   Wrap the `withdraw` in a low-level call:
```solidity
try v3SwapRouter.exactInputSingle(params) returns (uint256 amountOut) {
    (bool success, ) = WETH.call(abi.encodeWithSignature("withdraw(uint256)", amountOut));
    if (success) {
        emit TaxesSwapped(tokenAmount, address(this).balance - initialBal);
    }
} catch {}
```

---
### 4. V3 Pool Immutable Post-Launch
We will restrict `setV3Pool` so it can only be updated before trading is activated.

#### [MODIFY] `RobinhoodLotteryToken.sol`
```solidity
event V3PoolUpdated(address indexed oldPool, address indexed newPool);

function setV3Pool(address _pool) external onlyOwner {
    require(tradingActivatedAt == 0, "Pool locked after activation");
    emit V3PoolUpdated(uniswapV3Pool, _pool);
    uniswapV3Pool = _pool;
}
```

---
### 5. Dynamic Minimum Fenwick Tree
Instead of hardcoding loop iterators to `70`, we will dynamically calculate it.

#### [MODIFY] `RobinhoodLotteryToken.sol`
```solidity
function minEligibleFenwick Tree() public view returns (uint8) {
    uint256 minBal = (totalSupply() * ELIGIBILITY_BPS) / 10000;
    return msb(minBal);
}
```
*   Apply `minEligibleFenwick Tree()` to loops in `triggerLottery` and `finalizeLottery` (if necessary, though `finalizeLottery` doesn't loop Fenwick trees, only `triggerLottery` and `_selectFenwick Tree` do).

## Verification Plan
1. **Automated Tests:** Execute `npx hardhat test` to ensure these new constraints pass the existing security checks. Add explicit tests for append-only array integrity (simulate users moving Fenwick trees) and manual swap slippage checks.
2. **Manual Verification:** Confirm that `manualSwapTaxes` works correctly locally via `hardhat node` simulation.
