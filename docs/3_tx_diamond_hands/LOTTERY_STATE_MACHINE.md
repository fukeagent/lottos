# V25 Lottery State Machine

## `NONE` to `EPOCH_STARTED`

`startLotteryEpoch()` requires active trading, the launch delay and round interval, no active round, sufficient free balance, and positive block-opening eligible weight. It selects a tiered prize from `availableLotteryBalance()`, snapshots the dev receiver, reserves the prize, and starts a round-aware Fenwick/holder snapshot at `block.number - 1`.

Before start, every same-block Fenwick mutation has already captured the node's opening value. During and after start, `_treeUpdate` preserves the mandatory capture → freeze → current mutation order. Thus total snapshot weight and cumulative node routing describe the same block-opening distribution.

Availability excludes the selected prize plus pending winner and dev liabilities.

## `EPOCH_STARTED` to `DRAW_TRIGGERED`

While this phase is active, any sender that falls below their round-start balance permanently forfeits their full start weight. An engine-owned, round-tagged Fenwick overlay subtracts forfeited tickets from `roundRemainingWeight`. Dip-and-rebuy cannot restore weight; additional buys affect future rounds only.

After the holding duration, `triggerDraw()` records `endSnapshotBlock = block.number - 1`, closes live forfeiture, and selects a fixed future randomness block. It must execute within `TRIGGER_DRAW_GRACE_PERIOD`; otherwise anyone may expire the started epoch. Rewards are calculated but not paid at either start or trigger.

## `DRAW_TRIGGERED` to `FULFILLED`

After the randomness block, `payLottery()` derives deterministic attempt seeds and samples only residual non-forfeited start weight. The candidate must still pass defensive eligibility and end-balance validation. A permanently invalid residual candidate is excluded before the bounded loop continues.

On success, state and reservations are finalized before external calls. Failed winner and dev payments become reserved debts. Starter, triggerer, and payer rewards are best effort and create no debt. The active token snapshot is released.

## Expiry

If all start weight is forfeited, the round can expire immediately and its selected prize returns to free balance. The same release occurs if no eligible winner is found by the lifetime attempt cap or the fixed blockhash becomes unavailable. Expired rounds pay no action rewards and create no payout debt.

## Recovery

Automatic winner retry work is bounded and uses `AUTO_PAYOUT_GAS`. Winners and permissionless keepers can retry winner debt manually; dev receivers and keepers can likewise retry dev debt with `MANUAL_PAYOUT_GAS`. Failed retries leave the liability unchanged.
# V24 timing note

The holding phase uses the engine's owner-configurable `roundDuration` (30 minutes by default, bounded from 10 minutes to 24 hours). It may not change while a round is pending and is permanently locked by `freezeSettingsForever()`. The separate `DRAW_DELAY_BLOCKS` remains block-based to preserve the blockhash capture assumptions.
