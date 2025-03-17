// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {
    BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {EulerSwap, IEulerSwap, IEVault} from "./EulerSwap.sol";

contract EulerSwapHook is EulerSwap, BaseHook {
    using SafeCast for uint256;

    PoolKey internal _poolKey;

    constructor(IPoolManager _manager, Params memory params, CurveParams memory curveParams)
        EulerSwap(params, curveParams)
        BaseHook(_manager)
    {
        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();

        // convert fee in WAD to pips. 0.003e18 / 1e12 = 3000 = 0.30%
        uint24 fee = uint24(params.fee / 1e12);

        _poolKey = PoolKey({
            currency0: Currency.wrap(asset0Addr),
            currency1: Currency.wrap(asset1Addr),
            fee: fee,
            tickSpacing: 60, // TODO: fix arbitrary tick spacing
            hooks: IHooks(address(this))
        });

        // create the pool on v4, using starting price as sqrtPrice(1/1) * Q96
        poolManager.initialize(_poolKey, 79228162514264337593543950336);
    }

    /// @dev Helper function to return the poolKey as its struct type
    function poolKey() external view returns (PoolKey memory) {
        return _poolKey;
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // determine inbound/outbound token based on 0->1 or 1->0 swap
        (Currency inputCurrency, Currency outputCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        bool isExactInput = params.amountSpecified < 0;

        // TODO: compute the open side of the trade, using computeQuote() ?
        uint256 amountIn;
        uint256 amountOut;
        // uint256 amountIn = isExactInput ? uint256(-params.amountSpecified) : computeQuote(..., false);
        // uint256 amountOut = isExactInput ? computeQuote(..., true) : uint256(params.amountSpecified);

        // take the input token, from the PoolManager to the Euler vault
        // the debt will be paid by the swapper via the swap router
        // TODO: can we optimize the transfer by pulling from PoolManager directly to Euler?
        poolManager.take(inputCurrency, address(this), amountIn);
        depositAssets(inputCurrency == key.currency0 ? vault0 : vault1, amountIn);

        // pay the output token, to the PoolManager from an Euler vault
        // the credit will be forwarded to the swap router, which then forwards it to the swapper
        poolManager.sync(outputCurrency);
        withdrawAssets(outputCurrency == key.currency0 ? vault0 : vault1, amountOut, address(poolManager));
        poolManager.settle();

        {
            uint256 newReserve0 = inputCurrency == key.currency0 ? (reserve0 + amountIn) : (reserve0 - amountOut);
            uint256 newReserve1 = inputCurrency == key.currency1 ? (reserve1 + amountIn) : (reserve1 - amountOut);

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
            require(verify(newReserve0, newReserve1), CurveViolation());

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }

        // return the delta to the PoolManager, so it can process the accounting
        // exact input:
        //   specifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        //   unspecifiedDelta = negative, to offset the credit of the output token paid by the hook (positive delta)
        // exact output:
        //   specifiedDelta = negative, to offset the output token paid by the hook (positive delta)
        //   unspecifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        BeforeSwapDelta returnDelta = isExactInput
            ? toBeforeSwapDelta(amountIn.toInt128(), -(amountOut.toInt128()))
            : toBeforeSwapDelta(-(amountOut.toInt128()), amountIn.toInt128());
        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    // TODO: fix salt mining & verification for the hook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {}
    function validateHookAddress(BaseHook) internal pure override {}
}
