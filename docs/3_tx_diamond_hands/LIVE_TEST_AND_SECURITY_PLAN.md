# Goal Description
This plan covers the final steps required for the full live cycle testing of the Robinhood Lottery Token, which includes resolving critical security vulnerabilities in the eligibility arrays and updating the deployment script to initialize actual liquidity on the real Uniswap V3 ecosystem that was just deployed.

## Security Fix: Sybil Duplication Bug
In the current implementation of `_updateEligibility`, when a user transitions from a 0 balance to an eligible Fenwick tree, their address is `pushed` to the `Fenwick treeHolders` array. If they sell their tokens (dropping their balance below the threshold), their address remains in the array as a "ghost" to save gas.
However, if they buy tokens again, they are **pushed to the array a second time**. This means an attacker can repeatedly buy and sell small amounts of tokens to duplicate their address thousands of times in the `Fenwick treeHolders` array. Since the `selectWinner` function picks uniformly from the array, this allows an attacker to artificially increase their win probability to near 100%.

## Security Fix: Ghost DOS Attack
Additionally, because we leave "ghosts" in the array, the array can become extremely sparse. `selectWinner` only gets 3 attempts to find a winner with `diamondHands`. If the array is 99% ghosts, it will almost always fail 3 times and "rollover", keeping the ETH in the pool. The automated Keeper still receives a 2% reward on a rollover. An attacker could intentionally fill the arrays with ghosts to DOS the lottery, ensuring it always rolls over, and slowly drain the ETH pool via Keeper rewards.

To fix both issues, we will implement an O(1) "Swap and Pop" cleanup mechanism. This guarantees the array only ever contains currently active eligible holders, entirely eliminating both the Sybil duplicate attack and the DOS ghost attack.

## User Review Required
> [!IMPORTANT]  
> We will be deploying actual liquidity to the testnet Uniswap V3 using the `NonfungiblePositionManager`. I have calculated the price ratio (1:1) and the tick ranges. Please review this.

## Proposed Changes

---
### Contracts
We will modify `RobinhoodLotteryToken.sol` to track the exact index of every user in their respective Fenwick tree arrays using a `mapping(address => uint256) public holderIndex`. We will then use Swap and Pop to remove them when their Fenwick tree changes.

#### [MODIFY] RobinhoodLotteryToken.sol
```diff
     uint256[256] public Fenwick treeTotalBalance; 
     mapping(uint8 => address[]) public Fenwick treeHolders; 
     mapping(address => uint8) public userFenwick Tree; 
+    mapping(address => uint256) public holderIndex; // O(1) array cleanup
     // Checkpoints for Historical Balances
```
```diff
-                // We DO NOT swap and pop. We just let them remain as ghosts.
-                if (newFenwick Tree == 0) emit HolderRemovedFromEligibility(account, newBal);
+                // O(1) Swap and pop to prevent sybil duplication & DOS
+                uint256 index = holderIndex[account];
+                uint256 lastIndex = Fenwick treeHolders[oldFenwick Tree].length - 1;
+                address lastAccount = Fenwick treeHolders[oldFenwick Tree][lastIndex];
+                
+                Fenwick treeHolders[oldFenwick Tree][index] = lastAccount;
+                holderIndex[lastAccount] = index;
+                Fenwick treeHolders[oldFenwick Tree].pop();
+                holderIndex[account] = 0; // Reset
+                
+                if (newFenwick Tree == 0) emit HolderRemovedFromEligibility(account, newBal);
```
```diff
             if (newFenwick Tree != 0) {
                 Fenwick treeTotalBalance[newFenwick Tree] += newBal;
                 totalEligibleBalance += newBal;
                 
                 Fenwick treeHolders[newFenwick Tree].push(account);
+                holderIndex[account] = Fenwick treeHolders[newFenwick Tree].length - 1;
                 
                 if (oldFenwick Tree == 0) emit HolderBecameEligible(account, newBal);
             }
             userFenwick Tree[account] = newFenwick Tree;
```
---
### Deployment Scripts
We will rewrite `deploy-robinhood.js` to mint the initial liquidity position on the official `NonfungiblePositionManager` instead of skipping it. This allows our 1-hour automated trading simulation to route actual swaps through the live Uniswap V3 pool just like Mainnet.

#### [MODIFY] deploy-robinhood.js
```diff
-    // Initialize V3 Pool
-    console.log("Initializing V3 Pool...");
-    await factory.createPool(tokenAddress, await weth.getAddress(), 3000);
-    const poolAddress = await factory.getPool(tokenAddress, await weth.getAddress(), 3000);
-    
-    const Pool = await ethers.getContractAt("MockUniswapV3Pool", poolAddress);
-    await Pool.initialize(79228162514264337593543950336n); // 1:1 price
-    
-    await token.setV3Pool(poolAddress);
-
-    // Add V3 Liquidity
-    console.log("Skipping V3 Liquidity minting to save testnet gas!");
-    console.log("Mock exactInputSingle doesn't strictly require it.");
+    // Initialize and Mint Real V3 Liquidity!
+    console.log("Minting Initial V3 Liquidity via Position Manager...");
+    const pmAddress = "0x04b8D5fB476597152009e70165C9460FC1F0DfE7";
+    const pm = await ethers.getContractAt("INonfungiblePositionManager", pmAddress);
+    
+    // Approve tokens for liquidity
+    const liqAmount = ethers.parseEther("100000"); // 100k tokens
+    const ethAmount = ethers.parseEther("0.05"); // 0.05 ETH
+    await token.approve(pmAddress, liqAmount);
+    
+    // Sort tokens correctly for Uniswap V3 (token0 < token1)
+    const wethAddress = await weth.getAddress();
+    const isWethToken0 = wethAddress.toLowerCase() < tokenAddress.toLowerCase();
+    const token0 = isWethToken0 ? wethAddress : tokenAddress;
+    const token1 = isWethToken0 ? tokenAddress : wethAddress;
+    const amount0Desired = isWethToken0 ? ethAmount : liqAmount;
+    const amount1Desired = isWethToken0 ? liqAmount : ethAmount;
+    
+    await pm.createAndInitializePoolIfNecessary(token0, token1, 3000, 79228162514264337593543950336n); // 1:1 initial price
+    
+    const poolAddress = await factory.getPool(tokenAddress, wethAddress, 3000);
+    await token.setV3Pool(poolAddress);
+
+    await pm.mint({
+        token0, token1, fee: 3000,
+        tickLower: -887220, tickUpper: 887220,
+        amount0Desired, amount1Desired,
+        amount0Min: 0, amount1Min: 0,
+        recipient: deployer.address,
+        deadline: Math.floor(Date.now()/1000) + 600
+    }, { value: ethAmount });
+    console.log("Liquidity minted successfully on real UniswapV3!");
```

## Verification Plan
### Automated Tests
1. Rerun `npx hardhat test` to ensure the core mechanics of the Swap-and-Pop arrays are valid and no array-out-of-bounds errors occur during transfers.
2. Run `scripts/deploy-robinhood.js` to ensure the real `NonfungiblePositionManager.mint` correctly establishes the pool and position.
3. Rerun `scripts/run-e2e.sh` which continuously fires the Keeper and simulated user buys over 1 hour, verifying the true real-world liquidity routing matches Mainnet expectations and the `selectWinner` function still securely distributes rewards!
