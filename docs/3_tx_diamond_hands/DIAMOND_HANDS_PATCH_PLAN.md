# Diamond Hands 3-TX Lottery Patch — Execution Plan

## Phase 1: Contract Rewrites
1. **LotteryEngine.sol** — Full rewrite with 3-TX state machine:
   - `startLotteryEpoch()` → `triggerDraw()` → `payLottery()`
   - `expireLottery()` for missed blockhash windows
   - `_payoutOrEscrow()` + `failed payouts mechanism()` for safe payouts
   - Action rewards (1% capped at 0.02 ETH each) from selectedPrizePool
   - Diamond-hands validation: startBalance ≤ endBalance ≤ currentBalance
   - Remove fake EOA keeper check
   - Remove epoch-block timing, use timestamp intervals

2. **RobinhoodToken.sol** — Targeted patches:
   - Add `launchConfigLocked`, lock `setExemptions` after `activateTrading()`
   - Add `activeFenwick TreeBitmap` for gas-efficient Fenwick tree scanning
   - Add `_isLotteryIneligible()` to actively exclude contracts
   - Add `minEligibleAmount()` view function
   - Emit `LaunchConfigLocked` event

3. **LotteryHook.sol** — No changes needed (hook only collects tax)

## Phase 2: Tests
4. Rewrite `V4LotteryHookIntegration.t.sol`:
   - Keep all 8 V4 swap regression tests as-is
   - Rewrite E2E lifecycle for 3-TX flow
   - Add 28 state machine tests
   - Add 8 diamond-hands tests
   - Add 10 payout safety tests
   - Add 8 exemption/contract eligibility tests
   - Add 7 timing/blockhash tests
   - Add worst-case gas test

## Phase 3: Documentation
5. Write docs in `docs/diamond_hands_3tx_patch/`:
   - LOTTERY_STATE_MACHINE.md
   - LOTTERY_SECURITY_NOTES.md
   - PAYOUT_DESIGN.md
   - KEEPER_REWARDS.md
   - KNOWN_RISKS.md
   - TEST_RESUME.md

## Phase 4: Verify & Commit
6. `forge build` → `forge test -vvv --gas-report`
7. `git add . && git commit -m "fix: add diamond-hands lottery state machine and payout safeguards"`

## Acceptance Criteria
All 23 items from the spec must be verified green before commit.
