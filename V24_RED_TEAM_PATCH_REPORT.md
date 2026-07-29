# V24 Red-Team Patch Report

> Superseded by `V25_FINAL_HARDENING_REPORT.md`. V24 counts do not describe the strict live-forfeiture implementation.

## Verdict

**PASS.** Audited implementation commit: `8329b2a3e7134f67f3cc90eac6cbd16e6a573b6b`.

## Provenance

- Forge: `1.7.1`; solc: `0.8.26+commit.8a97fa7a`; Cancun, optimizer 200, `via_ir = true`.
- `v4-core`: `e50237c43811bd9b526eff40f26772152a42daba` (v4.0.0); `v4-periphery`: `3245c3cb99c48fa1dc2459c3b60abc37d4294aba`; OpenZeppelin: `5fd1781b1454fd1ef8e722282f86f9293cacf256`; forge-std: `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`.
- Foundry is the audited deployment path. Hardhat now matches solc, Cancun, optimizer runs, and `viaIR`; it is not the production artifact authority.

## Commands and results

After `forge clean` and recreation of `test_logs/`, the following all passed:

- `forge build` and `forge test -vvv --gas-report`: **191 passed, 0 failed, 0 skipped**.
- Focused v18/v20/v21/v22/v23/v24 suites: 12/6/7/26/3/14 passed respectively.
- Hook-path suite: 60 passed. `DeepSimulation`: 1 passed.

Logs are under `test_logs/`.

## Fixed findings

- Auto-swap remains optional and defaults off. A ready, non-zero quote derives `minEthOut`; router calldata and post-swap engine balance use that identical floor. Quote/output failures are caught, retaining tax tokens and preserving the taxed transfer. Tests cover unavailable/zero quotes, below-floor adversarial output, within-floor execution, cap/cooldown, and manual minimum output.
- External taxed pools must be token-containing V2-like or V3-like pools. EOAs, arbitrary contracts, official paths, allowlisted wallets, token, and engine are rejected.
- `LotteryHook` uses two-step ownership. Renunciation requires official-pool binding and permanent token settings freeze.
- Tax skims checkpoint `address(this)` with same-block overwrite semantics.
- `roundDuration` is owner-configurable from 10 minutes to 24 hours when no round is pending; it is immutable after freeze. Randomness delay remains block-based.

## Audit notes and accepted risks

Round-aware holder resolution, block-opening Fenwick capture ordering, payout liabilities, eligibility policy, and permanent-freeze behavior were rechecked through source review and their V22/V23 regressions. The official quote remains spot-price/MEV-visible, so slippage, `maxSwapAmount`, and cooldown bound rather than eliminate economic extraction; larger sweeps should use an explicit keeper/private-relay swap. Future-blockhash randomness remains MVP-grade and administration remains centralized until permanent freeze.
