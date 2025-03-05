// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";
import {IERC20, IEulerSwap, SafeERC20} from "./EulerSwap.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapPeriphery is IEulerSwapPeriphery {
    using SafeERC20 for IERC20;

    error UnsupportedPair();
    error OperatorNotInstalled();
    error SwapLimitExceeded();
    error AmountOutLessThanMin();
    error AmountInMoreThanMax();

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactIn(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external
    {
        uint256 amountOut = computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true);

        require(amountOut >= amountOutMin, AmountOutLessThanMin());

        swap(eulerSwap, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactOut(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax)
        external
    {
        uint256 amountIn = computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountOut, false);

        require(amountIn <= amountInMax, AmountInMoreThanMax());

        swap(eulerSwap, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256)
    {
        return computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256)
    {
        return computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountOut, false);
    }

    /// @dev Internal function to execute a token swap through EulerSwap
    /// @param eulerSwap The EulerSwap contract address to execute the swap through
    /// @param tokenIn The address of the input token being swapped
    /// @param tokenOut The address of the output token being received
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOut The amount of output tokens to receive
    function swap(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) internal {
        IERC20(tokenIn).safeTransferFrom(msg.sender, eulerSwap, amountIn);

        bool isAsset0In = tokenIn < tokenOut;
        (isAsset0In)
            ? IEulerSwap(eulerSwap).swap(0, amountOut, msg.sender, "")
            : IEulerSwap(eulerSwap).swap(amountOut, 0, msg.sender, "");
    }

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
        (uint256 inLimit, uint256 outLimit) = _getLimits(eulerSwap, asset0IsInput);

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

            uint256 low;
            uint256 high = type(uint112).max;

            while (low < high) {
                uint256 mid = (low + high) / 2;
                (uint256 a, uint256 b) = dy == 0 ? (uint256(reserve0New), mid) : (mid, uint256(reserve1New));
                require(a > 0 && b > 0, SwapLimitExceeded());
                if (eulerSwap.verify(a, b)) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }

            if (dx != 0) dy = int256(low) - reserve1New;
            else dx = int256(low) - reserve0New;
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
        } else {
            if (asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
        }
    }

    /**
     * @notice Computes the inverse of the `f()` function for the EulerSwap liquidity curve.
     * @dev Solves for `x` given `y` using the quadratic formula derived from the liquidity curve:
     *      x = (-b + sqrt(b^2 + 4ac)) / 2a
     *      Utilises mulDiv to avoid overflow and ensures precision with upward rounding.
     *
     * @param y The y-coordinate input value (must be greater than `y0`).
     * @param px Price factor for the x-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param py Price factor for the y-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param x0 Reference x-value on the liquidity curve (≤ 2^112 - 1).
     * @param y0 Reference y-value on the liquidity curve (≤ 2^112 - 1).
     * @param c Curve parameter shaping liquidity concentration (scaled by 1e18, between 0 and 1e18).
     *
     * @return x The computed x-coordinate on the liquidity curve.
     *
     * @custom:precision Uses rounding up to maintain precision in all calculations.
     * @custom:safety FullMath handles potential overflow in the b^2 computation.
     * @custom:requirement Input `y` must be strictly greater than `y0`; otherwise, the function will revert.
     */
    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        external
        pure
        returns (uint256)
    {
        // A component of the quadratic formula: a = 2 * c
        uint256 A = 2 * c;

        // B component of the quadratic formula
        int256 B = int256((px * (y - y0) + py - 1) / py) - int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18);

        // B^2 component, using FullMath for overflow safety
        uint256 absB = B < 0 ? uint256(-B) : uint256(B);
        uint256 squaredB = Math.mulDiv(absB, absB, 1e18, Math.Rounding.Ceil);

        // 4 * A * C component of the quadratic formula
        uint256 AC4 = Math.mulDiv(
            Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil),
            Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil),
            1e18,
            Math.Rounding.Ceil
        );

        // Discriminant: b^2 + 4ac, scaled up to maintain precision
        uint256 discriminant = (squaredB + AC4) * 1e18;

        // Square root of the discriminant (rounded up)
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

        // Compute and return x = fInverse(y) using the quadratic formula
        return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, A, Math.Rounding.Ceil);
    }

    /// @notice Max amount the pool can buy of tokenIn and sell of tokenOut
    function getLimits(address eulerSwap, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 inLimit, uint256 outLimit)
    {
        if (
            !IEVC(IEulerSwap(eulerSwap).EVC()).isAccountOperatorAuthorized(
                IEulerSwap(eulerSwap).eulerAccount(), eulerSwap
            )
        ) return (0, 0);

        return _getLimits(IEulerSwap(eulerSwap), checkTokens(IEulerSwap(eulerSwap), tokenIn, tokenOut));
    }

    function _getLimits(IEulerSwap es, bool asset0IsInput) internal view returns (uint256 inLimit, uint256 outLimit) {
        inLimit = outLimit = type(uint112).max;
        address eulerAccount = es.eulerAccount();
        (IEVault vault0, IEVault vault1) = (IEVault(es.vault0()), IEVault(es.vault1()));
        // Supply caps on input
        {
            IEVault vault = IEVault(asset0IsInput ? vault0 : vault1);
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
            IEVault vault = IEVault(asset0IsInput ? vault1 : vault0);

            uint256 cash = vault.cash();
            if (cash < outLimit) outLimit = cash;

            (, uint16 borrowCap) = vault.caps();
            uint256 maxWithdraw = decodeCap(uint256(borrowCap));
            maxWithdraw = vault.totalBorrows() > maxWithdraw ? 0 : maxWithdraw - vault.totalBorrows();
            if (maxWithdraw > cash) maxWithdraw = cash;
            maxWithdraw += vault.convertToAssets(vault.balanceOf(eulerAccount));
            if (maxWithdraw < outLimit) outLimit = maxWithdraw;
        }
    }

    function decodeCap(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

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
