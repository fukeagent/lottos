# Keeper Rewards System

To fully decentralize the operational execution of the lottery lifecycle, the `LotteryEngine` dedicates 3% of every prize pool to "Keepers" (any external caller who progresses the state machine).

## Goal
The protocol should never require the owner to manually click buttons to run the lottery. Instead, by offering a financial incentive, third-party MEV bots, network participants, or even regular users are encouraged to pay the gas fees required to run the lottery.

## Breakdown
The 3% total reward is split into 3 distinct slices, representing the 3 necessary transactions to complete a round:
1. `startLotteryEpoch()`: The caller who initiates the epoch receives 1% of the total prize pool.
2. `triggerDraw()`: The caller who closes the holding epoch and triggers the randomness request receives 1%.
3. `payLottery()`: The caller who finalizes the round by reading the blockhash and processing payouts receives 1%.

## Payout Execution
Keeper rewards are not distributed immediately upon their respective function calls. Instead, the addresses of the three keepers (`starter`, `triggerer`, `payer`) are cached in the `Round` struct. 
When `payLottery()` successfully finds a winner and processes the distribution, it calculates 1% of the original `selectedPrizePool` and pushes that amount to each of the three keeper addresses using `_tryPayout`. 

*Note: Action rewards are paid ONLY if `payLottery()` succeeds. If `expireLottery` or `expireStartedEpoch` is called because the blockhash window was missed or the epoch was stuck, the round is aborted. In this scenario, the prize pool is returned to the contract, and **no keeper rewards are paid** for that round. Keepers must successfully complete the round to get paid.*
