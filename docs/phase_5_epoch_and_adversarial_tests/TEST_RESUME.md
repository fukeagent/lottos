# V4 Test Environment Report

## Overview
A comprehensive test suite was written and executed to validate the core architecture components: `RobinhoodToken`, `LotteryEngine`, and `LotteryHook`.

The tests have been successfully executed using Foundry, and all logs/gas reports have been saved in the `test_logs/` folder of your project root.

## V4 Local Architecture Proof (Phase 4 & 5)

We successfully developed and executed a comprehensive local proof for the new Uniswap v4 lottery architecture. The updated system shifts the lottery trigger from caller-chosen timing to deterministic epoch-based timing, pays out winners directly in native ETH without requiring separate claims, and correctly taxes all four swap permutations.

### V4 E2E Test Suite Results

The `V4LotteryHookIntegration.t.sol` suite contains robust coverage for the entire lottery lifecycle and adversarial conditions.

| Test Case | Description | Result |
| :--- | :--- | :--- |
| `test_ExactInputETHBuy` | Exact ETH in for Token | **PASS** |
| `test_ExactInputTokenSell` | Exact Token in for ETH | **PASS** |
| `test_ExactOutputETHSell` | Exact ETH out for Token | **PASS** |
| `test_ExactOutputTokenBuy` | Exact Token out for ETH | **PASS** |
| `test_AdversarialWrongPool` | Swap on non-official pool bypasses tax | **PASS** |
| `test_AdversarialPreLaunch` | Swaps before token trading is active revert | **PASS** |
| `test_PriceLimitRevertDoesNotLeakTax` | Swaps that hit limits still follow exact-input limits safely and do not leak tax | **PASS** |
| `test_EndToEndLotteryLifecycle` | Full cycle: user swap -> warp to epoch -> trigger -> claim verification | **PASS** |
| `test_EpochBeforeWindowReverts` | Triggering before the deterministic window reverts | **PASS** |
| `test_EpochInsideWindowSucceeds` | Triggering inside the exact block window succeeds | **PASS** |
| `test_EpochAfterMissedWindowReverts` | Triggering after missing the trigger window correctly expires the epoch | **PASS** |
| `test_EpochSameEpochCannotTriggerTwice` | Attempting to trigger an active epoch again reverts | **PASS** |
| `test_EpochNextEpochCanTrigger` | After finalizing an epoch, the engine correctly opens the next epoch | **PASS** |

### Key Improvements Confirmed
1. **Epoch Timing**: Block timing logic successfully uses `currentEpochId` and `epochRandomnessBlock`. Time manipulation tests confirmed that the lottery can only trigger inside the designated block window, and expires outside of it.
2. **Direct Payouts**: The End-to-End lifecycle verified that the winning EOAs receive direct native ETH payments upon finalization without the previous claim step.
3. **Exact Tax Assertions**: Utilizing V4 `BalanceDelta`, all 4 combinations of ZeroForOne and ExactInput/ExactOutput swaps rigorously verify that `10%` of the net ETH flow is precisely sent to the LotteryEngine.
4. **Adversarial Resilience**: Pool hijacking, pre-launch swaps, price limit abuse, and epoch abuse vectors have all been patched and verified to be safe.
