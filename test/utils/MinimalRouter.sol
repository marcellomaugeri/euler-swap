// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract MinimalRouter is SafeCallback {
    using CurrencySettler for Currency;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    constructor(IPoolManager _manager) SafeCallback(_manager) {}

    function swap(PoolKey memory key, bool zeroForOne, bool exactInput, uint256 amount, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            poolManager.unlock(abi.encode(msg.sender, key, zeroForOne, exactInput, amount, hookData)), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (address sender, PoolKey memory key, bool zeroForOne, bool exactInput, uint256 amount, bytes memory hookData) =
            abi.decode(data, (address, PoolKey, bool, bool, uint256, bytes));

        // for exact input swaps, send the input first to avoid PoolManager token balance issues
        if (exactInput) {
            zeroForOne
                ? key.currency0.settle(poolManager, sender, amount, false)
                : key.currency1.settle(poolManager, sender, amount, false);
        }

        BalanceDelta delta = poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: exactInput ? -int256(amount) : int256(amount),
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            hookData
        );

        if (!exactInput && delta.amount0() < 0) {
            key.currency0.settle(poolManager, sender, uint256(int256(-delta.amount0())), false);
        } else if (delta.amount0() > 0) {
            key.currency0.take(poolManager, sender, uint256(int256(delta.amount0())), false);
        }

        if (!exactInput && delta.amount1() < 0) {
            key.currency1.settle(poolManager, sender, uint256(int256(-delta.amount1())), false);
        } else if (delta.amount1() > 0) {
            key.currency1.take(poolManager, sender, uint256(int256(delta.amount1())), false);
        }

        return abi.encode(delta);
    }
}
