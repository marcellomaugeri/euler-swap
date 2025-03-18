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









    /// @dev Computes the quote for a swap by applying fees and validating state conditions
    /// @param eulerSwap The EulerSwap contract to quote from
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuote(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        require(
            IEVC(eulerSwap.EVC()).isAccountOperatorAuthorized(eulerSwap.eulerAccount(), address(eulerSwap)),
            OperatorNotInstalled()
        );
        require(amount <= type(uint112).max, SwapLimitExceeded());

        uint256 feeMultiplier = eulerSwap.feeMultiplier();
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = amount * feeMultiplier / 1e18;

        bool asset0IsInput = checkTokens(eulerSwap, tokenIn, tokenOut);
        (uint256 inLimit, uint256 outLimit) = calcLimits(eulerSwap, asset0IsInput);

        uint256 quote = binarySearch(eulerSwap, reserve0, reserve1, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, SwapLimitExceeded());
        }

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn) quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    /// @notice Binary searches for the output amount along a swap curve given input parameters
    /// @dev General-purpose routine for binary searching swapping curves.
    /// Although some curves may have more efficient closed-form solutions,
    /// this works with any monotonic curve.
    /// @param eulerSwap The EulerSwap contract to search the curve for
    /// @param reserve0 Current reserve of asset0 in the pool
    /// @param reserve1 Current reserve of asset1 in the pool
    /// @param amount The input or output amount depending on exactIn
    /// @param exactIn True if amount is input amount, false if amount is output amount
    /// @param asset0IsInput True if asset0 is being input, false if asset1 is being input
    /// @return output The calculated output amount from the binary search
    function binarySearch(
        IEulerSwap eulerSwap,
        uint112 reserve0,
        uint112 reserve1,
        uint256 amount,
        bool exactIn,
        bool asset0IsInput
    ) internal view returns (uint256 output) {
        int256 dx;
        int256 dy;

        if (exactIn) {
            if (asset0IsInput) dx = int256(amount);
            else dy = int256(amount);
        } else {
            if (asset0IsInput) dy = -int256(amount);
            else dx = -int256(amount);
        }

        unchecked {
            int256 reserve0New = int256(uint256(reserve0)) + dx;
            int256 reserve1New = int256(uint256(reserve1)) + dy;
            require(reserve0New > 0 && reserve1New > 0, SwapLimitExceeded());

            uint256 low;
            uint256 high = type(uint112).max;

            while (low < high) {
                uint256 mid = (low + high) / 2;
                require(mid > 0, SwapLimitExceeded());
                (uint256 a, uint256 b) = dy == 0 ? (uint256(reserve0New), mid) : (mid, uint256(reserve1New));
                if (eulerSwap.verify(a, b)) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }

            require(high < type(uint112).max, SwapLimitExceeded()); // at least one point verified

            if (dx != 0) dy = int256(low) - reserve1New;
            else dx = int256(low) - reserve0New;
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
        } else {
            if (asset0IsInput) output = dx >= 0 ? uint256(dx) : 0;
            else output = dy >= 0 ? uint256(dy) : 0;
        }
    }

    /**
     * @notice Calculates the maximum input and output amounts for a swap based on protocol constraints
     * @dev Determines limits by checking multiple factors:
     *      1. Supply caps and existing debt for the input token
     *      2. Available reserves in the EulerSwap for the output token
     *      3. Available cash and borrow caps for the output token
     *      4. Account balances in the respective vaults
     *
     * @param es The EulerSwap contract to calculate limits for
     * @param asset0IsInput Boolean indicating whether asset0 (true) or asset1 (false) is the input token
     * @return uint256 Maximum amount of input token that can be deposited
     * @return uint256 Maximum amount of output token that can be withdrawn
     */
    function calcLimits(IEulerSwap es, bool asset0IsInput) internal view returns (uint256, uint256) {
        uint256 inLimit = type(uint112).max;
        uint256 outLimit = type(uint112).max;

        address eulerAccount = es.eulerAccount();
        (IEVault vault0, IEVault vault1) = (IEVault(es.vault0()), IEVault(es.vault1()));
        // Supply caps on input
        {
            IEVault vault = (asset0IsInput ? vault0 : vault1);
            uint256 maxDeposit = vault.debtOf(eulerAccount) + vault.maxDeposit(eulerAccount);
            if (maxDeposit < inLimit) inLimit = maxDeposit;
        }

        // Remaining reserves of output
        {
            (uint112 reserve0, uint112 reserve1,) = es.getReserves();
            uint112 reserveLimit = asset0IsInput ? reserve1 : reserve0;
            if (reserveLimit < outLimit) outLimit = reserveLimit;
        }

        // Remaining cash and borrow caps in output
        {
            IEVault vault = (asset0IsInput ? vault1 : vault0);

            uint256 cash = vault.cash();
            if (cash < outLimit) outLimit = cash;

            (, uint16 borrowCap) = vault.caps();
            uint256 maxWithdraw = decodeCap(uint256(borrowCap));
            maxWithdraw = vault.totalBorrows() > maxWithdraw ? 0 : maxWithdraw - vault.totalBorrows();
            if (maxWithdraw > cash) maxWithdraw = cash;
            maxWithdraw += vault.convertToAssets(vault.balanceOf(eulerAccount));
            if (maxWithdraw < outLimit) outLimit = maxWithdraw;
        }

        return (inLimit, outLimit);
    }

    /**
     * @notice Decodes a compact-format cap value to its actual numerical value
     * @dev The cap uses a compact-format where:
     *      - If amountCap == 0, there's no cap (returns max uint256)
     *      - Otherwise, the lower 6 bits represent the exponent (10^exp)
     *      - The upper bits (>> 6) represent the mantissa
     *      - The formula is: (10^exponent * mantissa) / 100
     * @param amountCap The compact-format cap value to decode
     * @return The actual numerical cap value (type(uint256).max if uncapped)
     * @custom:security Uses unchecked math for gas optimization as calculations cannot overflow:
     *                  maximum possible value 10^(2^6-1) * (2^10-1) ≈ 1.023e+66 < 2^256
     */
    function decodeCap(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

    /**
     * @notice Verifies that the given tokens are supported by the EulerSwap pool and determines swap direction
     * @dev Returns a boolean indicating whether the input token is asset0 (true) or asset1 (false)
     * @param eulerSwap The EulerSwap pool contract to check against
     * @param tokenIn The input token address for the swap
     * @param tokenOut The output token address for the swap
     * @return asset0IsInput True if tokenIn is asset0 and tokenOut is asset1, false if reversed
     * @custom:error UnsupportedPair Thrown if the token pair is not supported by the EulerSwap pool
     */
    function checkTokens(IEulerSwap eulerSwap, address tokenIn, address tokenOut)
        internal
        view
        returns (bool asset0IsInput)
    {
        address asset0 = eulerSwap.asset0();
        address asset1 = eulerSwap.asset1();

        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();
    }
}
