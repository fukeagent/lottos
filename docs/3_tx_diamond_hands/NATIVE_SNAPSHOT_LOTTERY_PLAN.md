# Native Robinhood Snapshot Lottery Architecture (V2)

## Goal Description
Rewrite the `RobinhoodLotteryToken` to completely eliminate Chainlink CCIP and cross-chain VRF dependencies. The lottery will run natively on Robinhood Testnet by combining **ERC20Votes** (for historical balance checkpoints) and a **Future Blockhash** commit-reveal scheme. This makes the lottery 100% immune to flash-loan/sandwich attacks while keeping tokens liquid in user wallets. We will also introduce permissionless **Keeper Rewards** so anyone can run the automation bots indefinitely.

## Addressed Feedback
- **Keeper Reward:** Set to **2% of the ETH pool**, capped at a maximum of **0.02 ETH** to prevent draining the pool.
- **Fallback Winners:** The contract will randomly select a 1st, 2nd, and 3rd place candidate. If the 1st candidate is disqualified, it checks the 2nd. If the 2nd is disqualified, it checks the 3rd. If all 3 fail, the jackpot officially rolls over. (We bound it to 3 to prevent Out-Of-Gas errors from infinite while-loops).
- **Buying More Tokens:** If a user holds 1,000 tokens at the snapshot, and buys 500 *more* tokens during the 20-minute wait, they **WILL** still win! The rule is `Live Balance >= Snapshot Balance`. Since `1,500 >= 1,000`, they successfully diamond-handed. Their winning chance is based on the 1,000, but their extra buys don't penalize them.

---

## Proposed Changes

### Core Token Contract

#### [MODIFY] `contracts/RobinhoodLotteryToken.sol`
We will rewrite the core logic:
1. **Inheritance**: Inherit `ERC20Votes` from OpenZeppelin to automatically record checkpoints on every transfer.
2. **Remove CCIP**: Delete all Chainlink CCIP imports, `arbitrumChainSelector`, `arbitrumVrfRequester`, and `_ccipReceive`.
3. **Append-Only Fenwick Trees**: Change the Fenwick tree logic to never "Swap and Pop" users. We just push them.
4. **Trigger Commitment**:
   ```solidity
   function triggerLottery() external {
       // Requires ETH pool minimum & cooldown
       
       uint256 currentBlock = block.number;
       Round storage r = rounds[currentRoundId];
       r.snapshotBlock = currentBlock - 1; // Prevent flash loans
       r.targetBlock = currentBlock + 600; // ~20 mins in future
       r.status = RoundStatus.PENDING_REVEAL;
       
       // Snapshot the 15 active Fenwick tree totals into storage (O(1) gas)
       // ...
   }
   ```
5. **Winner Selection (3 Fallbacks)**:
   ```solidity
   function selectWinner() external {
       Round storage r = rounds[currentRoundId];
       require(block.number >= r.targetBlock, "Too early");
       require(r.status == RoundStatus.PENDING_REVEAL, "Not pending");
       
       if (block.number > r.targetBlock + 255) {
           r.status = RoundStatus.EXPIRED; // 256-block window missed! 
           return;
       }
       
       // Generate Base Randomness
       uint256 seed = uint256(keccak256(abi.encode(blockhash(r.targetBlock), r.roundId)));
       
       address winner = address(0);
       
       // Try up to 3 candidates
       for (uint256 i = 0; i < 3; i++) {
           seed = uint256(keccak256(abi.encode(seed)));
           
           uint8 winningFenwick Tree = _selectFenwick Tree(seed, r.roundId);
           uint256 candidateIndex = seed % Fenwick treeHolders[winningFenwick Tree].length;
           address candidate = Fenwick treeHolders[winningFenwick Tree][candidateIndex];
           
           uint256 snapshotBalance = getPastVotes(candidate, r.snapshotBlock);
           bool isGhost = msb(snapshotBalance) != winningFenwick Tree;
           bool diamondHands = balanceOf(candidate) >= snapshotBalance;
           
           if (!isGhost && diamondHands) {
               winner = candidate;
               break; // We found a valid winner!
           }
       }
       
       // Calculate Keeper Reward (2% capped at 0.02 ETH)
       uint256 poolBalance = address(this).balance;
       uint256 keeperReward = (poolBalance * 2) / 100;
       if (keeperReward > 0.02 ether) keeperReward = 0.02 ether;
       
       if (winner != address(0)) {
           // WINNER! Pay them 90%, Dev 10% (minus Keeper reward)
       } else {
           // ALL 3 FAILED! Rollover!
       }
       
       payable(msg.sender).transfer(keeperReward);
       r.status = RoundStatus.IDLE;
   }
   ```

### Infrastructure & Deployment

#### [DELETE] `contracts/BaseVRFRequester.sol`
No longer needed. Cross-chain architecture is retired.

#### [MODIFY] `scripts/deploy-robinhood.js`
Update the deployment script to deploy `RobinhoodLotteryToken` as a standalone contract without needing CCIP router configurations.

#### [DELETE] `scripts/deploy-base.js`
#### [DELETE] `scripts/wire-contracts.js`
#### [DELETE] `scripts/fund-vrf.js`
Cross-chain wiring and funding scripts are no longer required!

#### [MODIFY] `scripts/long-run.js` (Keeper Bot)
Update the long-running simulation bot:
- It will continuously check if `triggerLottery()` can be called.
- It will monitor the blockchain for `targetBlock` to be mined.
- Once `targetBlock` is mined, it will immediately call `selectWinner()` to earn the Keeper Reward!
- The Keeper logic becomes completely native and localized to Robinhood Testnet.

---

## Verification Plan

### Automated Tests
I will rewrite the Hardhat tests in `test-trigger.js` to simulate:
1. `triggerLottery` recording the correct `targetBlock`.
2. Hardhat advancing the chain by 600 blocks (`evm_mine`).
3. Calling `selectWinner` and verifying the Keeper receives their reward.
4. Simulating a user who dumps their tokens during the 600 blocks and verifying the contract successfully falls back to candidate #2 or #3.

### Manual Verification
The user will manually run `bash scripts/run-e2e.sh` and observe the E2E simulation. The logs will clearly show the native trigger, the 600-block wait (sped up on local, but real on testnet), and the permissionless reward payout.
