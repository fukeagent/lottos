# V25 Lottery Security Notes

## Snapshot integrity

`beginLotterySnapshot` captures block-opening eligible total weight. On every Fenwick node mutation, `_treeUpdate` first calls `_captureNodeOpeningIfNeeded(index)`, then `_freezeNodeForActiveSnapshot(node)`, and only then mutates `node.current`. This ordering makes per-node round routing use the same block-opening model as `activeSnapshotTotalWeight`.

Two-holder deterministic and fuzz tests prove that an Alice top-up in the round-start block cannot crowd Bob out of his opening target range. A post-start same-block test protects lazy freeze. Eligible-index ownership remains round-aware, so same-block exit and reuse cannot pair old odds with a new live holder. `LotteryEngine._findWinner` walks the residual tree and calls `getHolderByEligibleIndexAtRound` for the same round.

The token returns the snapshotted holder before applying eligibility policy. The engine then calls `isLotteryIneligible`, preserving ghost-contract cleanup while allowing explicitly approved contract wallets.

During the active holding epoch, the token checks the sender once after the complete transfer, including both legs of a taxed transfer. Falling below the round-start balance permanently removes the holder's full start weight through the engine's round-tagged exclusion Fenwick overlay. Receivers are not checked, extra buys do not add current-round weight, and transfers after trigger cannot forfeit. Settlement walks residual weight directly rather than repeatedly sampling excluded tickets.

## Payout liabilities

Direct automatic payments use `AUTO_PAYOUT_GAS` (50,000). Failed winner payments become `pendingWinnerPayout` debt and enter a bounded retry queue. Failed dev payments become `pendingDevPayout` debt keyed to the round's snapshotted receiver. Manual claims and keeper retries use `MANUAL_PAYOUT_GAS` (300,000) and restore debt unchanged on failure.

`availableLotteryBalance()` subtracts the active `reservedPrizePool`, `totalPendingWinnerPayouts`, and `totalPendingDevPayouts`. Action rewards are best effort, are not liabilities, and are attempted only after successful winner resolution. Expired rounds pay no action rewards.

## Eligibility and freeze

Contracts are blocked by default. The owner may allow a contract only when no round is pending and only if it is not an official or taxed pool path. Removing permission refreshes live eligibility. EIP-7702 delegated EOAs are eligible intentionally; mutable delegated code remains a payout risk.

All configurable token, engine, and hook settings use the shared permanent-freeze state. Before `freezeSettingsForever`, the owner remains trusted. After freeze, configuration is blocked but permissionless round execution, expiry, refresh, claims, and retries remain available.

Taxed external pools are constrained to token-containing V2-like or V3-like shapes. This excludes EOAs, arbitrary contracts, official paths, allowlisted lottery wallets, the token, and the engine. `LotteryHook` uses two-step ownership; renunciation is possible only after permanent token freeze and official-pool binding.

## Auto-swap and timing

Auto-swap remains available but defaults off. A ready, non-zero official-pool quote produces the router `minEthOut`, and the engine ETH-balance delta is checked against the same value. Failed swaps are caught so a taxed user transfer completes and tax tokens remain for a later retry. The quote is still a MEV-visible spot quote, so loss per successful automatic execution is bounded by configured slippage, `maxSwapAmount`, and cooldown rather than eliminated.

The holding duration is `roundDuration`: 10 minutes to 24 hours before freeze, 30 minutes by default. The block-based randomness delay remains separate so changing the holding duration does not change the blockhash capture window.

Diamond-hands is a start-weighted no-dip rule. It reacts to every token transfer from a round-start holder during the active epoch, but does not continuously recalculate live odds or award extra current-round weight to buyers. Action rewards remain best-effort and never become pending debt.

## Remaining limitation

Future-blockhash randomness is not VRF-grade. Proposer/sequencer influence and blockhash-window liveness remain disclosed MVP risks.
