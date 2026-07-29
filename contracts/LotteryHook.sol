// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "./BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface ILotteryEngine {
    function autoLotteryStep(address rewardTo, uint256 maxPayAttempts) external returns (uint8 action, uint256 roundId);
    function processPendingWinnerPayouts(uint256 maxCount) external;
}

interface IRobinhoodToken {
    function tradingActivatedAt() external view returns (uint256);
    function settingsFrozenForever() external view returns (bool);
}

contract LotteryHook is BaseHook, Ownable2Step {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    uint256 public constant MAX_TAX_BPS = 1000;
    uint256 public constant MIN_TAX_BPS = 100;
    uint256 public constant TAX_DECAY_DURATION = 30 minutes;

    address public lotteryEngine;
    IRobinhoodToken public token;
    Currency public ethCurrency;

    PoolId public officialPoolId;

    uint256 public constant MIN_GAS_FOR_LOTTERY_STEP = 900_000;
    uint256 public constant LOTTERY_STEP_GAS = 750_000;
    uint256 public constant AUTO_PAY_ATTEMPTS = 3;
    bool public autoLotteryEnabled = true;

    event HookLotteryAutoActionSucceeded(uint256 indexed roundId, uint8 action, address indexed rewardTo);
    event HookLotteryAutoActionSkipped(uint8 action, string reason);
    event HookLotteryAutoActionFailed(bytes reason);

    modifier settingsMutable() {
        require(!token.settingsFrozenForever(), "Settings frozen forever");
        _;
    }

    constructor(
        IPoolManager _poolManager,
        address _lotteryEngine,
        address _token,
        Currency _ethCurrency,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        require(_lotteryEngine != address(0), "Invalid engine");
        require(_token != address(0), "Invalid token");
        require(Currency.unwrap(_ethCurrency) == address(0), "Expected native ETH");

        lotteryEngine = _lotteryEngine;
        token = IRobinhoodToken(_token);
        ethCurrency = _ethCurrency;
    }

    receive() external payable {}

    function setOfficialPool(PoolKey calldata key) external onlyOwner settingsMutable {
        require(PoolId.unwrap(officialPoolId) == bytes32(0), "Pool already set");

        address tokenAddr = address(token);

        bool hasETH = Currency.unwrap(key.currency0) == Currency.unwrap(ethCurrency)
            || Currency.unwrap(key.currency1) == Currency.unwrap(ethCurrency);

        bool hasToken = Currency.unwrap(key.currency0) == tokenAddr || Currency.unwrap(key.currency1) == tokenAddr;

        require(hasETH && hasToken, "Wrong pool");

        officialPoolId = key.toId();
    }

    function setAutoLotteryConfig(bool enabled) external onlyOwner settingsMutable {
        autoLotteryEnabled = enabled;
    }

    function renounceOwnership() public override onlyOwner {
        require(token.settingsFrozenForever(), "Settings not frozen");
        require(PoolId.unwrap(officialPoolId) != bytes32(0), "Official pool not set");
        super.renounceOwnership();
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function getCurrentTaxBps() public view returns (uint256) {
        uint256 activatedAt = token.tradingActivatedAt();
        require(activatedAt > 0, "Hook trading not active");
        uint256 elapsed = block.timestamp - activatedAt;
        if (elapsed >= TAX_DECAY_DURATION) return MIN_TAX_BPS;
        return MAX_TAX_BPS - (((MAX_TAX_BPS - MIN_TAX_BPS) * elapsed) / TAX_DECAY_DURATION);
    }

    function _decodeRewardTo(address sender, bytes calldata hookData) internal pure returns (address rewardTo) {
        if (hookData.length >= 32) {
            rewardTo = abi.decode(hookData, (address));
        }
        if (rewardTo == address(0)) rewardTo = sender;
    }

    function _tryAutoLotteryStep(address rewardTo) internal {
        if (!autoLotteryEnabled) return;
        if (lotteryEngine == address(0)) return;

        if (gasleft() < MIN_GAS_FOR_LOTTERY_STEP) {
            emit HookLotteryAutoActionSkipped(0, "Insufficient gas");
            return;
        }

        try ILotteryEngine(lotteryEngine).processPendingWinnerPayouts(1) {} catch {}

        try ILotteryEngine(lotteryEngine).autoLotteryStep{gas: LOTTERY_STEP_GAS}(rewardTo, AUTO_PAY_ATTEMPTS) returns (
            uint8 action, uint256 roundId
        ) {
            if (action == 0) {
                emit HookLotteryAutoActionSkipped(action, "No action");
            } else {
                emit HookLotteryAutoActionSucceeded(roundId, action, rewardTo);
            }
        } catch (bytes memory reason) {
            emit HookLotteryAutoActionFailed(reason);
        }
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(officialPoolId)) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        uint256 taxBps = getCurrentTaxBps();
        if (taxBps == 0) return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        bool isExactIn = params.amountSpecified < 0;
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        Currency specifiedCurrency = isExactIn ? inputCurrency : outputCurrency;

        if (Currency.unwrap(specifiedCurrency) == Currency.unwrap(ethCurrency)) {
            uint256 specifiedAmount = isExactIn ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            uint256 taxAmount = (specifiedAmount * taxBps) / 10000;

            if (taxAmount > 0) {
                poolManager.take(ethCurrency, address(this), taxAmount);
                (bool success,) = lotteryEngine.call{value: taxAmount}("");
                require(success, "ETH transfer failed");

                _tryAutoLotteryStep(_decodeRewardTo(sender, hookData));

                BeforeSwapDelta returnDelta = toBeforeSwapDelta(
                    int128(uint128(taxAmount)), // specified delta
                    0 // unspecified delta
                );

                return (BaseHook.beforeSwap.selector, returnDelta, 0);
            }
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(officialPoolId)) {
            return (BaseHook.afterSwap.selector, 0);
        }

        uint256 taxBps = getCurrentTaxBps();
        if (taxBps == 0) return (BaseHook.afterSwap.selector, 0);

        bool isExactIn = params.amountSpecified < 0;
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = params.zeroForOne ? key.currency1 : key.currency0;
        Currency feeCurrency = isExactIn ? outputCurrency : inputCurrency;

        // We only use afterSwap for when ETH is the UNSPECIFIED currency.
        if (Currency.unwrap(feeCurrency) == Currency.unwrap(ethCurrency)) {
            int256 ethDelta =
                Currency.unwrap(key.currency0) == Currency.unwrap(ethCurrency) ? delta.amount0() : delta.amount1();

            int128 hookReturnDelta = 0;

            if (ethDelta > 0) {
                uint256 taxAmount = (uint256(ethDelta) * taxBps) / 10000;
                if (taxAmount > 0) {
                    poolManager.take(ethCurrency, address(this), taxAmount);
                    (bool success,) = lotteryEngine.call{value: taxAmount}("");
                    require(success, "ETH transfer failed");
                    hookReturnDelta = int128(uint128(taxAmount));

                    _tryAutoLotteryStep(_decodeRewardTo(sender, hookData));
                }
            } else if (ethDelta < 0) {
                uint256 ethOut = uint256(-ethDelta);
                uint256 taxAmount = (ethOut * taxBps) / 10000;
                if (taxAmount > 0) {
                    poolManager.take(ethCurrency, address(this), taxAmount);
                    (bool success,) = lotteryEngine.call{value: taxAmount}("");
                    require(success, "ETH transfer failed");
                    hookReturnDelta = int128(uint128(taxAmount));

                    _tryAutoLotteryStep(_decodeRewardTo(sender, hookData));
                }
            }

            return (BaseHook.afterSwap.selector, hookReturnDelta);
        }

        return (BaseHook.afterSwap.selector, 0);
    }
}
