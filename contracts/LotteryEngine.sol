// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRobinhoodToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getPastBalance(address account, uint256 blockNumber) external view returns (uint256);
    function isEligibilityExempt(address account) external view returns (bool);
    function tradingActivatedAt() external view returns (uint256);
    function minEligibleAmount() external view returns (uint256);

    function totalEligibleBalance() external view returns (uint256);
    function getEligibleTotalWeight() external view returns (uint256);
    function beginLotterySnapshot(uint256 roundId) external returns (uint256 snapshotBlock, uint256 snapshotWeight);
    function endLotterySnapshot(uint256 roundId) external;
    function setDiamondHandsEpochActive(uint256 roundId, bool active) external;
    function canBeginLotterySnapshot() external view returns (bool);
    function treeFindByCumulativeAtRound(uint256 target, uint256 roundId) external view returns (uint256);
    function getEligibleWeightAtRound(uint256 index, uint256 roundId) external view returns (uint256);
    function getFenwickNodeValueAtRound(uint256 index, uint256 roundId) external view returns (uint256);
    function getHolderByEligibleIndexAtRound(uint256 index, uint256 roundId) external view returns (address);
    function isEip7702DelegatedEOA(address account) external view returns (bool);
    function isLotteryIneligible(address account) external view returns (bool);
    function refreshEligibility(address account) external;
    function settingsFrozenForever() external view returns (bool);
}

enum AutoLotteryAction {
    None,
    StartEpoch,
    TriggerDraw,
    PayLottery,
    ExpireStartedEpoch,
    ExpireDraw
}

/// @title LotteryEngine — 3-TX Diamond-Hands State Machine
/// @notice V14/V15 samples from the lazy round-snapshot Fenwick tree at startSnapshotBlock (Snapshot 1) for winner selection,
///         using lazy round-snapshot storage for gas efficiency. Only one active round snapshot exists at a time.
///         Snapshot 1 freezes odds.
///         During the holding epoch, a sender that dips below its start balance permanently loses its start weight.
///         Settlement samples the residual start tree; Snapshot 2 remains a defensive final validation point.
///         payLottery is settlement only and does not require currentBalance >= startBalance.
///         If a candidate fails validation, the engine iterates deterministically using subsequent attempt seeds.
///         The current lottery uses fixed-future-blockhash randomness with a capped selected payout.
///         It requires payLottery() to run before the blockhash is unavailable unless the randomness hash has already been stored by a prior pay attempt.
///         If no usable hash is captured, the round expires and the reserved prize returns to available vault balance.
///         This is acceptable only for MVP / capped prize pools. It is not VRF-grade randomness. A future randomness-provider upgrade can integrate VRF/oracle randomness.
///         LotteryEngine is the ETH vault. ETH from the official hook and external-pool tax swaps is held in LotteryEngine. LotteryEngine pays winner/dev/action rewards directly.
contract LotteryEngine is Ownable2Step, ReentrancyGuard {
    // ──────────────────────────────────────────────
    //  Token reference
    // ──────────────────────────────────────────────
    IRobinhoodToken public token;
    address public devFeeReceiver;

    // ──────────────────────────────────────────────
    //  Timing — human-time (block.timestamp)
    // ──────────────────────────────────────────────
    uint256 public constant FIRST_LOTTERY_DELAY = 2 hours;
    uint256 public constant MIN_ROUND_START_SPACING = 30 minutes;
    uint256 public constant MIN_ROUND_DURATION = 10 minutes;
    uint256 public constant MAX_ROUND_DURATION = 24 hours;
    uint256 public roundDuration = 30 minutes;

    // ──────────────────────────────────────────────
    //  Timing — block-based (blockhash randomness)
    // ──────────────────────────────────────────────
    uint256 public constant DRAW_DELAY_BLOCKS = 600;
    uint256 public constant BLOCKHASH_LOOKBACK_LIMIT = 250;

    // ──────────────────────────────────────────────
    //  Winner selection & gas-bounded attempts
    // ──────────────────────────────────────────────
    // Max candidates sampled per single payLottery execution to bound gas consumption
    uint256 public constant MAX_WINNER_ATTEMPTS = 150;
    // Lifetime attempt cap across all payLottery invocations; round expires if exhausted
    uint256 public constant MAX_TOTAL_ROUND_ATTEMPTS = 10000;
    uint256 public constant MAX_CANDIDATE_CLEANUPS_PER_CALL = 20;
    uint256 internal constant FENWICK_TREE_SIZE = 1 << 24;

    // ──────────────────────────────────────────────
    //  Action rewards — from selectedPrizePool
    // ──────────────────────────────────────────────
    uint256 public constant START_REWARD_BPS = 100; // 1%
    uint256 public constant TRIGGER_REWARD_BPS = 100; // 1%
    uint256 public constant PAY_REWARD_BPS = 100; // 1%
    uint256 public constant MAX_ACTION_REWARD = 0.02 ether;

    // ──────────────────────────────────────────────
    //  Dev fee
    // ──────────────────────────────────────────────
    uint256 public constant DEV_FEE_BPS = 1000; // 10%

    // ──────────────────────────────────────────────
    //  Prize selection (V18 Snowball Tiers)
    // ──────────────────────────────────────────────
    uint256 public constant INITIAL_TIER1_MAX = 2 ether;
    uint256 public constant INITIAL_TIER2_MAX = 10 ether;
    uint256 public constant INITIAL_TIER3_MAX = 50 ether;

    uint16 public constant INITIAL_TIER1_BPS = 2500;
    uint16 public constant INITIAL_TIER2_BPS = 1500;
    uint16 public constant INITIAL_TIER3_BPS = 1000;
    uint16 public constant INITIAL_TIER4_BPS = 500;

    uint256 public constant HARD_TIER1_MAX = 5 ether;
    uint256 public constant HARD_TIER2_MAX = 25 ether;
    uint256 public constant HARD_TIER3_MAX = 100 ether;

    uint16 public constant HARD_TIER1_BPS = 5000;
    uint16 public constant HARD_TIER2_BPS = 3000;
    uint16 public constant HARD_TIER3_BPS = 2000;
    uint16 public constant HARD_TIER4_BPS = 1000;

    uint256 public tier1MaxBalance = INITIAL_TIER1_MAX;
    uint256 public tier2MaxBalance = INITIAL_TIER2_MAX;
    uint256 public tier3MaxBalance = INITIAL_TIER3_MAX;

    uint16 public tier1PayoutBps = INITIAL_TIER1_BPS;
    uint16 public tier2PayoutBps = INITIAL_TIER2_BPS;
    uint16 public tier3PayoutBps = INITIAL_TIER3_BPS;
    uint16 public tier4PayoutBps = INITIAL_TIER4_BPS;

    uint256 public constant MIN_LOTTERY_BALANCE = 0.05 ether;
    uint256 public immutable HARD_MAX_PRIZE_PAYOUT;

    // ──────────────────────────────────────────────
    //  Accounting
    // ──────────────────────────────────────────────
    uint256 public reservedPrizePool;
    uint256 public lastRoundStartedAt;
    uint256 public currentRoundId;

    // ──────────────────────────────────────────────
    //  Enums
    // ──────────────────────────────────────────────
    // ──────────────────────────────────────────────
    //  Pending Winner Payouts
    // ──────────────────────────────────────────────
    mapping(address => uint256) public pendingWinnerPayout;
    mapping(address => bool) public pendingWinnerQueued;
    mapping(address => uint8) public pendingWinnerRetryCount;
    mapping(address => bool) public pendingWinnerAutoRetryDisabled;

    uint256 public totalPendingWinnerPayouts;

    address[] public pendingWinnerQueue;
    uint256 public pendingWinnerQueueCursor;

    uint256 public pendingWinnerQueuedCount;

    mapping(address => uint256) public pendingDevPayout;
    uint256 public totalPendingDevPayouts;

    uint256 public constant AUTO_PAYOUT_GAS = 50_000;
    uint256 public constant MANUAL_PAYOUT_GAS = 300_000;
    uint256 public constant TRIGGER_DRAW_GRACE_PERIOD = 1 hours;

    uint8 public constant MAX_AUTO_PAYOUT_RETRIES = 3;
    uint256 public constant MAX_PENDING_WINNER_PAYOUT_STEPS = 5;

    event WinnerPayoutStored(address indexed winner, uint256 amount);
    event PendingWinnerQueued(address indexed winner);
    event PendingWinnerAutoRetryDisabled(address indexed winner, uint256 amount);
    event PendingWinnerPayoutPaid(address indexed winner, uint256 amount, address indexed caller);
    event PendingWinnerPayoutFailed(address indexed winner, uint256 amount, address indexed caller, uint8 retryCount);
    event PendingDevPayoutStored(address indexed receiver, uint256 amount);
    event PendingDevPayoutPaid(address indexed receiver, uint256 amount, address indexed caller);
    event PendingDevPayoutFailed(address indexed receiver, uint256 amount, address indexed caller);

    event PayoutTiersUpdated(
        uint256 tier1MaxBalance,
        uint256 tier2MaxBalance,
        uint256 tier3MaxBalance,
        uint16 tier1PayoutBps,
        uint16 tier2PayoutBps,
        uint16 tier3PayoutBps,
        uint16 tier4PayoutBps
    );
    enum RoundStatus {
        NONE,
        EPOCH_STARTED,
        DRAW_TRIGGERED,
        FULFILLED,
        EXPIRED
    }

    enum PayoutType {
        Winner,
        Dev,
        StartReward,
        TriggerReward,
        PayReward
    }

    // ──────────────────────────────────────────────
    //  Round storage
    // ──────────────────────────────────────────────
    struct Round {
        uint256 roundId;
        RoundStatus status;
        // TX1 — startLotteryEpoch
        address starter;
        uint256 startSnapshotBlock;
        uint256 startTimestamp;
        uint256 selectedPrizePool;
        uint256 startReward;
        uint256 eligibleWeightAtSnapshot;
        address devFeeReceiverForRound;
        // TX2 — triggerDraw
        address triggerer;
        uint256 endSnapshotBlock;
        uint256 triggerTimestamp;
        uint256 randomnessBlock;
        uint256 triggerReward;
        // TX3 — payLottery
        address payer;
        address winner;
        uint256 winnerAmount;
        uint256 devAmount;
        uint256 payReward;
        bytes32 randomnessBlockHash;
    }

    mapping(uint256 => Round) internal _rounds;
    mapping(uint256 => uint256) public roundAttemptsCursor;
    mapping(uint256 => uint256) public roundRemainingWeight;
    mapping(uint256 => uint64) public forfeitedRoundByIndex;

    struct ForfeitureNode {
        uint64 roundId;
        uint192 weight;
    }

    mapping(uint256 => ForfeitureNode) internal forfeitureNodes;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────
    event LotteryEpochStarted(
        uint256 indexed roundId,
        address indexed starter,
        uint256 startSnapshotBlock,
        uint256 selectedPrizePool,
        uint256 eligibleWeight
    );

    event DrawTriggered(
        uint256 indexed roundId, address indexed triggerer, uint256 endSnapshotBlock, uint256 randomnessBlock
    );

    event LotteryFulfilled(
        uint256 indexed roundId,
        address indexed winner,
        uint256 winnerAmount,
        uint256 devAmount,
        uint256 startReward,
        uint256 triggerReward,
        uint256 payReward
    );

    event LotteryExpired(uint256 indexed roundId, uint256 releasedPrize);

    event LotterySelectionAttempted(uint256 indexed roundId, uint256 attemptsUsed, bool winnerFound);

    event CandidateEligibilityCleanupAttempted(uint256 indexed roundId, address indexed candidate, uint8 reason);
    event RoundWeightForfeited(
        uint256 indexed roundId, address indexed account, uint256 indexed index, uint256 startWeight
    );
    event RoundRemainingWeightUpdated(uint256 indexed roundId, uint256 remainingWeight);

    event DirectPayout(address indexed to, uint256 amount, PayoutType payoutType);
    event DirectPayoutFailed(address indexed to, uint256 amount, PayoutType payoutType);
    event WinnerPayoutFailed(uint256 indexed roundId, address indexed winner, uint256 amount);

    event DevFeeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event RoundDurationSet(uint256 oldDuration, uint256 newDuration);
    event LotteryAutoActionSucceeded(uint256 indexed roundId, AutoLotteryAction action, address indexed rewardTo);
    event LotteryAutoActionSkipped(AutoLotteryAction action, string reason);

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────
    constructor(address _token, address _devFeeReceiver, uint256 _hardMaxPrizePayout) Ownable(msg.sender) {
        require(_token != address(0), "Zero token address");
        require(_devFeeReceiver != address(0), "Zero dev fee receiver");
        require(_hardMaxPrizePayout > 0, "Zero hard cap");

        token = IRobinhoodToken(_token);
        devFeeReceiver = _devFeeReceiver;
        HARD_MAX_PRIZE_PAYOUT = _hardMaxPrizePayout;
    }

    receive() external payable {}

    // ══════════════════════════════════════════════
    //  View helpers
    // ══════════════════════════════════════════════

    function isLotteryPending() external view returns (bool) {
        return _hasActiveRound();
    }

    function _hasActiveRound() internal view returns (bool) {
        RoundStatus s = _rounds[currentRoundId].status;
        return s == RoundStatus.EPOCH_STARTED || s == RoundStatus.DRAW_TRIGGERED;
    }

    function availableLotteryBalance() public view returns (uint256) {
        uint256 locked = reservedPrizePool + totalPendingWinnerPayouts + totalPendingDevPayouts;
        if (address(this).balance <= locked) return 0;
        return address(this).balance - locked;
    }

    function isLotteryReady() public view returns (bool) {
        return getCurrentPrizeAmount() >= MIN_LOTTERY_BALANCE;
    }

    function _actionReward(uint256 pool, uint256 bps) internal pure returns (uint256) {
        uint256 reward = (pool * bps) / 10_000;
        if (reward > MAX_ACTION_REWARD) reward = MAX_ACTION_REWARD;
        return reward;
    }

    function getRound(uint256 roundId)
        external
        view
        returns (
            uint256 id,
            RoundStatus status,
            address starter,
            uint256 startSnapshotBlock,
            uint256 startTimestamp,
            uint256 selectedPrizePool,
            uint256 startReward,
            uint256 eligibleWeightAtSnapshot,
            address triggerer,
            uint256 endSnapshotBlock,
            uint256 randomnessBlock,
            uint256 triggerReward,
            address payer,
            address winner,
            uint256 winnerAmount,
            uint256 devAmount,
            uint256 payReward
        )
    {
        Round storage r = _rounds[roundId];
        return (
            r.roundId,
            r.status,
            r.starter,
            r.startSnapshotBlock,
            r.startTimestamp,
            r.selectedPrizePool,
            r.startReward,
            r.eligibleWeightAtSnapshot,
            r.triggerer,
            r.endSnapshotBlock,
            r.randomnessBlock,
            r.triggerReward,
            r.payer,
            r.winner,
            r.winnerAmount,
            r.devAmount,
            r.payReward
        );
    }

    function getRoundStatus(uint256 roundId) external view returns (RoundStatus) {
        return _rounds[roundId].status;
    }

    function getRoundRandomnessBlock(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].randomnessBlock;
    }

    function getRoundSelectedPrizePool(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].selectedPrizePool;
    }

    function getRoundStartSnapshotBlock(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].startSnapshotBlock;
    }

    function getRoundEndSnapshotBlock(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].endSnapshotBlock;
    }

    function getRoundWinner(uint256 roundId) external view returns (address) {
        return _rounds[roundId].winner;
    }

    function getRoundWinnerAmount(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].winnerAmount;
    }

    function getRoundDevAmount(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].devAmount;
    }

    function getRoundStartReward(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].startReward;
    }

    function getRoundTriggerReward(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].triggerReward;
    }

    function getRoundPayReward(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].payReward;
    }

    function getRoundStarter(uint256 roundId) external view returns (address) {
        return _rounds[roundId].starter;
    }

    function getRoundTriggerer(uint256 roundId) external view returns (address) {
        return _rounds[roundId].triggerer;
    }

    function getRoundPayer(uint256 roundId) external view returns (address) {
        return _rounds[roundId].payer;
    }

    function getCurrentPayoutBps() public view returns (uint16) {
        uint256 available = availableLotteryBalance();
        if (available < tier1MaxBalance) return tier1PayoutBps;
        if (available < tier2MaxBalance) return tier2PayoutBps;
        if (available < tier3MaxBalance) return tier3PayoutBps;
        return tier4PayoutBps;
    }

    function getCurrentPrizeAmount() public view returns (uint256) {
        uint256 available = availableLotteryBalance();
        if (available < MIN_LOTTERY_BALANCE) {
            return 0;
        }
        uint256 prizeByTier = (available * getCurrentPayoutBps()) / 10_000;
        if (prizeByTier < MIN_LOTTERY_BALANCE) {
            return MIN_LOTTERY_BALANCE;
        }
        if (prizeByTier > HARD_MAX_PRIZE_PAYOUT) {
            return HARD_MAX_PRIZE_PAYOUT;
        }
        return prizeByTier;
    }

    // ══════════════════════════════════════════════
    //  Owner functions
    // ══════════════════════════════════════════════

    function setPayoutTiers(
        uint256 _tier1MaxBalance,
        uint256 _tier2MaxBalance,
        uint256 _tier3MaxBalance,
        uint16 _tier1PayoutBps,
        uint16 _tier2PayoutBps,
        uint16 _tier3PayoutBps,
        uint16 _tier4PayoutBps
    ) external onlyOwner settingsMutable {
        require(_tier1MaxBalance >= INITIAL_TIER1_MAX, "Tier1 below initial");
        require(_tier2MaxBalance >= INITIAL_TIER2_MAX, "Tier2 below initial");
        require(_tier3MaxBalance >= INITIAL_TIER3_MAX, "Tier3 below initial");

        require(_tier1MaxBalance <= HARD_TIER1_MAX, "Tier1 too high");
        require(_tier2MaxBalance <= HARD_TIER2_MAX, "Tier2 too high");
        require(_tier3MaxBalance <= HARD_TIER3_MAX, "Tier3 too high");

        require(_tier1MaxBalance < _tier2MaxBalance, "Bad tiers");
        require(_tier2MaxBalance < _tier3MaxBalance, "Bad tiers");

        require(_tier1PayoutBps >= INITIAL_TIER1_BPS, "Tier1 bps below initial");
        require(_tier2PayoutBps >= INITIAL_TIER2_BPS, "Tier2 bps below initial");
        require(_tier3PayoutBps >= INITIAL_TIER3_BPS, "Tier3 bps below initial");
        require(_tier4PayoutBps >= INITIAL_TIER4_BPS, "Tier4 bps below initial");

        require(_tier1PayoutBps <= HARD_TIER1_BPS, "Tier1 bps too high");
        require(_tier2PayoutBps <= HARD_TIER2_BPS, "Tier2 bps too high");
        require(_tier3PayoutBps <= HARD_TIER3_BPS, "Tier3 bps too high");
        require(_tier4PayoutBps <= HARD_TIER4_BPS, "Tier4 bps too high");

        require(_tier1PayoutBps >= _tier2PayoutBps, "Bad payout slope");
        require(_tier2PayoutBps >= _tier3PayoutBps, "Bad payout slope");
        require(_tier3PayoutBps >= _tier4PayoutBps, "Bad payout slope");

        tier1MaxBalance = _tier1MaxBalance;
        tier2MaxBalance = _tier2MaxBalance;
        tier3MaxBalance = _tier3MaxBalance;
        tier1PayoutBps = _tier1PayoutBps;
        tier2PayoutBps = _tier2PayoutBps;
        tier3PayoutBps = _tier3PayoutBps;
        tier4PayoutBps = _tier4PayoutBps;

        emit PayoutTiersUpdated(
            _tier1MaxBalance,
            _tier2MaxBalance,
            _tier3MaxBalance,
            _tier1PayoutBps,
            _tier2PayoutBps,
            _tier3PayoutBps,
            _tier4PayoutBps
        );
    }

    function setDevFeeReceiver(address _devFeeReceiver) external onlyOwner settingsMutable {
        require(_devFeeReceiver != address(0), "Zero dev fee receiver");
        address oldReceiver = devFeeReceiver;
        devFeeReceiver = _devFeeReceiver;
        emit DevFeeReceiverUpdated(oldReceiver, _devFeeReceiver);
    }

    function setRoundDuration(uint256 newDuration) external onlyOwner settingsMutable {
        require(!_hasActiveRound(), "Lottery pending");
        require(newDuration >= MIN_ROUND_DURATION, "Duration too short");
        require(newDuration <= MAX_ROUND_DURATION, "Duration too long");

        uint256 oldDuration = roundDuration;
        roundDuration = newDuration;
        emit RoundDurationSet(oldDuration, newDuration);
    }

    function renounceOwnership() public override onlyOwner {
        require(token.settingsFrozenForever(), "Settings not frozen");
        super.renounceOwnership();
    }

    // ══════════════════════════════════════════════
    //  Lottery Actions
    // ══════════════════════════════════════════════

    function startLotteryEpoch() external nonReentrant {
        _startLotteryEpoch(msg.sender);
    }

    function triggerDraw(uint256 roundId) external nonReentrant {
        _triggerDraw(roundId, msg.sender);
    }

    function payLottery(uint256 roundId) external nonReentrant {
        _payLottery(roundId, MAX_WINNER_ATTEMPTS, msg.sender);
    }

    function payLottery(uint256 roundId, uint256 maxAttempts) external nonReentrant {
        require(maxAttempts > 0, "No attempts");
        require(maxAttempts <= MAX_WINNER_ATTEMPTS, "Too many attempts");
        _payLottery(roundId, maxAttempts, msg.sender);
    }

    // ══════════════════════════════════════════════
    //  Auto Action
    // ══════════════════════════════════════════════

    function autoLotteryStep(address rewardTo, uint256 maxPayAttempts)
        external
        nonReentrant
        returns (AutoLotteryAction action, uint256 roundId)
    {
        require(rewardTo != address(0), "Zero rewardTo");

        uint256 rId = currentRoundId;
        RoundStatus s = _rounds[rId].status;

        if (s == RoundStatus.EPOCH_STARTED) {
            Round storage r = _rounds[rId];
            if (block.timestamp > r.startTimestamp + roundDuration + TRIGGER_DRAW_GRACE_PERIOD) {
                _expireStartedEpoch(rId);
                return (AutoLotteryAction.ExpireStartedEpoch, rId);
            }
            if (block.timestamp >= r.startTimestamp + roundDuration) {
                _triggerDraw(rId, rewardTo);
                return (AutoLotteryAction.TriggerDraw, rId);
            }
            return (AutoLotteryAction.None, 0);
        } else if (s == RoundStatus.DRAW_TRIGGERED) {
            Round storage r = _rounds[rId];
            if (r.randomnessBlockHash == bytes32(0) && block.number > r.randomnessBlock + BLOCKHASH_LOOKBACK_LIMIT) {
                _expireLottery(rId);
                return (AutoLotteryAction.ExpireDraw, rId);
            }
            if (block.number > r.randomnessBlock) {
                if (maxPayAttempts == 0) maxPayAttempts = MAX_WINNER_ATTEMPTS;
                if (maxPayAttempts > MAX_WINNER_ATTEMPTS) maxPayAttempts = MAX_WINNER_ATTEMPTS;
                _payLottery(rId, maxPayAttempts, rewardTo);
                return (AutoLotteryAction.PayLottery, rId);
            }
            return (AutoLotteryAction.None, 0);
        } else {
            // Check start conditions safely
            if (
                token.tradingActivatedAt() != 0 && block.timestamp >= token.tradingActivatedAt() + FIRST_LOTTERY_DELAY
                    && block.timestamp >= lastRoundStartedAt + MIN_ROUND_START_SPACING
            ) {
                if (isLotteryReady()) {
                    // Note: We use staticcall internally so we don't revert swap if it reverts
                    try token.canBeginLotterySnapshot() returns (bool canStart) {
                        if (canStart) {
                            _startLotteryEpoch(rewardTo);
                            return (AutoLotteryAction.StartEpoch, currentRoundId);
                        }
                    } catch {}
                }
            }
            return (AutoLotteryAction.None, 0);
        }
    }

    modifier onlyToken() {
        require(msg.sender == address(token), "Not token");
        _;
    }

    modifier settingsMutable() {
        require(!token.settingsFrozenForever(), "Settings frozen forever");
        _;
    }

    // ══════════════════════════════════════════════
    //  Internal Logic
    // ══════════════════════════════════════════════

    function _startLotteryEpoch(address starter) internal {
        require(token.tradingActivatedAt() != 0, "Trading not active");
        require(block.timestamp >= token.tradingActivatedAt() + FIRST_LOTTERY_DELAY, "Too early after launch");
        require(!_hasActiveRound(), "Active round");
        require(block.timestamp >= lastRoundStartedAt + MIN_ROUND_START_SPACING, "Interval not passed");

        uint256 selectedPrizePool = getCurrentPrizeAmount();
        require(selectedPrizePool >= MIN_LOTTERY_BALANCE, "Prize too small");

        uint256 nextRoundId = currentRoundId + 1;
        (uint256 snapshotBlock, uint256 snapshotWeight) = token.beginLotterySnapshot(nextRoundId);
        require(snapshotWeight > 0, "No eligible weight");
        roundRemainingWeight[nextRoundId] = snapshotWeight;
        token.setDiamondHandsEpochActive(nextRoundId, true);

        Round storage r = _rounds[nextRoundId];

        r.roundId = nextRoundId;
        r.status = RoundStatus.EPOCH_STARTED;
        r.starter = starter;
        r.devFeeReceiverForRound = devFeeReceiver;
        r.startSnapshotBlock = snapshotBlock;
        r.startTimestamp = block.timestamp;
        r.selectedPrizePool = selectedPrizePool;
        r.startReward = _actionReward(selectedPrizePool, START_REWARD_BPS);
        r.eligibleWeightAtSnapshot = snapshotWeight;

        reservedPrizePool += selectedPrizePool;
        currentRoundId = nextRoundId;

        emit LotteryEpochStarted(
            nextRoundId, starter, r.startSnapshotBlock, selectedPrizePool, r.eligibleWeightAtSnapshot
        );
    }

    function _triggerDraw(uint256 roundId, address triggerer) internal {
        Round storage r = _rounds[roundId];

        require(r.status == RoundStatus.EPOCH_STARTED, "Wrong status");
        require(block.timestamp >= r.startTimestamp + roundDuration, "Holding epoch not finished");
        require(block.timestamp < r.startTimestamp + roundDuration + TRIGGER_DRAW_GRACE_PERIOD, "Grace period missed");

        r.endSnapshotBlock = block.number - 1;
        r.triggerTimestamp = block.timestamp;
        r.randomnessBlock = block.number + DRAW_DELAY_BLOCKS;
        r.triggerer = triggerer;
        r.triggerReward = _actionReward(r.selectedPrizePool, TRIGGER_REWARD_BPS);
        r.status = RoundStatus.DRAW_TRIGGERED;
        token.setDiamondHandsEpochActive(roundId, false);

        emit DrawTriggered(roundId, triggerer, r.endSnapshotBlock, r.randomnessBlock);
    }

    function _payLottery(uint256 roundId, uint256 maxAttempts, address payer) internal {
        Round storage r = _rounds[roundId];

        require(r.status == RoundStatus.DRAW_TRIGGERED, "Wrong status");
        if (roundRemainingWeight[roundId] == 0) {
            _expireZeroRemainingWeight(r);
            return;
        }

        bytes32 h = r.randomnessBlockHash;
        if (h == bytes32(0)) {
            require(block.number > r.randomnessBlock, "Randomness not ready");
            require(block.number <= r.randomnessBlock + BLOCKHASH_LOOKBACK_LIMIT, "Blockhash expired");
            h = blockhash(r.randomnessBlock);
            require(h != bytes32(0), "Invalid blockhash");
            r.randomnessBlockHash = h;
        }

        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(h, r.roundId, r.startSnapshotBlock, r.selectedPrizePool, address(this), block.chainid)
            )
        );

        uint256 startAttempt = roundAttemptsCursor[roundId];
        uint256 remaining = MAX_TOTAL_ROUND_ATTEMPTS - startAttempt;
        if (maxAttempts > remaining) maxAttempts = remaining;
        uint256 endAttempt = startAttempt + maxAttempts;

        (address winner, uint256 attemptsUsed) = _findWinner(r, seed, startAttempt, endAttempt);

        roundAttemptsCursor[roundId] = startAttempt + attemptsUsed;
        emit LotterySelectionAttempted(roundId, attemptsUsed, winner != address(0));

        if (winner != address(0)) {
            _processWinner(r, winner, payer);
        } else if (roundRemainingWeight[roundId] == 0) {
            _expireZeroRemainingWeight(r);
        } else if (startAttempt + attemptsUsed >= MAX_TOTAL_ROUND_ATTEMPTS) {
            r.status = RoundStatus.EXPIRED;
            reservedPrizePool -= r.selectedPrizePool;
            lastRoundStartedAt = r.startTimestamp;
            token.endLotterySnapshot(roundId);
            emit LotteryExpired(roundId, r.selectedPrizePool);
        }
    }

    function expireStartedEpoch(uint256 roundId) external nonReentrant {
        _expireStartedEpoch(roundId);
    }

    function _expireStartedEpoch(uint256 roundId) internal {
        Round storage r = _rounds[roundId];

        require(r.status == RoundStatus.EPOCH_STARTED, "Wrong status");
        require(
            block.timestamp >= r.startTimestamp + roundDuration + TRIGGER_DRAW_GRACE_PERIOD, "Grace period not missed"
        );

        r.status = RoundStatus.EXPIRED;
        reservedPrizePool -= r.selectedPrizePool;
        lastRoundStartedAt = r.startTimestamp;
        token.setDiamondHandsEpochActive(roundId, false);
        token.endLotterySnapshot(roundId);

        emit LotteryExpired(roundId, r.selectedPrizePool);
    }

    function expireZeroRemainingWeight(uint256 roundId) external nonReentrant {
        Round storage r = _rounds[roundId];
        require(r.status == RoundStatus.EPOCH_STARTED || r.status == RoundStatus.DRAW_TRIGGERED, "Wrong status");
        require(roundRemainingWeight[roundId] == 0, "Remaining weight");
        _expireZeroRemainingWeight(r);
    }

    function _expireZeroRemainingWeight(Round storage r) internal {
        if (r.status == RoundStatus.EPOCH_STARTED) {
            token.setDiamondHandsEpochActive(r.roundId, false);
        }
        r.status = RoundStatus.EXPIRED;
        reservedPrizePool -= r.selectedPrizePool;
        lastRoundStartedAt = r.startTimestamp;
        token.endLotterySnapshot(r.roundId);
        emit LotteryExpired(r.roundId, r.selectedPrizePool);
    }

    function expireLottery(uint256 roundId) external nonReentrant {
        _expireLottery(roundId);
    }

    function _expireLottery(uint256 roundId) internal {
        Round storage r = _rounds[roundId];

        require(r.status == RoundStatus.DRAW_TRIGGERED, "Wrong status");
        require(r.randomnessBlockHash == bytes32(0), "Randomness captured");
        require(block.number > r.randomnessBlock + BLOCKHASH_LOOKBACK_LIMIT, "Not expired");

        r.status = RoundStatus.EXPIRED;
        reservedPrizePool -= r.selectedPrizePool;
        lastRoundStartedAt = r.startTimestamp;
        token.endLotterySnapshot(roundId);

        emit LotteryExpired(roundId, r.selectedPrizePool);
    }

    // ══════════════════════════════════════════════
    //  Payout helpers
    // ══════════════════════════════════════════════

    function _storePendingWinnerPayout(address winner, uint256 amount) internal {
        if (amount == 0) return;

        pendingWinnerPayout[winner] += amount;
        totalPendingWinnerPayouts += amount;

        if (!pendingWinnerQueued[winner] && !pendingWinnerAutoRetryDisabled[winner]) {
            pendingWinnerQueued[winner] = true;
            pendingWinnerQueue.push(winner);
            pendingWinnerQueuedCount++;
            emit PendingWinnerQueued(winner);
        }

        emit WinnerPayoutStored(winner, amount);
    }

    function _attemptPendingWinnerPayout(address winner, bool isAutoRetry) internal returns (bool) {
        uint256 amount = pendingWinnerPayout[winner];
        if (amount == 0) {
            if (pendingWinnerQueued[winner]) {
                pendingWinnerQueued[winner] = false;
                if (pendingWinnerQueuedCount > 0) pendingWinnerQueuedCount--;
            }
            pendingWinnerRetryCount[winner] = 0;
            pendingWinnerAutoRetryDisabled[winner] = false;
            return true;
        }

        pendingWinnerPayout[winner] = 0;
        totalPendingWinnerPayouts -= amount;

        uint256 gasLimit = isAutoRetry ? AUTO_PAYOUT_GAS : MANUAL_PAYOUT_GAS;
        (bool ok,) = payable(winner).call{value: amount, gas: gasLimit}("");

        if (ok) {
            if (pendingWinnerQueued[winner]) {
                pendingWinnerQueued[winner] = false;
                if (pendingWinnerQueuedCount > 0) pendingWinnerQueuedCount--;
            }
            pendingWinnerRetryCount[winner] = 0;
            pendingWinnerAutoRetryDisabled[winner] = false;

            emit PendingWinnerPayoutPaid(winner, amount, msg.sender);
            return true;
        }

        pendingWinnerPayout[winner] = amount;
        totalPendingWinnerPayouts += amount;

        if (isAutoRetry) {
            uint8 nextCount = pendingWinnerRetryCount[winner] + 1;
            pendingWinnerRetryCount[winner] = nextCount;

            if (nextCount >= MAX_AUTO_PAYOUT_RETRIES) {
                if (pendingWinnerQueued[winner]) {
                    pendingWinnerQueued[winner] = false;
                    if (pendingWinnerQueuedCount > 0) pendingWinnerQueuedCount--;
                }
                pendingWinnerAutoRetryDisabled[winner] = true;
                emit PendingWinnerAutoRetryDisabled(winner, amount);
            }
        }

        emit PendingWinnerPayoutFailed(winner, amount, msg.sender, pendingWinnerRetryCount[winner]);
        return false;
    }

    function claimPendingWinnerPayout() external nonReentrant {
        _attemptPendingWinnerPayout(msg.sender, false);
    }

    function payPendingWinner(address winner) public nonReentrant {
        _attemptPendingWinnerPayout(winner, false);
    }

    function processPendingWinnerPayouts(uint256 maxSteps) external nonReentrant {
        _processPendingWinnerPayouts(maxSteps);
    }

    function claimPendingDevPayout() external nonReentrant {
        _attemptPendingDevPayout(msg.sender);
    }

    function payPendingDevPayout(address receiver) external nonReentrant {
        _attemptPendingDevPayout(receiver);
    }

    function _storePendingDevPayout(address receiver, uint256 amount) internal {
        if (amount == 0) return;

        pendingDevPayout[receiver] += amount;
        totalPendingDevPayouts += amount;
        emit PendingDevPayoutStored(receiver, amount);
    }

    function _attemptPendingDevPayout(address receiver) internal returns (bool) {
        uint256 amount = pendingDevPayout[receiver];
        if (amount == 0) return true;

        pendingDevPayout[receiver] = 0;
        totalPendingDevPayouts -= amount;

        (bool ok,) = payable(receiver).call{value: amount, gas: MANUAL_PAYOUT_GAS}("");
        if (ok) {
            emit PendingDevPayoutPaid(receiver, amount, msg.sender);
            return true;
        }

        pendingDevPayout[receiver] = amount;
        totalPendingDevPayouts += amount;
        emit PendingDevPayoutFailed(receiver, amount, msg.sender);
        return false;
    }

    function _processPendingWinnerPayouts(uint256 maxSteps) internal {
        if (maxSteps > MAX_PENDING_WINNER_PAYOUT_STEPS) {
            maxSteps = MAX_PENDING_WINNER_PAYOUT_STEPS;
        }

        uint256 len = pendingWinnerQueue.length;
        uint256 steps = 0;

        while (pendingWinnerQueueCursor < len && steps < maxSteps) {
            address winner = pendingWinnerQueue[pendingWinnerQueueCursor++];
            steps++;

            if (!pendingWinnerQueued[winner]) {
                continue;
            }

            if (pendingWinnerPayout[winner] == 0) {
                if (pendingWinnerQueued[winner]) {
                    pendingWinnerQueued[winner] = false;
                    if (pendingWinnerQueuedCount > 0) pendingWinnerQueuedCount--;
                }
                pendingWinnerRetryCount[winner] = 0;
                pendingWinnerAutoRetryDisabled[winner] = false;
                continue;
            }

            bool ok = _attemptPendingWinnerPayout(winner, true);
            if (!ok && pendingWinnerQueued[winner]) {
                pendingWinnerQueue.push(winner);
            }
        }

        if (pendingWinnerQueueCursor == pendingWinnerQueue.length) {
            delete pendingWinnerQueue;
            pendingWinnerQueueCursor = 0;
        }
    }

    function _processWinner(Round storage r, address winner, address payer) internal {
        uint256 payReward = _actionReward(r.selectedPrizePool, PAY_REWARD_BPS);
        uint256 devAmount = (r.selectedPrizePool * DEV_FEE_BPS) / 10_000;
        uint256 winnerAmount = r.selectedPrizePool - r.startReward - r.triggerReward - payReward - devAmount;

        r.status = RoundStatus.FULFILLED;
        r.winner = winner;
        r.winnerAmount = winnerAmount;
        r.devAmount = devAmount;
        r.payReward = payReward;
        r.payer = payer;

        reservedPrizePool -= r.selectedPrizePool;
        lastRoundStartedAt = r.startTimestamp;
        token.endLotterySnapshot(r.roundId);

        bool winnerOk = _tryPayout(winner, winnerAmount, PayoutType.Winner);
        if (!winnerOk) {
            _storePendingWinnerPayout(winner, winnerAmount);
            emit WinnerPayoutFailed(r.roundId, winner, winnerAmount);
        }

        address devReceiver = r.devFeeReceiverForRound;
        if (devReceiver == address(0)) devReceiver = devFeeReceiver;
        bool devOk = _tryPayout(devReceiver, devAmount, PayoutType.Dev);
        if (!devOk) {
            _storePendingDevPayout(devReceiver, devAmount);
        }
        _tryPayout(r.starter, r.startReward, PayoutType.StartReward);
        _tryPayout(r.triggerer, r.triggerReward, PayoutType.TriggerReward);
        _tryPayout(payer, payReward, PayoutType.PayReward);

        emit LotteryFulfilled(r.roundId, winner, winnerAmount, devAmount, r.startReward, r.triggerReward, payReward);
    }

    function _tryPayout(address to, uint256 amount, PayoutType payoutType) internal returns (bool ok) {
        if (amount == 0) return true;

        (ok,) = payable(to).call{value: amount, gas: AUTO_PAYOUT_GAS}("");

        if (ok) {
            emit DirectPayout(to, amount, payoutType);
        } else {
            emit DirectPayoutFailed(to, amount, payoutType);
        }
    }

    // ══════════════════════════════════════════════
    //  Winner selection — Fenwick Model
    // ══════════════════════════════════════════════

    enum CandidateInvalidReason {
        NONE,
        ZERO_ADDRESS,
        CONTRACT_CODE_OR_EXEMPT,
        START_BELOW_MIN,
        END_BELOW_START
    }

    function _candidateInvalidReason(Round storage r, address candidate)
        internal
        view
        returns (CandidateInvalidReason)
    {
        if (candidate == address(0)) return CandidateInvalidReason.ZERO_ADDRESS;
        if (token.isLotteryIneligible(candidate)) return CandidateInvalidReason.CONTRACT_CODE_OR_EXEMPT;

        uint256 minEligible = token.minEligibleAmount();
        uint256 startBalance = token.getPastBalance(candidate, r.startSnapshotBlock);
        uint256 endBalance = token.getPastBalance(candidate, r.endSnapshotBlock);

        if (startBalance < minEligible) return CandidateInvalidReason.START_BELOW_MIN;
        if (endBalance < startBalance) return CandidateInvalidReason.END_BELOW_START;

        return CandidateInvalidReason.NONE;
    }

    function _maybeCleanupInvalidCandidate(
        uint256 roundId,
        address candidate,
        CandidateInvalidReason reason,
        uint256 cleanupsUsed
    ) internal returns (uint256) {
        if (cleanupsUsed >= MAX_CANDIDATE_CLEANUPS_PER_CALL) {
            return cleanupsUsed;
        }

        bool permanent =
            reason == CandidateInvalidReason.CONTRACT_CODE_OR_EXEMPT || reason == CandidateInvalidReason.ZERO_ADDRESS;

        if (!permanent) {
            return cleanupsUsed;
        }

        try token.refreshEligibility(candidate) {
            emit CandidateEligibilityCleanupAttempted(roundId, candidate, uint8(reason));
        } catch {
            // Cleanup failure must never block payLottery.
        }

        return cleanupsUsed + 1;
    }

    function _forfeitureNodeValue(uint256 index, uint256 roundId) internal view returns (uint256) {
        ForfeitureNode storage node = forfeitureNodes[index];
        return node.roundId == roundId ? node.weight : 0;
    }

    function _addForfeitureWeight(uint256 index, uint256 roundId, uint256 weight) internal {
        for (uint256 nodeIndex = index; nodeIndex < FENWICK_TREE_SIZE; nodeIndex += nodeIndex & (~nodeIndex + 1)) {
            ForfeitureNode storage node = forfeitureNodes[nodeIndex];
            uint256 current = node.roundId == roundId ? node.weight : 0;
            uint256 next = current + weight;
            require(next <= type(uint192).max, "Forfeiture overflow");
            node.roundId = uint64(roundId);
            node.weight = uint192(next);
        }
    }

    function forfeitRoundAccount(uint256 roundId, uint256 index, address account) external returns (bool) {
        require(msg.sender == address(token), "Only token");
        require(_rounds[roundId].status == RoundStatus.EPOCH_STARTED, "Forfeiture phase closed");
        return _forfeitRoundIndex(roundId, index, account);
    }

    function _forfeitRoundIndex(uint256 roundId, uint256 index, address account) internal returns (bool) {
        if (index == 0 || index >= FENWICK_TREE_SIZE || forfeitedRoundByIndex[index] == roundId) return false;

        address roundHolder = token.getHolderByEligibleIndexAtRound(index, roundId);
        if (account != address(0) && roundHolder != account) return false;

        uint256 startWeight = token.getEligibleWeightAtRound(index, roundId);
        if (startWeight == 0) return false;

        uint256 remaining = roundRemainingWeight[roundId];
        require(remaining >= startWeight, "Remaining weight underflow");
        forfeitedRoundByIndex[index] = uint64(roundId);
        _addForfeitureWeight(index, roundId, startWeight);
        remaining -= startWeight;
        roundRemainingWeight[roundId] = remaining;

        emit RoundWeightForfeited(roundId, roundHolder, index, startWeight);
        emit RoundRemainingWeightUpdated(roundId, remaining);
        return true;
    }

    function treeFindByCumulativeRemaining(uint256 target, uint256 roundId) public view returns (uint256) {
        require(
            _rounds[roundId].status == RoundStatus.EPOCH_STARTED
                || _rounds[roundId].status == RoundStatus.DRAW_TRIGGERED,
            "Round not active"
        );
        require(target < roundRemainingWeight[roundId], "Target out of bounds");

        uint256 index;
        uint256 bitMask = FENWICK_TREE_SIZE >> 1;
        while (bitMask != 0) {
            uint256 tIdx = index + bitMask;
            if (tIdx < FENWICK_TREE_SIZE) {
                uint256 snapshotNode = token.getFenwickNodeValueAtRound(tIdx, roundId);
                uint256 excludedNode = _forfeitureNodeValue(tIdx, roundId);
                require(snapshotNode >= excludedNode, "Residual tree underflow");
                uint256 residualNode = snapshotNode - excludedNode;
                if (residualNode <= target) {
                    index = tIdx;
                    target -= residualNode;
                }
            }
            bitMask >>= 1;
        }
        return index + 1;
    }

    function _findWinner(Round storage r, uint256 seed, uint256 startAttempt, uint256 endAttempt)
        internal
        returns (address winner, uint256 attemptsUsed)
    {
        uint256 cleanupsUsed = 0;

        for (uint256 i = startAttempt; i < endAttempt; i++) {
            uint256 remainingWeight = roundRemainingWeight[r.roundId];
            if (remainingWeight == 0) break;

            attemptsUsed++;

            bytes32 attemptSeed = keccak256(abi.encodePacked(seed, r.roundId, i, address(this)));

            uint256 target = uint256(attemptSeed) % remainingWeight;

            uint256 index = treeFindByCumulativeRemaining(target, r.roundId);
            address candidate = token.getHolderByEligibleIndexAtRound(index, r.roundId);

            CandidateInvalidReason reason = _candidateInvalidReason(r, candidate);

            if (reason == CandidateInvalidReason.NONE) {
                return (candidate, attemptsUsed);
            } else {
                _forfeitRoundIndex(r.roundId, index, address(0));
                cleanupsUsed = _maybeCleanupInvalidCandidate(r.roundId, candidate, reason, cleanupsUsed);
            }
        }

        return (address(0), attemptsUsed);
    }
}
