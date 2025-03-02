// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery} from "./EulerSwapTestBase.t.sol";

contract EulerSwapPeripheryTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_SwapExactIn() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactIn(address(eulerSwap), address(assetTST), address(assetTST2), amountIn, amountOut);
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapExactIn_AmountOutLessThanMin() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        vm.expectRevert(EulerSwapPeriphery.AmountOutLessThanMin.selector);
        periphery.swapExactIn(address(eulerSwap), address(assetTST), address(assetTST2), amountIn, amountOut + 1);
        vm.stopPrank();
    }

    function test_SwapExactOut() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactOut(address(eulerSwap), address(assetTST), address(assetTST2), amountOut, amountIn);
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapExactOut_AmountInMoreThanMax() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        vm.expectRevert(EulerSwapPeriphery.AmountInMoreThanMax.selector);
        periphery.swapExactOut(address(eulerSwap), address(assetTST), address(assetTST2), amountOut * 2, amountIn);
        vm.stopPrank();
    }
}
