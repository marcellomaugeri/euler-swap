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

import {IEVault} from "evk/EVault/IEVault.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {CtxLib} from "./CtxLib.sol";
import {QuoteLib} from "./QuoteLib.sol";
import {CurveLib} from "./CurveLib.sol";
import {FundsLib} from "./FundsLib.sol";

contract UniswapHook is BaseHook {
    using SafeCast for uint256;

    address private immutable evc;

    PoolKey internal _poolKey;

    constructor(address evc_, address _poolManager) BaseHook(IPoolManager(_poolManager)) {
        evc = evc_;
    }

    function activateHook(IEulerSwap.Params memory p) internal {
        address asset0Addr = IEVault(p.vault0).asset();
        address asset1Addr = IEVault(p.vault1).asset();

        // convert fee in WAD to pips. 0.003e18 / 1e12 = 3000 = 0.30%
        uint24 fee = uint24(p.fee / 1e12);

        _poolKey = PoolKey({
            currency0: Currency.wrap(asset0Addr),
            currency1: Currency.wrap(asset1Addr),
            fee: fee,
            tickSpacing: 1, // hard-coded tick spacing, as its unused
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
        IEulerSwap.Params memory p = CtxLib.getParams();

        uint256 amountInWithoutFee;
        uint256 amountOut;
        BeforeSwapDelta returnDelta;

        {
            uint256 amountIn;
            bool isExactInput = params.amountSpecified < 0;
            if (isExactInput) {
                amountIn = uint256(-params.amountSpecified);
                amountOut = QuoteLib.computeQuote(evc, p, params.zeroForOne, uint256(-params.amountSpecified), true);
            } else {
                amountIn = QuoteLib.computeQuote(evc, p, params.zeroForOne, uint256(params.amountSpecified), false);
                amountOut = uint256(params.amountSpecified);
            }

            // return the delta to the PoolManager, so it can process the accounting
            // exact input:
            //   specifiedDelta = positive, to offset the input token taken by the hook (negative delta)
            //   unspecifiedDelta = negative, to offset the credit of the output token paid by the hook (positive delta)
            // exact output:
            //   specifiedDelta = negative, to offset the output token paid by the hook (positive delta)
            //   unspecifiedDelta = positive, to offset the input token taken by the hook (negative delta)
            returnDelta = isExactInput
                ? toBeforeSwapDelta(amountIn.toInt128(), -(amountOut.toInt128()))
                : toBeforeSwapDelta(-(amountOut.toInt128()), amountIn.toInt128());

            // take the input token, from the PoolManager to the Euler vault
            // the debt will be paid by the swapper via the swap router
            poolManager.take(params.zeroForOne ? key.currency0 : key.currency1, address(this), amountIn);
            amountInWithoutFee = FundsLib.depositAssets(evc, p, params.zeroForOne ? p.vault0 : p.vault1);

            // pay the output token, to the PoolManager from an Euler vault
            // the credit will be forwarded to the swap router, which then forwards it to the swapper
            poolManager.sync(params.zeroForOne ? key.currency1 : key.currency0);
            FundsLib.withdrawAssets(evc, p, params.zeroForOne ? p.vault1 : p.vault0, amountOut, address(poolManager));
            poolManager.settle();
        }

        {
            CtxLib.Storage storage s = CtxLib.getStorage();

            uint256 newReserve0 = params.zeroForOne ? (s.reserve0 + amountInWithoutFee) : (s.reserve0 - amountOut);
            uint256 newReserve1 = !params.zeroForOne ? (s.reserve1 + amountInWithoutFee) : (s.reserve1 - amountOut);

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, CurveLib.Overflow());
            require(CurveLib.verify(p, newReserve0, newReserve1), CurveLib.CurveViolation());

            s.reserve0 = uint112(newReserve0);
            s.reserve1 = uint112(newReserve1);
        }

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
