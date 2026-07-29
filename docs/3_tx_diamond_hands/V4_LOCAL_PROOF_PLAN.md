# V4 Local Proof Completion Plan

## Goal Description
The objective is to finalize the V4 local proof by adding exact tax assertions for all swap paths, implementing adversarial tests for the Hook, completing the local deployment script (wiring, liquidity, trading activation), and creating a full end-to-end lottery flow test.

## Proposed Changes

### Script Updates
#### [MODIFY] `script/DeployLocalV4.s.sol`
Update the deployment script to not just deploy the contracts, but completely initialize the environment:
1. Approve PoolManager to spend RobinhoodToken.
2. Initialize the Uniswap V4 pool (`manager.initialize(key, STARTING_PRICE)`).
3. Set appropriate limits and exemptions in `RobinhoodToken` so the manager can hold liquidity.
4. Add initial liquidity to the pool using a deployed/mocked `PoolModifyLiquidityTest` or similar router.
5. Set `engine.setLotteryHook` and wire all relationships (hook to official pool, token to engine).
6. Call `token.activateTrading()` to make the system live.

### Test Updates
#### [MODIFY] `test/V4LotteryHookIntegration.t.sol`
1. **Exact Tax Assertions**:
   - Update `test_ExactOutputTokenBuy` and `test_ExactInputTokenSell` to dynamically calculate the expected tax. 
   - We will retrieve the exact ETH delta from the `BalanceDelta` returned by `swapRouter.swap()` and assert that the tax transferred to the `LotteryEngine` is strictly `(ethDelta * 1000) / 10000` (or `10%` depending on tax bps).

2. **End-to-End Test**:
   - Create `test_EndToEndLotteryLifecycle()`.
   - Perform a swap to generate a prize pool > `MIN_LOTTERY_BALANCE`.
   - Warp time past `LOTTERY_COOLDOWN`.
   - Trigger the lottery via `engine.triggerLottery()`.
   - Fulfill the lottery (simulating VRF) using `engine.finalizeLottery(roundId)`.
   - Verify the winner receives the prize minus the dev fee.

3. **Adversarial Tests**:
   - `test_RevertIfWrongPool`: Try swapping on a pool with a different token but the same hook, expect revert.
   - `test_RevertIfTradingNotActive`: Try swapping before `token.activateTrading()` is called, expect revert.
   - `test_ZeroBalanceHook`: Ensure hook `balance` is strictly `0` after partial fills or complex exact-output routes to guarantee no ETH is left stranded in the hook.

## Verification Plan

### Automated Tests
```bash
forge test --match-contract V4LotteryHookIntegrationTest -vvv
```
All new adversarial tests and exact tax assertions must pass.

### Script Verification
```bash
forge script script/DeployLocalV4.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <ANVIL_PRIVATE_KEY>
```
The script must successfully execute on a local Anvil node without reverting during the liquidity addition or pool initialization phases.
