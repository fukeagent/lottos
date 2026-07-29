# Epoch & Adversarial Test Plan

## Goal Description
This plan addresses the outstanding tasks requested by the user: adding zero-address checks to the constructor, replacing the pre-launch test to use the official pool setup, renaming the partial-fill test to clarify its behavior, and expanding explicit tests for the deterministic epoch-based timing logic. 

## User Review Required
No breaking changes or significant architectural shifts are introduced. The test structure in `V4LotteryHookIntegration.t.sol` will be refactored to move `token.activateTrading()` out of `setUp()` and into individual tests. This enables a true pre-launch test against the officially initialized pool.

## Proposed Changes

### `contracts/LotteryEngine.sol`
Add explicit nonzero checks in the constructor for the critical addresses (`_token` and `_devWallet`).

```diff
     constructor(address _token, address _devWallet) Ownable(msg.sender) {
+        require(_token != address(0), "Zero token address");
+        require(_devWallet != address(0), "Zero dev wallet");
         token = IRobinhoodToken(_token);
         devWallet = _devWallet;
         lotteryGenesisBlock = block.number;
     }
```

### `test/V4LotteryHookIntegration.t.sol`
Refactor the setup phase to allow testing the pre-launch behavior natively on the main pool, and introduce comprehensive epoch timeline validation tests.

#### [MODIFY] test/V4LotteryHookIntegration.t.sol
1. **Remove `activateTrading()` from `setUp()`**:
   - `token.activateTrading()` will be removed from `setUp()`.
   - Every existing test (except the pre-launch test) will have `token.activateTrading()` added as its first step.
2. **Rewrite `test_AdversarialPreLaunch`**:
   - Remove the `token3` and `preLaunchKey` scaffolding.
   - Use the official `key` and attempt a swap directly after setup (before trading is active).
   - Assert that the swap reverts correctly.
3. **Rename `test_AdversarialPartialFill`**:
   - Rename to `test_PriceLimitRevertDoesNotLeakTax` to clarify that since the hook taxes on the exact input, partial fills hitting a limit should revert the transaction entirely to prevent unfair taxation.
4. **Add Explicit Epoch Timeline Tests**:
   - `test_EpochBeforeWindowReverts()`: Roll block to `epochSnapshotBlock` but before the trigger window; assert `triggerLottery` reverts with "Trigger window missed or pending".
   - `test_EpochInsideWindowSucceeds()`: Roll to `epochRandomnessBlock`; assert `triggerLottery` succeeds.
   - `test_EpochAfterMissedWindowReverts()`: Roll to `epochRandomnessBlock + TRIGGER_WINDOW_BLOCKS + 1`; assert `triggerLottery` reverts.
   - `test_EpochSameEpochCannotTriggerTwice()`: Trigger successfully, attempt to trigger again; assert revert.
   - `test_EpochNextEpochCanTrigger()`: Trigger successfully, warp/roll to the *next* epoch's randomness block; assert trigger succeeds again.

### `test/RobinhoodToken.t.sol`
Fix the currently failing `test_TransferUpdatesCheckpoints` to ensure `getPastBalance` is tested securely and reliably without block number offset misalignment.

## Verification Plan

### Automated Tests
```bash
forge test -vvv --gas-report | tee test_logs/forge_test.log
```
The logs will confirm the execution of the new epoch tests, the adversarial configurations, and a successful test matrix. Once verified and fully matched with the real tests, `TEST_RESUME.md` will be updated to reflect the new state.
