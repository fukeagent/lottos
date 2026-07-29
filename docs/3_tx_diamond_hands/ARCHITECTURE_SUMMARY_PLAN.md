# System Architecture Plan & Verification

## Goal Description
This document serves to confirm the structural integrity of the `RobinhoodLotteryToken` ecosystem and verify where all core logic resides before final sign-off.

## User Review Required
> [!IMPORTANT]  
> Please review the distinction between **On-Chain Logic** and **Off-Chain Execution**. While all the core rules are in the smart contract, you will need to host a simple Keeper bot (similar to our E2E script) to automate the execution, unless you plan to rely solely on the community to trigger it for the 2% reward.

## Architecture Breakdown

### 1. On-Chain Smart Contract (`RobinhoodLotteryToken.sol`)
**Yes, 100% of the core protocol logic is entirely contained within this single Solidity file.** 
This includes:
* **Token Mechanics:** Standard ERC-20 transfers, Max Wallet enforcement (1% -> 3%), and Anti-Snipe tax decay (10% -> 3%).
* **DEX Interactions:** The contract autonomously swaps accumulated taxes for ETH using the hardcoded Uniswap V3 Router.
* **Lottery State Machine:** Tracking active rounds, cooldowns, and the Commit/Reveal lifecycle (`triggerLottery`, `selectWinner`).
* **Participant Tracking:** The highly optimized O(1) swap-and-pop Fenwick trees tracking eligible holders (`_updateEligibility`).
* **Randomness & Payouts:** Securely hashing historical block data to select a winner and autonomously transferring ETH to the Winner, the Dev Wallet, and the Keeper.

Because everything is contained here, the contract is completely **immutable and permissionless**. You do not need multiple custom contracts. 

### 2. External On-Chain Dependencies
The token interfaces with live standard contracts that already exist on the network:
* `UniswapV3Factory` & `SwapRouter` (For DEX Trading and Tax Swapping)
* `WETH9` (For ETH wrapping during swaps)

### 3. Off-Chain Execution (The Keeper)
The only logic *not* in the smart contract is the "cron job" that presses the buttons. Smart contracts cannot execute themselves based on time; they must be called by an external transaction.
* The functions `triggerLottery()` and `selectWinner()` are permissionless.
* We have designed an economic incentive (a **2% ETH reward** capped at 0.02 ETH) so that any third-party bot can pay the gas to execute these functions and earn a profit.
* **Your Responsibility:** When you deploy this to mainnet, you should run a lightweight Node.js bot (similar to the `long-run.js` script we used for E2E testing) on a cheap VPS to ensure the lottery runs smoothly. If your bot ever goes down, the community can still trigger it to claim the 2% reward.

## Conclusion
The architecture is monolithic and highly efficient. `RobinhoodLotteryToken.sol` is the only custom smart contract you need to deploy and manage.
