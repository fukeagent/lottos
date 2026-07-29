## Goal Description
The Chainlink CCIP infrastructure is officially deployed and active on the Robinhood Testnet! This means we no longer need to use `MockCCIPRouter` to test cross-chain lottery triggers. We will revert our mock infrastructure and configure the system to use the *real* Chainlink Decentralized Oracle Networks (DONs) to route messages from Robinhood Testnet to Arbitrum Sepolia, and back.

## User Review Required
> [!IMPORTANT]
> The real Chainlink CCIP and VRF infrastructure takes physical time to execute cross-chain (often 5-15 minutes round trip). The 1-hour simulation will progress much slower than the mock version, but it will be 100% authentic. Please approve if you are okay with authentic cross-chain latency during the E2E simulation.

## Proposed Changes

### Configuration Updates
We will update the hardcoded CCIP Router addresses in our deployment scripts to point to the real infrastructure.

#### [MODIFY] `scripts/deploy-robinhood.js`
Revert `MockCCIPRouter` deployment and use the official Robinhood Testnet Router.
```javascript
-    const CCIPRouterFactory = await ethers.getContractFactory("MockCCIPRouter");
-    const mockRouter = await CCIPRouterFactory.deploy();
-    await mockRouter.waitForDeployment();
-    const RH_CCIP_ROUTER = await mockRouter.getAddress();
+    const RH_CCIP_ROUTER = "0x30D197C6F5bE050D5525dD94d01760FaCdB67e7C";
```

#### [MODIFY] `scripts/deploy-arbitrum.js`
Revert `MockCCIPRouter` deployment and use the official Arbitrum Sepolia Router.
```javascript
-    const CCIPRouterFactory = await ethers.getContractFactory("MockCCIPRouter");
-    const mockRouter = await CCIPRouterFactory.deploy();
-    await mockRouter.waitForDeployment();
-    const ARB_CCIP_ROUTER = await mockRouter.getAddress();
+    const ARB_CCIP_ROUTER = "0x2a9c5afb0d0e4bab2bcdae109ec4b0c4be15a165";
```

### Keeper Bot Adjustments
We will clean up the Keeper bot (`long-run.js`) to remove the manual mock CCIP relaying logic. The bot will rely entirely on the real Chainlink DON to deliver the messages.

#### [MODIFY] `scripts/long-run.js`
Remove `simulateIncomingMessage` blocks. The Keeper will now only:
1. Detect Robinhood conditions and trigger the lottery (sends real CCIP message).
2. Monitor Arbitrum for the VRF fulfillment (which happens automatically after the real CCIP message arrives).
3. Execute `sendRandomnessToRobinhood` on Arbitrum to pay the return CCIP fee and dispatch the result back to Robinhood.

## Verification Plan
### Automated Tests
We will execute the long-running simulation using the real testnets:
`bash scripts/run-e2e.sh`

### Manual Verification
Monitor the background logs. You will be able to verify the cross-chain messages physically appearing on the [CCIP Explorer](https://ccip.chain.link/) by looking up the CCIP message hashes printed in the Keeper logs.
