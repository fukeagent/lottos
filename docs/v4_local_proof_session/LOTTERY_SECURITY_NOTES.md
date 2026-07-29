# RobinhoodLotteryToken - Security Notes

## Randomness Model (Fixed Future Blockhash)
This contract utilizes a **native on-chain fallback** randomness model due to the unavailability of Chainlink VRF on the target network. 

**IMPORTANT RISK NOTE:** This is a fixed-future-blockhash fallback, **not** VRF-grade randomness.

### How it works
1. **Trigger:** `triggerLottery()` captures the current state (bucket totals, eligible weight) and sets `randomnessBlock = block.number + DRAW_DELAY_BLOCKS` (e.g. +600 blocks).
2. **Finalize:** `finalizeLottery(roundId)` executes after `randomnessBlock` is mined. It hashes the immutable `blockhash(randomnessBlock)` along with execution context to create a random seed.
3. **Expiry:** If `finalizeLottery` is not called within `BLOCKHASH_LOOKBACK_LIMIT` (250 blocks) past the `randomnessBlock`, the blockhash is wiped from the EVM. The round is then forced into an `EXPIRED` status, rolling over the prize pool to the next round. This prevents a finalizer from intentionally waiting until `blockhash` returns `0x0` to force a zero seed.

### Known Limitations
- **Sequencer/Block Producer Influence:** A malicious block producer can potentially drop their own block if they see that the resulting blockhash does not benefit them (an extortion/bribe vector). This is an inherent limitation of native blockhash randomness.
- **No True VRF:** Until native VRF exists on Robinhood network, this is the most secure viable alternative.
- **Production Recommendations:** It is strongly recommended to cap the maximum prize per round and ensure the project keeper runs a cron job to finalize rounds immediately at `randomnessBlock + 1`. 

## Diamond-Hands Validation Rule
Even though live array candidate selections are used, they are safeguarded by the `diamondHands` validation rule inside `finalizeLottery`:
```solidity
uint256 snapshotBalance = getPastBalance(candidate, snapBlock);
bool isGhost = (snapshotBalance == 0 || msb(snapshotBalance) != winningBucket);
bool diamondHands = balanceOf(candidate) >= snapshotBalance;
```
- A winner is only valid if their current live balance is $\ge$ their snapshot balance.
- This prevents a user who sells their tokens after the snapshot (but before the transfer lock) from claiming a win. 
- **Requirement:** To win the lottery, a holder must be eligible at the snapshot and must not reduce their balance until the draw completes.

## Protected Manual Tax Swaps
The previous auto-swap mechanism (`amountOutMinimum: 0`) has been completely removed to prevent Zero-Slippage Sandwich Attacks on the liquidity pool.

- **Keeper Driven:** Tax swaps are strictly executed manually via `manualSwapTaxes(uint256 tokenAmount, uint256 amountOutMinimum)`.
- **WETH Unwrap Safety:** Router unwraps are executed using low-level `.call` to prevent a reverting `IWETH9.withdraw()` from bricking the contract flow. If the unwrap fails, WETH is held safely in the contract and can be retrieved via `unwrapWETH(uint256 amount)`.
- **Pool Permissions:** The `setV3Pool` function is permanently locked once trading is activated.
