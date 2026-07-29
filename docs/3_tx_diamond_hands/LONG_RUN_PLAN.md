## Goal Description
The dev wallet is now funded with ETH. The goal is to run a comprehensive 1-hour End-to-End (E2E) simulation on the testnet. This simulation will deploy the contracts, distribute tokens to multiple trading wallets, simulate continuous randomized buy/sell trading volume, and run the Keeper bot in parallel. The Keeper bot will detect when the ETH pool and cooldown conditions are met, trigger the cross-chain CCIP lottery, and wait for the Chainlink VRF fulfillment to select and pay a winner. This cycle will repeat continuously for 1 hour.

## Proposed Changes

### 1. `scripts/long-run.js` (NEW)
We will create a dedicated long-running simulation script that acts as both the market simulator and the keeper bot orchestrator.
- **Wallet Setup**: Reads/Generates 5-10 trading wallets, funds them with gas, and distributes the initial token supply.
- **Trading Loop**: Runs an asynchronous loop for 60 minutes. Every 15-30 seconds, it will pick two random wallets and execute a token transfer (simulating a trade). This generates taxes, which eventually trigger the `swapTokensForEth` function to fund the lottery pool.
- **Keeper Integration**: Every 1 minute, the script will invoke the `sdk` to check if lottery trigger conditions are met. If met, it will trigger the lottery and enter a "Waiting for CCIP Fulfillment" state, monitoring the contract until the VRF callback arrives and a winner is selected.
- **Stats Logging**: Prints real-time statistics (ETH pool size, eligible holders, current lottery status, recent winners).

### 2. `scripts/run-e2e.sh` (MODIFY)
Update the E2E bash script to ensure a clean deployment and wiring phase before handing off execution to `long-run.js`.
- Uncomment the deployment and CCIP wiring commands.
- Replace the call to `simulate-trading.js` with `long-run.js`.

### 3. Contract Adjustments (Optional/Verification)
Ensure `MIN_LOTTERY_BALANCE` (0.0005 ETH) and `LOTTERY_COOLDOWN` (1 minute) in `RobinhoodLotteryToken.sol` are correctly set for rapid testing, allowing multiple lottery rounds within the 1-hour window.

## Verification Plan
### Automated Execution
Run the bash script:
```bash
bash scripts/run-e2e.sh
```

### Manual Verification
- Observe the console output to ensure trading wallets are repeatedly trading and generating taxes.
- Watch the Keeper logs to see the CCIP messages successfully being sent to Arbitrum.
- Verify the VRF fulfillment successfully arrives back on Robinhood and the contract correctly distributes ETH to a winning wallet.
