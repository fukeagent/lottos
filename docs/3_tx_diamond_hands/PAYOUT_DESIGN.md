# V22 Payout Design

## Prize accounting

At round start, `selectedPrizePool` moves from free balance into `reservedPrizePool`. The selected pool is divided among the winner, the round-snapshotted dev receiver, and capped starter/triggerer/payer rewards.

`availableLotteryBalance()` is:

```text
max(0, vault ETH - reservedPrizePool
                 - totalPendingWinnerPayouts
                 - totalPendingDevPayouts)
```

ETH already owed cannot size or fund another round.

## Automatic settlement

`_tryPayout` uses `AUTO_PAYOUT_GAS` (50,000). State is finalized before calls, so a rejecting recipient cannot revert round completion.

- Winner failure creates `pendingWinnerPayout[winner]` and increases `totalPendingWinnerPayouts`.
- Dev failure creates `pendingDevPayout[roundReceiver]` and increases `totalPendingDevPayouts`.
- Action reward failure emits an event but creates no debt.

The dev receiver is captured at round start. Later configuration changes cannot redirect old debt. Action rewards are attempted only when a winner completes the round; expiration pays none.

## Recovery

Automatic winner processing is capped per call and per receiver. It uses the automatic gas stipend and disables requeueing after three failures without deleting debt.

`claimPendingWinnerPayout`, `payPendingWinner`, `claimPendingDevPayout`, and `payPendingDevPayout` use `MANUAL_PAYOUT_GAS` (300,000). Each retry applies checks-effects-interactions under `nonReentrant`. A failed call restores the exact mapping and aggregate liability; a successful call clears both and transfers the same ETH, leaving free balance unchanged.
# V24 auto-swap note

Tax-token auto-swaps are optional and disabled by default. When enabled, a ready official-pool quote supplies `minEthOut`; both the router call and the engine balance-delta check enforce it. A failed auto-swap is caught so the taxed transfer succeeds and the tax-token balance remains available for a later manual or automatic retry. The quote is MEV-visible spot pricing, so large sweeps should use a keeper/private relay with an explicit `manualSwapTaxTokens` floor.

After freeze, `sweepTaxTokens(callerMinEthOut)` remains permissionless. It uses the frozen quote/router, respects the amount cap and cooldown, and applies the greater of the internal oracle floor and caller floor. Failed automatic attempts enter cooldown; action rewards remain best-effort and never create pending liabilities.
