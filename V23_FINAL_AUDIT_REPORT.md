# V23 Final Audit Report (Superseded by V24)

V24 changed auto-swap protection, external-pool classification, hook ownership, checkpoints, and timing. Consult `V24_RED_TEAM_PATCH_REPORT.md` for current evidence.

## Verdict

**PASS** for the scoped V23 release-candidate requirements at audited implementation commit:

```text
7b3a7d2a436ad62f47a9be4e7bbc045ffa85dd99
```

This report is a documentation-only follow-up. No Solidity, test, deployment, dependency, or evidence log changed after the audited commit.

## Toolchain and dependencies

- Forge: `1.7.1` (`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`)
- Solidity compiler: `0.8.26+commit.8a97fa7a`
- Cancun EVM; optimizer enabled with 200 runs; IR enabled
- `v4-core`: tag `v4.0.0`, commit `e50237c43811bd9b526eff40f26772152a42daba`
- `v4-periphery`: commit `3245c3cb99c48fa1dc2459c3b60abc37d4294aba`
- OpenZeppelin: commit `5fd1781b1454fd1ef8e722282f86f9293cacf256`
- forge-std: tag `v1.16.2`, commit `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`

## Commands and results

| Command | Result | Evidence |
|---|---:|---|
| `forge fmt --check` | PASS | final verification |
| `forge build` | PASS | `test_logs/forge_build.log` |
| `forge test -vvv --gas-report` | 177 passed, 0 failed, 0 skipped | `test_logs/forge_test.log` |
| `forge test --match-contract FenwickAndTaxTest -vvv --gas-report` | 49/49 passed | `test_logs/fenwick_gas_after_opening_capture.log` |
| `forge test --match-path 'test/v18/*.sol' -vvv --gas-report` | 12/12 passed | `test_logs/v18_tests.log` |
| `forge test --match-path 'test/v20/*.sol' -vvv --gas-report` | 6/6 passed | `test_logs/v20_tests.log` |
| `forge test --match-path 'test/v21/*.sol' -vvv --gas-report` | 7/7 passed | `test_logs/v21_tests.log` |
| `forge test --match-path 'test/v22/*.sol' -vvv --gas-report` | 26/26 passed | `test_logs/v22_tests.log` |
| `forge test --match-path 'test/v23/*.sol' -vvv --gas-report` | 3/3 passed | `test_logs/v23_tests.log` |
| `forge test --match-path 'test/**/*Hook*.sol' -vvv --gas-report` | 59/59 passed | `test_logs/hook_tests.log` |
| `forge test --match-contract DeepSimulation -vvv --gas-report` | 1/1 passed | `test_logs/deep_simulation.log` |

The required source/status greps were run and saved in `test_logs/stale_grep_review.log`. No suite or test was skipped or left unverified.

## Fixed finding and regression proof

The independent finding was valid. `_captureNodeOpeningIfNeeded` existed but was not called, allowing same-block pre-start mutations to alter per-node routing while total snapshot weight remained block-opening-based.

`_treeUpdate` is now the only `node.current` write path and enforces:

```text
_captureNodeOpeningIfNeeded(index)
_freezeNodeForActiveSnapshot(node)
node.current = next
```

The V23 suite proves:

1. With Alice/Bob opening at 100/100, Alice's same-block pre-start +100 top-up leaves snapshot total at 200 and live total at 300.
2. Target 50 resolves Alice and target 150 resolves Bob.
3. A 256-run two-holder fuzz selects targets exclusively from Bob's opening range and always resolves Bob despite Alice top-ups from 1 to 10,000 ether.
4. Alice's same-block post-start top-up likewise leaves target 150 assigned to Bob.
5. Existing same-block exit/index-reuse tests still resolve the block-opening holder.
6. `LotteryEngine._findWinner` still calls only `getHolderByEligibleIndexAtRound`.

The earlier one-holder fuzz could only prove total-weight preservation. It was renamed and narrowed; multi-holder V23 tests now prove odds routing.

## Gas impact

Compared with the same `test_GAS_V14_LazyFenwickTransfer` measurements in the committed V22 log:

| Scenario | V22 | V23 | Delta |
|---|---:|---:|---:|
| Idle standard transfer | 246,418 | 249,948 | +3,530 (+1.4%) |
| First mutation during active snapshot | 1,339,051 | 1,356,948 | +17,897 (+1.3%) |
| Subsequent active-snapshot mutation | 289,666 | 293,165 | +3,499 (+1.2%) |

The first mutation of each Fenwick node per block writes its opening value. This cost is accepted because removing it would restore the fairness defect.

## Manual audit conclusions

- Every Fenwick node mutation captures opening state before freeze, and freeze occurs before current mutation.
- `activeSnapshotTotalWeight` and `_nodeValueAtRound` now use one block-opening model for pre-start and post-start mutations.
- Round-aware index ownership remains intact during same-block exit/reuse.
- Winner/dev liability reservation, bounded retry behavior, contract-wallet policy, EIP-7702 behavior, and permanent settings freeze all pass their retained suites.
- Hook and deep integration compile and pass against the pinned v4 dependencies.
- Deployment, DeepSimulation, and primary hook integration mark PoolManager official tax-exempt before `activateTrading()`.
- Current docs withdraw V22 as current evidence and match V23 source/logs.

## Still-accepted risks

- Fixed-future-blockhash randomness remains proposer/sequencer-influenceable and operationally dependent on the blockhash window.
- Administration remains centralized until `freezeSettingsForever()` executes.
- EIP-7702 delegated code or a rejecting contract wallet can leave winner debt reserved indefinitely.
- A permanently rejecting dev receiver can leave dev debt reserved indefinitely.
- Fenwick opening capture adds storage-write gas to the first node mutation in each block.

## Non-blocking notes

- Build output contains compiler/lint warnings but no errors.
- Historical pre-V23 phase/session documents remain archival and are not current release evidence.
- JavaScript tooling dependencies are separate from the pinned Foundry compilation path and should continue to receive dependency maintenance.
