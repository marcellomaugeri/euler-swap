// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapHook} from "../src/EulerSwapHook.sol";

import {IPoolManager, PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

contract EulerSwapHookTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;

    PoolSwapTest.TestSettings public settings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

    function setUp() public virtual override {
        super.setUp();

        // TODO: move upstream to EulerSwapTestBase?
        poolManager = PoolManagerDeployer.deploy(address(this));
        swapRouter = new PoolSwapTest(poolManager);

        // eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
        IEulerSwap.Params memory poolParams = getEulerSwapParams(60e18, 60e18, 0);
        IEulerSwap.CurveParams memory curveParams =
            IEulerSwap.CurveParams({priceX: 1e18, priceY: 1e18, concentrationX: 0.4e18, concentrationY: 0.85e18});
        bytes memory constructorArgs = abi.encode(poolManager, poolParams, curveParams);
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(creator, flags, type(EulerSwapHook).creationCode, constructorArgs);
        vm.prank(creator);
        eulerSwap = new EulerSwapHook{salt: salt}(poolManager, poolParams, curveParams);
        assertEq(address(eulerSwap), hookAddress);

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), true);
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
