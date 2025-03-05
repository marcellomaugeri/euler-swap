// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IEulerSwapPeriphery {
    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut`, with at least `amountOutMin` received.
    function swapExactIn(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external;

    /// @notice Swap `amountOut` of `tokenOut` for `tokenIn`, with at most `amountInMax` paid.
    function swapExactOut(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax)
        external;

    /// @notice How much `tokenOut` can I get for `amountIn` of `tokenIn`?
    function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256);

    /// @notice How much `tokenIn` do I need to get `amountOut` of `tokenOut`?
    function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256);

    /// @notice Max amount the pool can buy of tokenIn and sell of tokenOut
    function getLimits(address eulerSwap, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 inLimit, uint256 outLimit);

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
        returns (uint256);
}
