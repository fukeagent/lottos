// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ILotteryEngine {
    function isLotteryPending() external view returns (bool);
    function autoLotteryStep(address rewardTo, uint256 maxPayAttempts) external returns (uint8 action, uint256 roundId);
    function processPendingWinnerPayouts(uint256 maxSteps) external;
    function forfeitRoundAccount(uint256 roundId, uint256 index, address account) external returns (bool);
}

interface IOfficialPoolQuote {
    function quoteReady() external view returns (bool);

    function quoteTokenToETH(uint256 tokenAmount) external view returns (uint256 expectedEthOut);
}

interface IRouter {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function WETH() external pure returns (address);
}

interface IV2LikeExternalPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IV3LikeExternalPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

contract RobinhoodToken is ERC20, Ownable2Step, ReentrancyGuard {
    enum ExternalPoolKind {
        Unknown,
        UniswapV2Like,
        UniswapV3Like
    }
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    uint256 public minEligibleAmount;
    uint256 public constant MIN_ELIGIBLE_AMOUNT_FLOOR = 1 ether;
    uint256 public constant MIN_ELIGIBLE_AMOUNT_CEILING = 1_000_000 ether;

    uint256 public tradingActivatedAt;
    bool public launchConfigLocked;

    struct Checkpoint {
        uint64 fromBlock;
        uint192 balance;
    }
    mapping(address => Checkpoint[]) public checkpoints;

    mapping(address => bool) public isTradingExempt;
    mapping(address => bool) public isMaxWalletExempt;
    mapping(address => bool) public isEligibilityExempt;

    address public lotteryEngine;

    // Fenwick Tree
    uint256 public totalEligibleBalance;
    uint256 public nextEligibleIndex = 1;
    mapping(address => uint256) public eligibleIndexOf;
    mapping(uint256 => address) public holderAtIndex;
    uint256 public constant TREE_SIZE = 1 << 24;

    uint256 public constant NORMAL_ALLOC_SWEEP_LIMIT = 16;
    uint256 public constant HIGH_PRESSURE_ALLOC_SWEEP_LIMIT = 256;
    uint256 public constant ROUND_START_SWEEP_LIMIT = 512;
    uint256 public constant TREE_PRESSURE_BPS = 9000; // 90%

    uint256[] internal freeEligibleIndices;
    uint256[] internal pendingFreeIndices;
    uint256 public pendingFreeSweepCursor;
    mapping(uint256 => uint64) public pendingFreeRoundByIndex;

    struct FenwickNode {
        uint192 current;
        uint64 openingBlock;
        uint192 opening;
        uint64 frozenRoundId;
        uint192 frozen;
    }

    mapping(uint256 => FenwickNode) internal fenwickNodes;
    mapping(address => uint256) public eligibleWeightOf;

    // Active round snapshot state
    uint64 public activeSnapshotRoundId;
    uint64 public activeSnapshotBlock; // block.number - 1
    uint64 public activeSnapshotStartedAtBlock; // block.number where beginLotterySnapshot was called
    uint192 public activeSnapshotTotalWeight;

    // Strict diamond-hands transfer-phase gate. Residual weight accounting is
    // held by LotteryEngine to keep this hot-path token deployable.
    bool public diamondHandsEpochActive;
    uint64 public forfeitureRoundId;

    uint64 public blockOpeningEligibleBalanceBlock;
    uint256 public blockOpeningEligibleBalance;

    mapping(uint256 => uint64) public holderOpeningBlockByIndex;
    mapping(uint256 => address) public holderOpeningAtIndex;

    // External tax
    mapping(address => bool) public isTaxedExternalPool;
    mapping(address => ExternalPoolKind) public taxedExternalPoolKind;
    mapping(address => bool) public isOfficialTaxExemptPoolOrManager;

    uint256 public constant MAX_EXTERNAL_TAX_BPS = 1000; // 10%
    uint256 public constant MIN_EXTERNAL_TAX_BPS = 100; // 1%
    uint256 public constant EXTERNAL_TAX_DECAY_DURATION = 30 minutes;

    bool public autoSwapEnabled = false; // owner turns this on post-launch
    bool private inSwap;

    IOfficialPoolQuote public officialPoolQuote;
    uint256 public constant QUOTE_GAS_LIMIT = 60_000;

    uint256 public autoSwapSlippageBps = 300; // 3%
    uint256 public constant MAX_AUTO_SWAP_SLIPPAGE_BPS = 1_000; // 10%
    uint256 public constant MIN_AUTO_SWAP_SLIPPAGE_BPS = 50; // 0.5%

    uint256 public minAutoSwapExpectedEthOut; // optional value floor, not slippage protection

    uint256 public swapThreshold = 100_000 ether; // 0.01% of total supply
    uint256 public maxSwapAmount = 200_000 ether; // 0.02% of total supply
    uint256 public swapCooldown = 15 minutes; // longer than a mature-pool default
    uint256 public lastAutoSwapAttemptAt;
    uint256 public lastAutoSwapSuccessAt;

    /// @notice Backwards-compatible success timestamp alias.
    function lastAutoSwapAt() external view returns (uint256) {
        return lastAutoSwapSuccessAt;
    }

    uint256 public constant MAX_SWAP_THRESHOLD = 5_000_000 ether;
    uint256 public constant HARD_MAX_SWAP_AMOUNT = 1_000_000 ether;
    uint256 public constant MAX_SWAP_COOLDOWN = 1 hours;

    address public taxSwapRouter;
    bool public taxSwapRouterLocked;

    bool public settingsFrozenForever;
    mapping(address => bool) public contractLotteryAllowed;

    event SettingsFrozenForever(address indexed owner);
    event ContractLotteryAllowedSet(address indexed account, bool allowed);

    event HolderBecameEligible(address indexed holder, uint256 balance);
    event HolderRemovedFromEligibility(address indexed holder, uint256 balance);
    event EligibilityIndexExhausted(address indexed account, uint256 attemptedIndex);
    event EligibleIndexAllocated(address indexed holder, uint256 indexed index);
    event EligibleIndexReused(address indexed holder, uint256 indexed index);
    event EligibleIndexQueuedForFree(address indexed holder, uint256 indexed index, uint256 indexed roundId);
    event EligibleIndexFreed(address indexed holder, uint256 indexed index);
    event EligibleIndexFreeCanceled(address indexed holder, uint256 indexed index);
    event TradingActivated(uint256 timestamp);
    event LaunchConfigLocked();

    event TaxedExternalPoolUpdated(address indexed pool, bool taxed);
    event TaxedExternalPoolValidated(address indexed pool, bool taxed, ExternalPoolKind kind);
    event OfficialTaxExemptUpdated(address indexed account, bool exempt);
    event TaxSwapRouterSet(address indexed router);
    event AutoSwapConfigUpdated(bool enabled, uint256 threshold, uint256 maxAmount, uint256 cooldown);
    event OfficialPoolQuoteUpdated(address indexed oldQuote, address indexed newQuote);
    event AutoSwapSlippageUpdated(uint256 oldBps, uint256 newBps);
    event MinAutoSwapExpectedEthOutUpdated(uint256 oldAmount, uint256 newAmount);

    event LotterySnapshotStarted(uint256 indexed roundId, uint256 snapshotBlock, uint256 totalWeight);
    event LotterySnapshotEnded(uint256 indexed roundId);
    event LotterySnapshotStartBlocked(uint256 indexed roundId, uint256 mutationBlock, uint256 currentBlock);
    event DiamondHandsEpochStatusSet(uint256 indexed roundId, bool active);

    event AutoSwapSkipped(uint256 amount, string reason);
    event AutoSwapSucceeded(uint256 amount, uint256 minEthOut);
    event AutoSwapFailed(uint256 amount, uint256 minEthOut, bytes reason);
    event TokenLotteryAutoActionSucceeded(uint256 indexed roundId, uint8 action, address indexed rewardTo);
    event TokenLotteryAutoActionSkipped(uint8 action, string reason);
    event TokenLotteryAutoActionFailed(bytes reason);

    constructor() ERC20("Robinhood", "RHT") Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY);

        minEligibleAmount = 1000 ether; // reasonable default

        isTradingExempt[msg.sender] = true;
        isMaxWalletExempt[msg.sender] = true;
        isEligibilityExempt[msg.sender] = true;

        isTradingExempt[address(this)] = true;
        isMaxWalletExempt[address(this)] = true;
        isEligibilityExempt[address(this)] = true;
    }

    receive() external payable {}

    modifier settingsMutable() {
        require(!settingsFrozenForever, "Settings frozen forever");
        _;
    }

    function setMinEligibleAmount(uint256 newAmount) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        require(newAmount >= MIN_ELIGIBLE_AMOUNT_FLOOR, "Too low");
        require(newAmount <= MIN_ELIGIBLE_AMOUNT_CEILING, "Too high");
        minEligibleAmount = newAmount;
    }

    function setExemptions(address account, bool trading, bool maxWallet, bool eligibility)
        external
        onlyOwner
        settingsMutable
    {
        require(!launchConfigLocked, "Launch config locked");
        isTradingExempt[account] = trading;
        isMaxWalletExempt[account] = maxWallet;
        isEligibilityExempt[account] = eligibility;
    }

    function setLotteryEngine(address _engine) external onlyOwner settingsMutable {
        require(lotteryEngine == address(0), "Engine already set");
        require(_engine != address(0), "Invalid engine");
        lotteryEngine = _engine;
    }

    function activateTrading() external onlyOwner settingsMutable {
        require(tradingActivatedAt == 0, "Already active");
        tradingActivatedAt = block.timestamp;
        launchConfigLocked = true;

        emit TradingActivated(block.timestamp);
        emit LaunchConfigLocked();
    }

    // External Pool Admin
    function setTaxedExternalPool(address pool, bool taxed) external onlyOwner settingsMutable {
        require(pool.code.length > 0, "Not contract");
        if (taxed) {
            _validateTaxedExternalPool(pool);
            taxedExternalPoolKind[pool] = _externalPoolKind(pool);
        } else {
            taxedExternalPoolKind[pool] = ExternalPoolKind.Unknown;
        }
        isTaxedExternalPool[pool] = taxed;
        emit TaxedExternalPoolUpdated(pool, taxed);
        emit TaxedExternalPoolValidated(pool, taxed, taxedExternalPoolKind[pool]);
    }

    function _validateTaxedExternalPool(address pool) internal view {
        require(pool != address(this), "Token contract");
        require(pool != lotteryEngine, "Lottery engine");
        require(pool != taxSwapRouter, "Tax swap router");
        require(pool != address(officialPoolQuote), "Official quote");
        require(!isOfficialTaxExemptPoolOrManager[pool], "Official path");
        require(!contractLotteryAllowed[pool], "Lottery allowed contract");
        require(_externalPoolKind(pool) != ExternalPoolKind.Unknown, "Invalid external pool");
    }

    function _externalPoolKind(address pool) internal view returns (ExternalPoolKind) {
        address token0;
        address token1;

        try IV2LikeExternalPool(pool).token0() returns (address value) {
            token0 = value;
        } catch {
            return ExternalPoolKind.Unknown;
        }
        try IV2LikeExternalPool(pool).token1() returns (address value) {
            token1 = value;
        } catch {
            return ExternalPoolKind.Unknown;
        }
        if (token0 != address(this) && token1 != address(this)) return ExternalPoolKind.Unknown;

        try IV2LikeExternalPool(pool).getReserves() returns (uint112, uint112, uint32) {
            return ExternalPoolKind.UniswapV2Like;
        } catch {}

        try IV3LikeExternalPool(pool).fee() returns (uint24) {}
        catch {
            return ExternalPoolKind.Unknown;
        }
        try IV3LikeExternalPool(pool).slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
            return ExternalPoolKind.UniswapV3Like;
        } catch {
            return ExternalPoolKind.Unknown;
        }
    }

    function setOfficialTaxExemptPoolOrManager(address account, bool exempt) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        require(account.code.length > 0, "Not contract");
        if (exempt) {
            require(!isTaxedExternalPool[account], "Taxed external pool");
        }
        isOfficialTaxExemptPoolOrManager[account] = exempt;
        emit OfficialTaxExemptUpdated(account, exempt);
    }

    function setOfficialPoolQuote(address quote) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        require(quote != address(0), "Zero quote");
        require(quote.code.length > 0, "Quote not contract");

        address old = address(officialPoolQuote);
        officialPoolQuote = IOfficialPoolQuote(quote);

        emit OfficialPoolQuoteUpdated(old, quote);
    }

    function setAutoSwapSlippageBps(uint256 bps) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        require(bps >= MIN_AUTO_SWAP_SLIPPAGE_BPS, "Slippage too low");
        require(bps <= MAX_AUTO_SWAP_SLIPPAGE_BPS, "Slippage too high");

        uint256 old = autoSwapSlippageBps;
        autoSwapSlippageBps = bps;

        emit AutoSwapSlippageUpdated(old, bps);
    }

    function setMinAutoSwapExpectedEthOut(uint256 amount) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        uint256 old = minAutoSwapExpectedEthOut;
        minAutoSwapExpectedEthOut = amount;

        emit MinAutoSwapExpectedEthOutUpdated(old, amount);
    }

    function setTaxSwapRouterOnce(address router) external onlyOwner settingsMutable {
        require(!launchConfigLocked, "Launch config locked");
        require(!taxSwapRouterLocked, "Router locked");
        require(taxSwapRouter == address(0), "Router already set");
        require(router != address(0), "Router zero");
        require(router.code.length > 0, "Router not contract");

        taxSwapRouter = router;
        taxSwapRouterLocked = true;

        emit TaxSwapRouterSet(router);
    }

    event AutoSwapEnabledUpdated(bool enabled);

    function setAutoSwapConfig(bool enabled, uint256 threshold, uint256 maxAmount, uint256 cooldown)
        external
        onlyOwner
        settingsMutable
    {
        require(!launchConfigLocked, "Launch config locked");
        require(taxSwapRouter != address(0), "Router not set");
        require(threshold > 0, "Threshold zero");
        require(maxAmount >= threshold, "Max too small");
        require(threshold <= MAX_SWAP_THRESHOLD, "Threshold too high");
        require(maxAmount <= HARD_MAX_SWAP_AMOUNT, "Max too high");
        require(cooldown <= MAX_SWAP_COOLDOWN, "Cooldown too high");

        autoSwapEnabled = enabled;
        swapThreshold = threshold;
        maxSwapAmount = maxAmount;
        swapCooldown = cooldown;
        emit AutoSwapConfigUpdated(enabled, threshold, maxAmount, cooldown);
    }

    function setAutoSwapEnabled(bool enabled) external onlyOwner settingsMutable {
        require(taxSwapRouter != address(0), "Router not set");
        autoSwapEnabled = enabled;
        emit AutoSwapEnabledUpdated(enabled);
    }

    uint256 public constant MAX_WALLET_START_BPS = 10; // 0.1%
    uint256 public constant MAX_WALLET_END_BPS = 200; // 2.0%
    uint256 public constant MAX_WALLET_RAMP_DURATION = 2 hours;

    function getMaxWallet() public view returns (uint256) {
        if (tradingActivatedAt == 0) return totalSupply();

        uint256 startMax = (totalSupply() * MAX_WALLET_START_BPS) / 10_000;
        uint256 endMax = (totalSupply() * MAX_WALLET_END_BPS) / 10_000;

        uint256 elapsed = block.timestamp - tradingActivatedAt;
        if (elapsed >= MAX_WALLET_RAMP_DURATION) {
            return endMax;
        }

        return startMax + ((endMax - startMax) * elapsed) / MAX_WALLET_RAMP_DURATION;
    }

    function _currentBlockOpeningOrLiveTotal() internal view returns (uint256) {
        uint64 b = uint64(block.number);
        if (blockOpeningEligibleBalanceBlock == b) {
            return blockOpeningEligibleBalance;
        }
        return totalEligibleBalance;
    }

    function canBeginLotterySnapshot() external view returns (bool) {
        return activeSnapshotRoundId == 0 && block.number > 0 && _currentBlockOpeningOrLiveTotal() > 0;
    }

    function beginLotterySnapshot(uint256 roundId) external returns (uint256 snapshotBlock, uint256 snapshotWeight) {
        require(msg.sender == lotteryEngine, "Only lottery engine");
        require(roundId != 0, "Invalid round");
        require(activeSnapshotRoundId == 0, "Snapshot active");
        require(block.number > 0, "No previous block");

        _sweepPendingFreeIndices(ROUND_START_SWEEP_LIMIT);

        snapshotBlock = block.number - 1;
        snapshotWeight = _currentBlockOpeningOrLiveTotal();

        require(snapshotWeight > 0, "No eligible weight");
        require(snapshotWeight <= type(uint192).max, "Snapshot weight overflow");

        activeSnapshotRoundId = uint64(roundId);
        activeSnapshotBlock = uint64(snapshotBlock);
        activeSnapshotStartedAtBlock = uint64(block.number);
        activeSnapshotTotalWeight = uint192(snapshotWeight);

        emit LotterySnapshotStarted(roundId, snapshotBlock, snapshotWeight);
    }

    function endLotterySnapshot(uint256 roundId) external {
        require(msg.sender == lotteryEngine, "Only lottery engine");
        require(activeSnapshotRoundId == roundId, "Wrong active round");

        diamondHandsEpochActive = false;
        forfeitureRoundId = 0;
        activeSnapshotRoundId = 0;
        activeSnapshotBlock = 0;
        activeSnapshotStartedAtBlock = 0;
        activeSnapshotTotalWeight = 0;

        emit LotterySnapshotEnded(roundId);
    }

    function setDiamondHandsEpochActive(uint256 roundId, bool active) external {
        require(msg.sender == lotteryEngine, "Only lottery engine");
        require(roundId == activeSnapshotRoundId, "Wrong active round");

        if (active) {
            require(!diamondHandsEpochActive, "Epoch already active");
            forfeitureRoundId = uint64(roundId);
        } else {
            require(forfeitureRoundId == roundId, "Wrong forfeiture round");
        }

        diamondHandsEpochActive = active;
        emit DiamondHandsEpochStatusSet(roundId, active);
    }

    function _captureHolderOpeningIfNeeded(uint256 index) internal {
        if (index == 0) return;
        uint64 b = uint64(block.number);
        if (holderOpeningBlockByIndex[index] != b) {
            holderOpeningAtIndex[index] = holderAtIndex[index];
            holderOpeningBlockByIndex[index] = b;
        }
    }

    function _captureNodeOpeningIfNeeded(uint256 index) internal {
        FenwickNode storage node = fenwickNodes[index];
        uint64 b = uint64(block.number);
        if (node.openingBlock != b) {
            node.opening = node.current;
            node.openingBlock = b;
        }
    }

    function _captureTotalOpeningIfNeeded() internal {
        uint64 b = uint64(block.number);
        if (blockOpeningEligibleBalanceBlock != b) {
            blockOpeningEligibleBalance = totalEligibleBalance;
            blockOpeningEligibleBalanceBlock = b;
        }
    }

    function _freezeNodeForActiveSnapshot(FenwickNode storage node) internal {
        uint64 roundId = activeSnapshotRoundId;

        if (roundId == 0) return;
        if (node.frozenRoundId == roundId) return;

        node.frozenRoundId = roundId;
        if (node.openingBlock == activeSnapshotStartedAtBlock) {
            node.frozen = node.opening;
        } else {
            node.frozen = node.current;
        }
    }

    function _treeUpdate(uint256 index, int256 delta) internal {
        for (; index < TREE_SIZE; index += index & (~index + 1)) {
            FenwickNode storage node = fenwickNodes[index];

            // CRITICAL:
            // 1. Capture block-opening node value before any same-block mutation.
            // 2. Freeze active snapshot before modifying current.
            // 3. Then mutate current.
            _captureNodeOpeningIfNeeded(index);
            _freezeNodeForActiveSnapshot(node);

            uint256 current = uint256(node.current);
            uint256 next;

            if (delta > 0) {
                next = current + uint256(delta);
            } else {
                uint256 absDelta = uint256(-delta);
                require(current >= absDelta, "Fenwick underflow");
                next = current - absDelta;
            }

            require(next <= type(uint192).max, "Fenwick overflow");
            node.current = uint192(next);
        }
    }

    function treePrefixSum(uint256 index) public view returns (uint256) {
        uint256 sum = 0;
        for (; index > 0; index -= index & (~index + 1)) {
            sum += fenwickNodes[index].current;
        }
        return sum;
    }

    function treeFindByCumulative(uint256 target) external view returns (uint256) {
        require(target < totalEligibleBalance, "Target out of bounds");
        uint256 index = 0;
        uint256 bitMask = TREE_SIZE >> 1;
        while (bitMask != 0) {
            uint256 tIdx = index + bitMask;
            if (tIdx < TREE_SIZE && uint256(fenwickNodes[tIdx].current) <= target) {
                index = tIdx;
                target -= fenwickNodes[tIdx].current;
            }
            bitMask >>= 1;
        }
        return index + 1;
    }

    function getEligibleTotalWeight() external view returns (uint256) {
        return totalEligibleBalance;
    }

    function _nodeValueAtRound(FenwickNode storage node, uint256 roundId) internal view returns (uint256) {
        if (node.frozenRoundId == roundId) {
            return node.frozen;
        }
        if (node.openingBlock == activeSnapshotStartedAtBlock) {
            return node.opening;
        }
        return node.current;
    }

    function treePrefixSumAtRound(uint256 index, uint256 roundId) public view returns (uint256) {
        require(roundId != 0, "Invalid round");
        require(roundId == activeSnapshotRoundId, "Round not active");

        uint256 sum = 0;

        for (; index > 0; index -= index & (~index + 1)) {
            sum += _nodeValueAtRound(fenwickNodes[index], roundId);
        }

        return sum;
    }

    function treeFindByCumulativeAtRound(uint256 target, uint256 roundId) external view returns (uint256) {
        require(roundId != 0, "Invalid round");
        require(roundId == activeSnapshotRoundId, "Round not active");
        require(target < activeSnapshotTotalWeight, "Target out of bounds");

        uint256 index = 0;
        uint256 bitMask = TREE_SIZE >> 1;

        while (bitMask != 0) {
            uint256 tIdx = index + bitMask;

            if (tIdx < TREE_SIZE) {
                uint256 nodeValue = _nodeValueAtRound(fenwickNodes[tIdx], roundId);

                if (nodeValue <= target) {
                    index = tIdx;
                    target -= nodeValue;
                }
            }

            bitMask >>= 1;
        }

        return index + 1;
    }

    function getEligibleWeightAtRound(uint256 index, uint256 roundId) public view returns (uint256) {
        require(index > 0 && index < TREE_SIZE, "Invalid index");
        uint256 upper = treePrefixSumAtRound(index, roundId);
        uint256 lower = treePrefixSumAtRound(index - 1, roundId);
        return upper - lower;
    }

    function getFenwickNodeValueAtRound(uint256 index, uint256 roundId) external view returns (uint256) {
        require(roundId == activeSnapshotRoundId, "Round not active");
        require(index > 0 && index < TREE_SIZE, "Invalid index");
        return _nodeValueAtRound(fenwickNodes[index], roundId);
    }

    function _maybeForfeitRoundWeight(address account) internal {
        if (!diamondHandsEpochActive || account == address(0) || account == address(this)) return;

        uint256 roundId = forfeitureRoundId;
        uint256 index = eligibleIndexOf[account];
        if (index == 0) return;
        if (_holderByEligibleIndexAtRound(index, roundId) != account) return;

        uint256 startBalance = getPastBalance(account, activeSnapshotBlock);
        if (startBalance == 0 || balanceOf(account) >= startBalance) return;

        ILotteryEngine(lotteryEngine).forfeitRoundAccount(roundId, index, account);
    }

    function getActiveSnapshotTotalWeight(uint256 roundId) external view returns (uint256) {
        require(roundId == activeSnapshotRoundId, "Round not active");
        return activeSnapshotTotalWeight;
    }

    function _holderByEligibleIndexAtRound(uint256 index, uint256 roundId) internal view returns (address) {
        address holder;
        if (roundId == activeSnapshotRoundId && holderOpeningBlockByIndex[index] == activeSnapshotStartedAtBlock) {
            holder = holderOpeningAtIndex[index];
        } else {
            holder = holderAtIndex[index];
        }
        return holder;
    }

    function getHolderByEligibleIndexAtRound(uint256 index, uint256 roundId) external view returns (address) {
        return _holderByEligibleIndexAtRound(index, roundId);
    }

    function getHolderByEligibleIndex(uint256 index) external view returns (address) {
        return holderAtIndex[index];
    }

    function _isEip7702DelegatedEOA(address account) internal view returns (bool) {
        bytes memory c = account.code;
        return (c.length == 23 && c[0] == bytes1(0xef) && c[1] == bytes1(0x01) && c[2] == bytes1(0x00));
    }

    function isEip7702DelegatedEOA(address account) external view returns (bool) {
        return _isEip7702DelegatedEOA(account);
    }

    function _isLotteryIneligible(address account) internal view returns (bool) {
        if (
            account == address(0) || isEligibilityExempt[account] || isOfficialTaxExemptPoolOrManager[account]
                || isTaxedExternalPool[account]
        ) {
            return true;
        }

        if (account.code.length > 0) {
            if (_isEip7702DelegatedEOA(account)) {
                return false;
            }

            if (contractLotteryAllowed[account]) {
                return false;
            }

            return true;
        }

        return false;
    }

    function isLotteryIneligible(address account) public view returns (bool) {
        return _isLotteryIneligible(account);
    }

    uint256 public constant MAX_REFRESH_BATCH_SIZE = 50;

    function refreshEligibilityBatch(address[] calldata accounts) external {
        require(accounts.length <= MAX_REFRESH_BATCH_SIZE, "Too many accounts");
        for (uint256 i = 0; i < accounts.length; i++) {
            _refreshEligibility(accounts[i]);
        }
    }

    function refreshEligibility(address account) external {
        _refreshEligibility(account);
    }

    function _refreshEligibility(address account) internal {
        uint256 oldWeight = eligibleWeightOf[account];

        uint256 newWeight = 0;
        if (!_isLotteryIneligible(account)) {
            uint256 bal = balanceOf(account);
            if (bal >= minEligibleAmount) {
                newWeight = bal;
            }
        }

        if (oldWeight == newWeight) return;

        uint256 index = eligibleIndexOf[account];

        if (index == 0 && newWeight > 0) {
            index = _allocateEligibleIndex(account);

            if (index == 0) {
                // Transfer succeeds, but account remains unindexed/ineligible.
                return;
            }
        }

        if (index != 0 && newWeight > 0) {
            _cancelPendingFreeIfAny(account, index);
        }

        if (newWeight > oldWeight) {
            uint256 delta = newWeight - oldWeight;
            _captureTotalOpeningIfNeeded();
            _treeUpdate(index, int256(delta));
            totalEligibleBalance += delta;
            require(totalEligibleBalance <= type(uint192).max, "Total eligible overflow");
        } else {
            uint256 delta = oldWeight - newWeight;
            _captureTotalOpeningIfNeeded();
            _treeUpdate(index, -int256(delta));
            totalEligibleBalance -= delta;
        }

        eligibleWeightOf[account] = newWeight;

        if (oldWeight == 0 && newWeight > 0) {
            emit HolderBecameEligible(account, newWeight);
        }

        if (oldWeight > 0 && newWeight == 0) {
            emit HolderRemovedFromEligibility(account, oldWeight);
            _releaseEligibleIndexIfPossible(account, index);
        }
    }

    function _allocationSweepLimit() internal view returns (uint256) {
        if (nextEligibleIndex >= (TREE_SIZE * TREE_PRESSURE_BPS) / 10_000) {
            return HIGH_PRESSURE_ALLOC_SWEEP_LIMIT;
        }
        return NORMAL_ALLOC_SWEEP_LIMIT;
    }

    function _allocateEligibleIndex(address account) internal returns (uint256 index) {
        _sweepPendingFreeIndices(_allocationSweepLimit());

        if (freeEligibleIndices.length > 0) {
            index = freeEligibleIndices[freeEligibleIndices.length - 1];
            freeEligibleIndices.pop();

            _captureHolderOpeningIfNeeded(index);
            holderAtIndex[index] = account;
            eligibleIndexOf[account] = index;

            emit EligibleIndexReused(account, index);
            return index;
        }

        if (nextEligibleIndex >= TREE_SIZE) {
            emit EligibilityIndexExhausted(account, nextEligibleIndex);
            return 0;
        }

        index = nextEligibleIndex++;

        _captureHolderOpeningIfNeeded(index);
        holderAtIndex[index] = account;
        eligibleIndexOf[account] = index;

        emit EligibleIndexAllocated(account, index);
    }

    function _freeEligibleIndex(address account, uint256 index) internal {
        if (index == 0) return;
        if (eligibleWeightOf[account] != 0) return;
        if (eligibleIndexOf[account] != index) return;
        if (holderAtIndex[index] != account) return;

        eligibleIndexOf[account] = 0;
        _captureHolderOpeningIfNeeded(index);
        holderAtIndex[index] = address(0);
        pendingFreeRoundByIndex[index] = 0;

        freeEligibleIndices.push(index);

        emit EligibleIndexFreed(account, index);
    }

    function _releaseEligibleIndexIfPossible(address account, uint256 index) internal {
        if (index == 0) return;

        if (activeSnapshotRoundId != 0) {
            if (pendingFreeRoundByIndex[index] == 0) {
                pendingFreeRoundByIndex[index] = activeSnapshotRoundId;
                pendingFreeIndices.push(index);

                emit EligibleIndexQueuedForFree(account, index, activeSnapshotRoundId);
            }
            return;
        }

        _freeEligibleIndex(account, index);
    }

    function _cancelPendingFreeIfAny(address account, uint256 index) internal {
        if (index == 0) return;

        if (pendingFreeRoundByIndex[index] != 0) {
            pendingFreeRoundByIndex[index] = 0;
            emit EligibleIndexFreeCanceled(account, index);
        }
    }

    function sweepPendingFreeIndices(uint256 maxSteps) external {
        _sweepPendingFreeIndices(maxSteps);
    }

    function _sweepPendingFreeIndices(uint256 maxSteps) internal {
        if (activeSnapshotRoundId != 0) return;

        uint256 len = pendingFreeIndices.length;
        uint256 steps = 0;

        while (pendingFreeSweepCursor < len && steps < maxSteps) {
            uint256 index = pendingFreeIndices[pendingFreeSweepCursor++];
            steps++;

            uint64 pendingRound = pendingFreeRoundByIndex[index];
            if (pendingRound == 0) {
                continue;
            }

            address account = holderAtIndex[index];
            if (account != address(0) && eligibleIndexOf[account] == index && eligibleWeightOf[account] == 0) {
                _freeEligibleIndex(account, index);
            } else {
                pendingFreeRoundByIndex[index] = 0;
            }
        }

        if (pendingFreeSweepCursor == pendingFreeIndices.length) {
            delete pendingFreeIndices;
            pendingFreeSweepCursor = 0;
        }
    }

    function getFreeEligibleIndicesCount() external view returns (uint256) {
        return freeEligibleIndices.length;
    }

    function getPendingFreeIndicesCount() external view returns (uint256) {
        return pendingFreeIndices.length;
    }

    function getFreeEligibleIndexAt(uint256 pos) external view returns (uint256) {
        return freeEligibleIndices[pos];
    }

    function getPendingFreeIndexAt(uint256 pos) external view returns (uint256) {
        return pendingFreeIndices[pos];
    }

    // Dynamic external tax
    function getCurrentExternalTaxBps() public view returns (uint256) {
        if (tradingActivatedAt == 0) return 0;
        uint256 elapsed = block.timestamp - tradingActivatedAt;
        if (elapsed >= EXTERNAL_TAX_DECAY_DURATION) return MIN_EXTERNAL_TAX_BPS;
        return MAX_EXTERNAL_TAX_BPS
            - (((MAX_EXTERNAL_TAX_BPS - MIN_EXTERNAL_TAX_BPS) * elapsed) / EXTERNAL_TAX_DECAY_DURATION);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0) || amount == 0) {
            super._update(from, to, amount);
            _writeCheckpoint(from, balanceOf(from));
            _writeCheckpoint(to, balanceOf(to));
            return;
        }

        if (tradingActivatedAt == 0) {
            require(isTradingExempt[from] && isTradingExempt[to], "Trading not active");
        }

        bool officialPath = isOfficialTaxExemptPoolOrManager[from] || isOfficialTaxExemptPoolOrManager[to];
        bool externalPoolTrade = isTaxedExternalPool[from] || isTaxedExternalPool[to];

        uint256 sendAmount = amount;

        // Computed once, independent of whether THIS transfer happened to generate tax —
        // any qualifying sell can clear an existing backlog, not just the one that added to it.
        bool shouldMaybeAutoSwap = !inSwap && !officialPath && externalPoolTrade && isTaxedExternalPool[to];

        if (!inSwap && !officialPath && externalPoolTrade) {
            uint256 taxBps = getCurrentExternalTaxBps();
            if (taxBps > 0) {
                uint256 taxAmount = (amount * taxBps) / 10_000;
                sendAmount = amount - taxAmount;
                super._update(from, address(this), taxAmount);
                _writeCheckpoint(address(this), balanceOf(address(this)));
            }
        }

        bool isPoolOrManager = isTaxedExternalPool[to] || isOfficialTaxExemptPoolOrManager[to];
        if (!isMaxWalletExempt[to] && !isPoolOrManager) {
            require(balanceOf(to) + sendAmount <= getMaxWallet(), "Exceeds max wallet limit");
        }

        super._update(from, to, sendAmount);

        _writeCheckpoint(from, balanceOf(from));
        _writeCheckpoint(to, balanceOf(to));

        _maybeForfeitRoundWeight(from);

        _refreshEligibility(from);
        _refreshEligibility(to);
        if (!inSwap && !officialPath && externalPoolTrade) {
            _refreshEligibility(address(this));
        }

        if (shouldMaybeAutoSwap) {
            _maybeAutoSwap(from, to);
        }
    }

    function _computeAutoSwapMinOut(uint256 amountToSwap)
        internal
        view
        returns (bool ok, uint256 minEthOut, string memory reason)
    {
        if (address(officialPoolQuote) == address(0)) {
            return (false, 0, "Quote not set");
        }

        try officialPoolQuote.quoteReady{gas: QUOTE_GAS_LIMIT}() returns (bool ready) {
            if (!ready) {
                return (false, 0, "Quote not ready");
            }
        } catch {
            return (false, 0, "Quote ready failed");
        }

        uint256 expectedEthOut;
        try officialPoolQuote.quoteTokenToETH{gas: QUOTE_GAS_LIMIT}(amountToSwap) returns (uint256 out) {
            expectedEthOut = out;
        } catch {
            return (false, 0, "Quote failed");
        }

        if (expectedEthOut == 0) {
            return (false, 0, "Zero quote");
        }

        if (minAutoSwapExpectedEthOut != 0 && expectedEthOut < minAutoSwapExpectedEthOut) {
            return (false, 0, "Quote below floor");
        }

        // Avoid a multiplication overflow from a malformed quote. This is the
        // same floor as quote * (10_000 - bps) / 10_000, rounded down.
        uint256 slippageAmount = (expectedEthOut / 10_000) * autoSwapSlippageBps
            + ((expectedEthOut % 10_000) * autoSwapSlippageBps) / 10_000;
        minEthOut = expectedEthOut - slippageAmount;

        if (minEthOut == 0) {
            return (false, 0, "Unsafe minOut");
        }

        return (true, minEthOut, "");
    }

    // Auto swap logic
    function _maybeAutoSwap(address from, address to) internal {
        if (!autoSwapEnabled) return;
        if (inSwap) return;
        if (taxSwapRouter == address(0)) return;
        if (lastAutoSwapAttemptAt != 0 && block.timestamp < lastAutoSwapAttemptAt + swapCooldown) return;
        if (!isTaxedExternalPool[to]) return; // sell-side only
        if (balanceOf(address(this)) < swapThreshold) return;

        uint256 amountToSwap = balanceOf(address(this));
        if (amountToSwap > maxSwapAmount) amountToSwap = maxSwapAmount;

        (bool ok, uint256 minEthOut, string memory reason) = _computeAutoSwapMinOut(amountToSwap);

        if (!ok) {
            emit AutoSwapSkipped(amountToSwap, reason);
            return;
        }

        lastAutoSwapAttemptAt = block.timestamp;
        try this.swapTaxTokensForETH(amountToSwap, minEthOut) {
            lastAutoSwapSuccessAt = block.timestamp;
            emit AutoSwapSucceeded(amountToSwap, minEthOut);

            _tryAutoLotteryStep(from);
        } catch (bytes memory err) {
            emit AutoSwapFailed(amountToSwap, minEthOut, err);
        }
    }

    function swapTaxTokensForETH(uint256 amount, uint256 minEthOut) external {
        require(msg.sender == address(this), "Not authorized");
        _swapTaxTokensForETH(amount, minEthOut);
    }

    function freezeSettingsForever() external onlyOwner {
        require(!settingsFrozenForever, "Already frozen");
        require(lotteryEngine != address(0) && !ILotteryEngine(lotteryEngine).isLotteryPending(), "Lottery pending");

        settingsFrozenForever = true;

        emit SettingsFrozenForever(msg.sender);
    }

    function renounceOwnership() public override onlyOwner {
        require(settingsFrozenForever, "Settings not frozen");
        super.renounceOwnership();
    }

    function setContractLotteryAllowed(address account, bool allowed) external onlyOwner settingsMutable {
        require(lotteryEngine != address(0) && !ILotteryEngine(lotteryEngine).isLotteryPending(), "Lottery pending");
        require(account.code.length > 0, "Not contract");

        require(!isTaxedExternalPool[account], "External pool");
        require(!isOfficialTaxExemptPoolOrManager[account], "Official pool/router");

        contractLotteryAllowed[account] = allowed;

        _refreshEligibility(account);

        emit ContractLotteryAllowedSet(account, allowed);
    }

    function manualSwapTaxTokens(uint256 amount, uint256 minEthOut) external onlyOwner settingsMutable nonReentrant {
        require(amount > 0, "Amount zero");
        require(minEthOut > 0, "minEthOut zero");
        uint256 toSwap = amount > maxSwapAmount ? maxSwapAmount : amount;
        require(balanceOf(address(this)) >= toSwap, "Not enough taxed tokens");
        _swapTaxTokensForETH(toSwap, minEthOut);
    }

    function sweepTaxTokens(uint256 callerMinEthOut) external nonReentrant returns (uint256 ethReceived) {
        require(lastAutoSwapAttemptAt == 0 || block.timestamp >= lastAutoSwapAttemptAt + swapCooldown, "Swap cooldown");
        uint256 amountToSwap = balanceOf(address(this));
        if (amountToSwap > maxSwapAmount) amountToSwap = maxSwapAmount;
        require(amountToSwap > 0, "No taxed tokens");
        (bool ok, uint256 computedMinOut, string memory reason) = _computeAutoSwapMinOut(amountToSwap);
        require(ok, reason);
        uint256 finalMinOut = computedMinOut > callerMinEthOut ? computedMinOut : callerMinEthOut;
        uint256 beforeBalance = lotteryEngine.balance;
        lastAutoSwapAttemptAt = block.timestamp;
        _swapTaxTokensForETH(amountToSwap, finalMinOut);
        ethReceived = lotteryEngine.balance - beforeBalance;
        lastAutoSwapSuccessAt = block.timestamp;
        emit AutoSwapSucceeded(amountToSwap, finalMinOut);
    }

    function _swapTaxTokensForETH(uint256 amount, uint256 minEthOut) internal {
        require(amount > 0, "Amount zero");
        require(minEthOut > 0, "minEthOut zero");
        require(amount <= maxSwapAmount, "Amount too high");
        require(balanceOf(address(this)) >= amount, "Not enough taxed tokens");
        require(taxSwapRouter != address(0), "Router not set");
        require(lotteryEngine != address(0), "Engine not set");

        inSwap = true;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = IRouter(taxSwapRouter).WETH();

        _approve(address(this), taxSwapRouter, amount);

        uint256 engineEthBefore = lotteryEngine.balance;

        IRouter(taxSwapRouter)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(amount, minEthOut, path, lotteryEngine, block.timestamp);

        uint256 ethReceived = lotteryEngine.balance - engineEthBefore;
        require(ethReceived >= minEthOut, "Router underpaid engine");

        inSwap = false;
    }

    function _tryAutoLotteryStep(address rewardTo) internal {
        if (lotteryEngine == address(0)) return;
        if (gasleft() < 900_000) {
            emit TokenLotteryAutoActionSkipped(0, "Insufficient gas");
            return;
        }

        try ILotteryEngine(lotteryEngine).processPendingWinnerPayouts(1) {}
            catch {
            // best effort only; never revert user transfer/swap
        }

        try ILotteryEngine(lotteryEngine).autoLotteryStep{gas: 750_000}(rewardTo, 3) returns (
            uint8 action, uint256 roundId
        ) {
            if (action == 0) {
                emit TokenLotteryAutoActionSkipped(action, "No action");
            } else {
                emit TokenLotteryAutoActionSucceeded(roundId, action, rewardTo);
            }
        } catch (bytes memory reason) {
            emit TokenLotteryAutoActionFailed(reason);
        }
    }

    // Checkpoints
    function getPastBalance(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "Balance checkpoint: block not yet mined");
        Checkpoint[] storage ckpts = checkpoints[account];
        uint256 high = ckpts.length;
        uint256 low = 0;
        while (low < high) {
            uint256 mid = low + (high - low) / 2;
            if (ckpts[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high == 0 ? 0 : ckpts[high - 1].balance;
    }

    function _writeCheckpoint(address account, uint256 newBalance) internal {
        Checkpoint[] storage ckpts = checkpoints[account];
        uint256 length = ckpts.length;
        if (length > 0 && ckpts[length - 1].fromBlock == block.number) {
            ckpts[length - 1].balance = uint192(newBalance);
        } else {
            ckpts.push(Checkpoint({fromBlock: uint64(block.number), balance: uint192(newBalance)}));
        }
    }
}
