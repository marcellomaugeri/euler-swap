// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

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

event EulerSwapActivated(address indexed asset0, address indexed asset1);
