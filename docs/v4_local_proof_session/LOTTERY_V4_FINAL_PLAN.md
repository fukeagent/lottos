## Goal Description
The current Uniswap V4 hook implementation utilizes `afterSwapReturnDelta` exclusively, which successfully intercepts ETH when it acts as the "unspecified" currency in a swap (e.g., exact-input RHT sells). However, it completely bypasses swaps where ETH is the "specified" currency (e.g., exact-input ETH buys).

To create a **Universal Buy/Sell Tax**, the hook must intercept ETH across all swap paths. Furthermore, we need to solidify the pool association to prevent malicious overrides, validate constructor arguments, and perfectly synchronize the Hook's trading launch with the Token's launch.

## Proposed Changes

### 1. Universal Hook Fee Logic (LotteryHook.sol)
We will expand the Hook to utilize both `beforeSwap` (to take cuts of specified ETH input) and `afterSwap` (to take cuts of unspecified ETH output).

- **Permissions Update**:
  - `beforeSwap: true`
  - `beforeSwapReturnDelta: true`
  - `afterSwap: true`
  - `afterSwapReturnDelta: true`

- **Fee Logic**:
  - **`beforeSwap`**: If the user is swapping exact ETH in, the Hook skims the dynamically decayed tax from the ETH delta *before* the pool sees it. It returns a `BeforeSwapDelta` to instruct the PoolManager to reduce the liquidity curve's input.
  - **`afterSwap`**: If the user is swapping for exact RHT (unspecified ETH input) or swapping exact RHT (unspecified ETH output), the hook assesses the ETH delta *after* the swap and returns an `afterSwapReturnDelta`.
  - Both hooks immediately funnel the taken ETH into `LotteryEngine`.

### 2. Constructor & Official Pool Hardening
- **Constructor Validation**:
  ```solidity
  require(_lotteryEngine != address(0), "Invalid engine");
  require(Currency.unwrap(_ethCurrency) == address(0), "Expected native ETH");
  ```
- **`setOfficialPool` One-Time Lock**:
  ```solidity
  require(PoolId.unwrap(officialPoolId) == bytes32(0), "Pool already set");
  require(
      Currency.unwrap(key.currency0) == Currency.unwrap(ethCurrency) ||
      Currency.unwrap(key.currency1) == Currency.unwrap(ethCurrency),
      "Pool must include ETH"
  );
  officialPoolId = key.toId();
  ```

### 3. Unified Activation State
The Hook will discard its own isolated `tradingActivatedAt` state. Instead, it will interface directly with the Token.

- **Hook Logic**:
  ```solidity
  function getCurrentTaxBps() public view returns (uint256) {
      uint256 activatedAt = token.tradingActivatedAt();
      require(activatedAt > 0, "Trading not active");
      uint256 elapsed = block.timestamp - activatedAt;
      // ... decay logic ...
  }
  ```
This guarantees an atomic launch: when the owner calls `activateTrading()` on the Token, the Hook is instantly armed and synchronized.

## User Review Required
> [!IMPORTANT]
> **CREATE2 Address Mining:** Because the hook now requires four permission flags (`beforeSwap`, `afterSwap`, `beforeSwapReturnDelta`, `afterSwapReturnDelta`), the `address` of the deployed hook must correctly bitwise-encode these flags as prefixes (per Uniswap V4 specifications). Your deployment script MUST use `CREATE2` vanity mining (e.g., via Foundry's `Mine.sol`) to find a valid address.

> [!WARNING]
> **V4 Fuzz Testing:** Manually constructing `BeforeSwapDelta` and `AfterSwapReturnDelta` in `int128` format across all four AMM swap quadrants (exact-in buy, exact-out buy, exact-in sell, exact-out sell) is extremely sensitive. You must execute rigorous Foundry fork tests against a live or mock `PoolManager` before interacting with real funds.

## Verification Plan

### Automated Tests
1. Develop Foundry tests for `PoolManager.swap()`.
2. **Path A (Exact-Input ETH Buy)**: Verify `beforeSwap` extracts tax in ETH.
3. **Path B (Exact-Input RHT Sell)**: Verify `afterSwap` extracts tax in ETH.
4. **Path C (Exact-Output ETH Buy)**: Verify `afterSwap` extracts tax in ETH.
5. **Path D (Exact-Output RHT Sell)**: Verify `beforeSwap` (or `afterSwap`) extracts tax in ETH.
6. Confirm `LotteryEngine` receives the exact ETH tax across all 4 permutations.
