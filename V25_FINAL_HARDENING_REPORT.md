# V25 Final Hardening Report

## Verdict

**PASS.** The clean Foundry build and full suite completed with 211 passed, 0 failed, and 0 skipped. The new strict no-dip and residual-sampling regressions pass, and production runtime sizes remain below EIP-170.

Audited implementation and evidence commit: `d93de423c409400f7f9594d95ff781c1b52b3e72`.

## Toolchain and provenance

- Forge: 1.7.1 (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`)
- Forge-selected solc: 0.8.26; Cancun, optimizer 200, `via_ir = true`
- `v4-core`: `e50237c43811bd9b526eff40f26772152a42daba` (`v4.0.0`)
- `v4-periphery`: `3245c3cb99c48fa1dc2459c3b60abc37d4294aba`
- OpenZeppelin: `5fd1781b1454fd1ef8e722282f86f9293cacf256`
- forge-std: `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b` (`v1.16.2`)
- Foundry/Forge artifacts are the only audited production artifacts. Hardhat has no live network deployment configuration.
- Runtime sizes: `RobinhoodToken` 23,404 bytes; `LotteryEngine` 19,797 bytes.

## Implementation audit

The token opens a dedicated forfeiture phase at epoch start and closes it at trigger. After the complete transfer and checkpoints, only the sender is checked. A post-transfer balance below the start snapshot causes the engine to exclude the index's full round-start weight exactly once. Buying more never increases current-round weight; dip-and-rebuy never restores it; transfers after trigger cannot forfeit.

The immutable block-opening snapshot remains authoritative. The engine maintains a round-tagged exclusion Fenwick overlay and samples `snapshotNode - forfeitedNode` against `roundRemainingWeight`. Round-aware holder lookup prevents live-index reuse mismatches. Permanent fallback validation failures are excluded; payout failures are not. Zero remaining weight expires cleanly and releases the reserved prize.

Renounce on token, engine, and hook is freeze-gated. Permissionless tax sweep remains callable after freeze, applies `max(computedMinOut, callerMinEthOut)`, and respects amount/cooldown limits. Failed automatic swaps preserve the user transfer and start attempt cooldown. Pending winner/dev liabilities and best-effort action-reward policy are unchanged.

## Verification

Commands and results:

- `forge build --sizes`: PASS.
- `forge test -vvv --gas-report`: 211 passed, 0 failed, 0 skipped.
- V18: 12 passed; V20: 6; V21: 7; V22: 26; V23: 3; V24: 14; V25: 20.
- Hook-path suites: 60 passed.
- `DeepSimulation`: 1 passed.
- `test/audit/*.sol`: not present; no audit suite was claimed or skipped. Audit coverage resides in versioned and integration suites.

Authoritative logs are in `test_logs/`.

## Gas impact

Measured V25 scenarios: no-active-round transfer 247,994 gas; active-round sender absent from snapshot 296,391; snapshot sender remaining above start 308,617; first forfeiture 889,784; repeated post-forfeiture transfer 317,805. Ten forfeitures used 7,294,813 gas and fifty used 30,600,592 across separate simulated holder calls. Both 90% and 99.9% forfeiture cases settled in one winner-selection attempt; `payLottery` averaged about 586k gas in the focused report.

The first forfeiture is intentionally expensive because it writes an O(log N) exclusion path. It does not create a keeper retry storm, and ordinary transfers do not write the exclusion overlay.

## Accepted risks

- Fixed-future-blockhash randomness is MVP-only. Proposer/sequencer influence and blockhash-window liveness remain accepted; prize caps are the fairness budget until VRF or equivalent.
- The official quote is a MEV-visible spot integration. Slippage, maximum swap size, and cooldown bound each automatic execution; private-relay/manual execution remains preferable for large sweeps.
- Action rewards remain best-effort and create no pending debt.
- This is a start-weighted lottery with live forfeiture for rule-breakers, not a live-balance lottery.
