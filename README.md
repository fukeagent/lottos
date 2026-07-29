# V25 Lottery and Uniswap v4 Integration

This Foundry project implements `RobinhoodToken`, the three-transaction `LotteryEngine`, and a native-ETH Uniswap v4 tax hook. V25 adds strict live diamond-hands forfeiture, residual Fenwick sampling, and permissionless post-freeze tax sweeps.

## Reproducible setup

```bash
git submodule update --init --recursive
npm ci
forge build --sizes
forge test -vvv
```

Foundry is the canonical audited deployment path. Hardhat is configured to the same solc 0.8.26, Cancun, optimizer-200, and `viaIR` settings, but production deployments must use Forge artifacts. The contracts use the `IPoolManager.SwapParams` and `IPoolManager.ModifyLiquidityParams` API from the pinned `lib/v4-core` submodule:

- `v4-core`: tag `v4.0.0`, commit `e50237c43811bd9b526eff40f26772152a42daba`
- `v4-periphery`: commit `3245c3cb99c48fa1dc2459c3b60abc37d4294aba`
- OpenZeppelin: commit `5fd1781b1454fd1ef8e722282f86f9293cacf256`
- forge-std: tag `v1.16.2`, commit `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`

The incompatible npm v4 packages are intentionally not declared. `remappings.txt`, Git submodule pointers, and `foundry.lock` select the source compiled by Forge.

## Architecture and security

Every `_treeUpdate` captures each node's opening value before snapshot freeze and before mutating `node.current`. Consequently, both `activeSnapshotTotalWeight` and `treeFindByCumulativeAtRound` use the same block-opening model. A same-block pre-start or post-start top-up changes live weight but cannot crowd another holder out of the active round. Multi-holder deterministic and fuzz regressions enforce this boundary.

At round start, the token freezes eligible-index ownership and start weight. During `startLotteryEpoch` → `triggerDraw`, a sender whose post-transfer balance ever falls below their start balance permanently forfeits their full start weight. Buying more cannot increase current-round weight, and dip-and-rebuy cannot restore it. The engine samples the immutable start tree minus a round-tagged forfeiture overlay, so even 99.9% forfeiture does not cause retry grinding. Transfers after trigger do not affect the round.

`LotteryEngine` selects weight and holder through round-aware APIs and keeps end-snapshot validation as defense in depth. Failed winner payouts become bounded-queue debt; failed dev payouts remain debt to the receiver snapshotted for that round. `availableLotteryBalance()` excludes reserved prizes and both debt totals.

Contracts are ineligible unless explicitly allowed. Pools, official routers/managers, and taxed external pools cannot be allowed. EIP-7702 delegated EOAs remain eligible, but delegated payout code can reject ETH and create pending winner debt.

Owner settings remain centralized until `freezeSettingsForever()` is called. The freeze blocks token, engine, and hook configuration permanently, while permissionless round execution, expiry, eligibility refresh, and payout retries continue.

External taxed pools must be token-containing V2-like or V3-like pools; EOAs, routers, official paths, allowlisted wallets, the token, and engine are rejected. Auto-swap is disabled by default and, when enabled, uses a ready official-pool quote, a 3% default floor (bounded to 10%), `maxSwapAmount`, and `swapCooldown`. The quote is a spot-quote integration and remains MEV-visible; use manual/keeper private-relay swaps for larger sweeps.

`roundDuration` defaults to 30 minutes and can be set from 10 minutes to 24 hours only before freeze and without a pending round. Hook ownership uses `Ownable2Step`; renunciation additionally requires token freeze and an official pool.

After permanent freeze, anyone can call `sweepTaxTokens(callerMinEthOut)` to use the frozen router and quote configuration. The caller floor can only tighten the internally computed floor. Failed automatic attempts enter cooldown without reverting the triggering trade. Token, engine, and hook ownership may be renounced only after freeze.

This is a start-weighted lottery with live forfeiture for rule-breakers. It is not a live-balance lottery.

The current fixed-future-blockhash randomness is MVP-grade and vulnerable to proposer/sequencer influence and missed blockhash windows. Use a stronger randomness source before high-value production deployment.

Deployment and integration setup marks the Uniswap v4 PoolManager both eligibility-exempt and official tax-exempt before trading locks configuration.

See `V25_FINAL_HARDENING_REPORT.md` and `test_logs/` for current release-candidate evidence. Earlier reports are superseded.
