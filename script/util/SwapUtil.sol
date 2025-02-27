// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IEulerSwapPeriphery} from "../../src/interfaces/IEulerSwapPeriphery.sol";
import {IERC20, IEulerSwap, SafeERC20} from "../../src/EulerSwap.sol";

// This is not meant to be run in production, just for testing purposes
contract SwapUtil {
    using SafeERC20 for IERC20;
    
    IEulerSwapPeriphery public immutable periphery;

    constructor(address peripheryAddr) {
        periphery = IEulerSwapPeriphery(peripheryAddr);
    }

    function executeSwap(address pool, address tokenIn, address tokenOut, uint256 amount, bool isExactIn) external {
        bool isAsset0In = tokenIn < tokenOut;

        (uint256 amountIn, uint256 amountOut) = (isExactIn)
            ? (amount, periphery.quoteExactInput(address(pool), tokenIn, tokenOut, amount))
            : (periphery.quoteExactOutput(address(pool), tokenIn, tokenOut, amount), amount);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(pool), amountIn);

        (isAsset0In)
            ? IEulerSwap(pool).swap(0, amountOut, msg.sender, "")
            : IEulerSwap(pool).swap(amountOut, 0, msg.sender, "");
    }
}
