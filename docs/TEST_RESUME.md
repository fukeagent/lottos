# V25 Test Resume

## Verified status

The authoritative V25 full run is `test_logs/forge_test.log`: 211 passed, 0 failed, 0 skipped. Exact toolchain and focused-suite counts are recorded in `V25_FINAL_HARDENING_REPORT.md`.

## Current behavior

- `_treeUpdate` captures every Fenwick node's block-opening value before active-round freeze and before current-value mutation.
- Same-block pre-start and post-start top-ups change live weight but cannot change the active round's opening odds. Multi-holder tests prove Bob retains the original `[100, 200)` range after Alice tops up.
- `activeSnapshotTotalWeight` and `treeFindByCumulativeAtRound` now share the same block-opening model. The old one-holder fuzz is retained only as a total-weight check; V23 adds meaningful deterministic and fuzzed multi-holder routing tests.
- Block-opening eligible-index ownership remains frozen for each active round.
- Winner resolution uses `getHolderByEligibleIndexAtRound(index, roundId)`, never the live holder mapping.
- Start weights remain fixed. A sender that dips below their start balance before trigger permanently forfeits their full start weight; buying more cannot add weight and rebuying cannot restore forfeited weight.
- `LotteryEngine` samples a round-tagged residual Fenwick tree. Zero residual weight expires immediately, while 90% and 99.9% exclusion tests still settle in one attempt.
- Failed winner payouts are reserved in `pendingWinnerPayout`; automatic queue retries use `AUTO_PAYOUT_GAS` (50,000), are bounded to three failures, and never brick hook/token execution.
- Manual winner and dev retries use `MANUAL_PAYOUT_GAS` (300,000).
- Failed dev payouts are reserved per snapshotted receiver in `pendingDevPayout`; changing `devFeeReceiver` cannot redirect existing debt.
- `availableLotteryBalance()` excludes `reservedPrizePool`, `totalPendingWinnerPayouts`, and `totalPendingDevPayouts`.
- Action rewards are best effort, create no debt, and are attempted only on fulfilled rounds. Expired rounds pay none.
- Contract wallets are blocked unless explicitly allowed; pools, routers/managers, and taxed pools cannot be allowed. Removal immediately refreshes eligibility.
- EIP-7702 delegated EOAs are intentionally eligible. Their delegated code may reject payout, in which case winner debt is preserved.
- `freezeSettingsForever()` permanently blocks settings across token, engine, and hook while leaving permissionless execution and recovery enabled.
- Deployment and integration setup marks PoolManager official tax-exempt before `activateTrading()`.
- Auto-swap is disabled by default; if enabled, an official quote must be ready and non-zero, and the router plus post-balance check enforce the same slippage floor. Unsafe execution skips without reverting the taxed transfer.
- Taxed external pools must be validated V2-like or V3-like pools containing this token. Hook ownership is two-step and can be renounced only after permanent freeze and official-pool binding.
- Tax skims checkpoint `address(this)`. `roundDuration` is mutable from 10 minutes through 24 hours only before freeze and without a pending round.
- Permissionless `sweepTaxTokens` works after freeze with an internally computed quote floor; caller input can only tighten it. Failed automatic attempts start cooldown without blocking the user transfer.

## Resume commands

```bash
forge fmt --check
forge build --sizes
forge test -vvv --gas-report
```

Do not rely on older reports or generated artifacts. Recreate `test_logs/` after any source change.
