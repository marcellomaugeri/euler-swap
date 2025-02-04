// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevBase {
    function configure() external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function quoteExactOutput(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256);

    function vault0() external view returns (address);
    function vault1() external view returns (address);
    function asset0() external view returns (address);
    function asset1() external view returns (address);
    function myAccount() external view returns (address);
    function feeMultiplier() external view returns (uint256);
    function getReserves() external view returns (uint112, uint112, uint32);
}
