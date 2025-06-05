// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

/// @notice Emitted upon EulerSwap instance creation.
///   * `asset0` and `asset1` are the underlying assets of the vaults.
///     They are always in lexical order: `asset0 < asset1`.
event EulerSwapActivated(address indexed asset0, address indexed asset1);

/// @notice Emitted after every swap.
///   * `amount0In` and `amount1In` are after fees have been subtracted.
///   * When executed via Uniswap4 hook, `sender` and `to` are the PoolManager.
///   * `reserve0` and `reserve1` are the pool's new reserves (after the swap).
event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    uint112 reserve0,
    uint112 reserve1,
    address indexed to
);
