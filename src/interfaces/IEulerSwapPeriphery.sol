// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IEulerSwapPeriphery {
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
}
