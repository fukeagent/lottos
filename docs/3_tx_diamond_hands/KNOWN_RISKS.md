# V24 Known Risks

## MVP blockhash randomness

Winner entropy comes from a fixed future `blockhash`. A proposer, builder, or centralized sequencer may influence or withhold a favorable block. The hash also becomes unavailable after the EVM lookback window. Expiry safely releases the selected prize, but does not remove bias or liveness risk. Replace this mechanism with VRF or equivalent unbiased randomness before high-value deployment.

On sequencer-controlled L2s, the sequencer is trusted for fairness and liveness. Prize caps are the MVP fairness budget until VRF or equivalent randomness is deployed.

## Administration before permanent freeze

The owner controls payout tiers, the dev receiver, pool classification, whitelist policy, and swap configuration until `freezeSettingsForever()` executes. This is material centralization. The freeze is irreversible and spans token, engine, and hook settings; permissionless lottery actions, expiry, claims, retries, and eligibility refresh remain callable.

## Wallet code and eligibility

Normal contracts are blocked unless manually allowed. Official pools/managers/routers and taxed external pools cannot be allowed. Constructor-time code absence can temporarily admit a contract, but bounded candidate cleanup and permissionless refresh remove it. Whitelist removal refreshes eligibility immediately.

EIP-7702 delegated EOAs are intentionally treated as EOAs. Delegated code can later change or reject native ETH. A rejected winner payment becomes reserved pending winner debt; it cannot be reused by future rounds.

## Payout liveness

Automatic direct payments use `AUTO_PAYOUT_GAS` (50,000). Winner retry processing is bounded, and manual retries use `MANUAL_PAYOUT_GAS` (300,000). A receiver that always rejects ETH retains an indefinitely reserved claim. Failed action rewards are best effort and do not become debt.

Failed dev payments are preserved for the receiver snapshotted when the round started. Changing the current dev receiver does not redirect that liability.

## Operational and liquidity risks

Keepers must trigger, settle, or expire rounds within their timing windows. Quote failures safely skip auto-swaps but may accumulate tax-token backlog. The official-pool quote is a spot-quote integration, so auto-swaps remain MEV-visible; the configured slippage floor, `maxSwapAmount`, and cooldown cap each automatic execution, while manual/private-relay sweeps remain preferable for large balances. Uniswap v4 deployment must use the exact pinned core/periphery commits documented in `README.md`; different APIs are not supported.

## Fenwick write cost

The first eligibility mutation of a Fenwick node in each block records its opening value. The dedicated gas report measured roughly 1.2–1.4% increases in the existing transfer scenarios versus the committed V22 log, including about +17.9k gas for the first active-snapshot mutation. This cost is accepted to preserve block-opening odds. Multi-holder V23 tests replace the prior insufficient one-holder fairness claim.

Strict live forfeiture adds a cheap phase check to transfers. A first forfeiture also writes the round exclusion path and is materially more expensive; repeated transfers from an already forfeited holder remain bounded. Large multi-holder forfeiture totals occur across separate holder transactions, not one required keeper transaction. Settlement still finds the residual winner directly.
