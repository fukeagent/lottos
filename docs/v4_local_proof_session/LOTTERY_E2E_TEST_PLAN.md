## Goal Description
The smart contracts are successfully deployed on the Robinhood Testnet and Arbitrum Sepolia. Now we must plan the End-To-End (E2E) Live Test. The goal is to wire the contracts, simulate live user trading on the DEX, fund the Arbitrum VRF subscription, and trigger the lottery Keeper bot to perform a complete cross-chain drawing.

## User Review Required
> [!IMPORTANT]
> **Liquidity State:** All 1,000,000,000 tokens were successfully added to the Mock V3 Router on the Robinhood Testnet during deployment. To simulate real-world behavior, we will simulate a user "buying" from the V3 pool and then transferring tokens to trigger the automatic tax-to-ETH swapping.

## Proposed Changes

---

### Scripts for E2E Testing
We will add three new scripts to automate the testing workflow.

#### [NEW] `scripts/simulate-trading.js`
This script will run on the Robinhood Testnet. 
1. It will use a secondary wallet to perform a V3 "Buy" swap (trading testnet ETH for RLOTTO tokens).
2. It will perform a series of transfers to other wallets.
3. Because the V3 auto-swap threshold is set to 100,000 tokens, these transfers will automatically generate taxes, swap them back to WETH via the V3 Router, and unwrap them into Native ETH inside the Lottery Token contract until the pool reaches the `0.05 ETH` minimum threshold.

#### [NEW] `scripts/fund-vrf.js`
This script will run on Arbitrum Sepolia.
1. It will attach to the `ArbitrumVRFRequester`.
2. It will call `topUpSubscriptionNative()` and send 0.05 testnet ETH to fund the Chainlink VRF subscription so it can respond to our random number requests.

#### [NEW] `scripts/run-e2e.sh`
A master bash script to execute the entire sequence in order:
```bash
# 1. Wire the contracts
npx hardhat run scripts/wire-contracts.js --network robinhoodTestnet
npx hardhat run scripts/wire-contracts.js --network arbitrumSepolia

# 2. Fund VRF
npx hardhat run scripts/fund-vrf.js --network arbitrumSepolia

# 3. Simulate Trading to collect taxes
npx hardhat run scripts/simulate-trading.js --network robinhoodTestnet

# 4. Start the Keeper Bot
node bot/keeper.js
```

## Verification Plan
### Automated Tests
*   N/A (This is a live testnet execution)

### Manual Verification
*   You will be able to watch the terminal output of `run-e2e.sh`.
*   We will see the Robinhood token accrue ETH.
*   We will see the Keeper Bot automatically detect the threshold, trigger the CCIP message to Arbitrum, wait for the VRF fulfillment, and relay the winner back to Robinhood!
