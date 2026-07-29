# V22 Final Audit Report — Superseded

> **Verdict withdrawn for current release use.** V23 review found an unwired per-node Fenwick opening capture that could distort same-block pre-start odds. The finding is fixed and re-audited in `V23_FINAL_AUDIT_REPORT.md`.

## Release-candidate verdict

**Historical V22 result only** for the previously scoped requirements at audited implementation commit:

```text
6b40c24d5f30d9bef0d347d6c5ec58fa3b879f98
```

The report itself is a documentation-only follow-up commit. No source changed after the clean test run or audited implementation commit.

## Toolchain and dependencies

- Forge: `1.7.1` (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`)
- Solidity compiler: `0.8.26+commit.8a97fa7a`
- EVM target: Cancun; optimizer enabled with 200 runs; IR enabled
- `v4-core`: tag `v4.0.0`, commit `e50237c43811bd9b526eff40f26772152a42daba`
- `v4-periphery`: commit `3245c3cb99c48fa1dc2459c3b60abc37d4294aba`
- OpenZeppelin: commit `5fd1781b1454fd1ef8e722282f86f9293cacf256`
- forge-std: tag `v1.16.2`, commit `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`

Foundry git submodules are the sole Uniswap v4 source. The incompatible npm v4 packages were removed; a clean `npm ci` installs neither package.

## Commands and results

| Command | Result | Evidence |
|---|---:|---|
| `forge build` | PASS | `test_logs/forge_build.log` |
| `forge test -vvv --gas-report` | 174 passed, 0 failed, 0 skipped | `test_logs/forge_test.log` |
| `forge test --match-path 'test/v18/*.sol' -vvv --gas-report` | 12/12 passed | `test_logs/v18_tests.log` |
| `forge test --match-path 'test/v20/*.sol' -vvv --gas-report` | 6/6 passed | `test_logs/v20_tests.log` |
| `forge test --match-path 'test/v21/*.sol' -vvv --gas-report` | 7/7 passed | `test_logs/v21_tests.log` |
| `forge test --match-path 'test/v22/*.sol' -vvv --gas-report` | 26/26 passed | `test_logs/v22_tests.log` |
| `forge test --match-contract DeepSimulation -vvv --gas-report` | 1/1 passed | `test_logs/deep_simulation.log` |
| `forge test --match-path 'test/**/*Hook*.sol' -vvv --gas-report` | 59/59 passed | `test_logs/hook_tests.log` |
| `forge fmt --check` | PASS | final verification |

No test was skipped or left unverified.

## Fixed issues

1. `LotteryEngine._findWinner` resolves Fenwick indices exclusively through `getHolderByEligibleIndexAtRound(index, roundId)`.
2. Same-block exit, index reuse, and re-entry resolve the block-opening holder without burning attempts; a negative guard demonstrates the old live lookup failure.
3. Failed dev payments create aggregate and per-receiver debt. Claims and permissionless retries use `MANUAL_PAYOUT_GAS` and restore debt exactly on failure.
4. Dev debt remains assigned to the receiver snapshotted for its round; later receiver changes cannot redirect it.
5. Free balance reserves active prizes, pending winner debt, and pending dev debt.
6. Winner automatic retries remain bounded and non-blocking. Manual retries use the larger stipend. Queue-count bookkeeping now clears at the retry cap.
7. Failed action rewards create no debt; rewards are attempted only after fulfillment, and expired rounds pay none.
8. Contract-wallet policy is evaluated after round-owner resolution, preserving ghost cleanup and allowing approved contracts to win. Removal refreshes eligibility.
9. Token, engine, and hook settings share the permanent freeze while permissionless execution and recovery remain available.
10. Uniswap v4 source/API selection is reproducibly pinned to the declared Foundry submodules.

## Manual audit conclusions

- Round Fenwick values and index ownership use the same active-round boundary.
- No winner payout path uses the live holder mapping.
- Winner and dev liabilities follow checks-effects-interactions under `nonReentrant`; failures cannot erase or reuse debt.
- Pools, official routers/managers, and taxed external pools cannot enter the contract-wallet allowlist.
- Normal contracts remain blocked unless manually allowed; allowlist removal invokes eligibility refresh.
- EIP-7702 delegated EOAs are intentionally eligible.
- Every owner configuration entry point in token, engine, and hook is blocked after the irreversible freeze. Round start/trigger/pay/expiry, refresh, and payout recovery are unaffected.
- Active documentation and regenerated logs match the audited source. Grep hits retained in older session/design documents are historical, not current status claims.

## Unresolved accepted risks

- Fixed-future-blockhash randomness remains proposer/sequencer-influenceable and operationally dependent on the blockhash window. This is suitable only for the disclosed capped MVP, not high-value production.
- Administration is centralized until `freezeSettingsForever()` is executed.
- EIP-7702 delegated code can change or reject ETH; failed winner payouts can remain reserved indefinitely.
- A permanently rejecting winner or dev receiver creates an indefinitely locked liability.

## Remaining non-blocking notes

- The clean build emits lint/compiler warnings in tests and for timestamp-dependent protocol logic; no compilation error or failing test exists.
- `npm ci` reports vulnerabilities in legacy JavaScript tooling dependencies. Solidity compilation uses pinned Foundry submodules, but the JavaScript dependency tree should be separately upgraded before using Hardhat tooling in a sensitive environment.
- Historical documents under earlier session/phase directories describe superseded architectures and are not release evidence.
