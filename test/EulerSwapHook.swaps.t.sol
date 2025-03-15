// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {EulerSwapHook} from "../src/EulerSwapHook.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager, PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract EulerSwapHookTest is EulerSwapTestBase {
    using StateLibrary for IPoolManager;

    EulerSwapHook public eulerSwap;

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

        // confirm pool was created
        assertFalse(eulerSwap.poolKey().currency1 == CurrencyLibrary.ADDRESS_ZERO);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(eulerSwap.poolKey().toId());
        assertNotEq(sqrtPriceX96, 0);

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), true);
    }

    function test_SwapExactIn() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(swapRouter), amountIn);

        bool zeroForOne = address(assetTST) < address(assetTST2);
        _swap(eulerSwap.poolKey(), zeroForOne, true, amountIn);
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapExactOut() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        bool zeroForOne = address(assetTST) < address(assetTST2);
        _swap(eulerSwap.poolKey(), zeroForOne, false, amountOut);
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function _swap(PoolKey memory key, bool zeroForOne, bool exactInput, uint256 amount) internal {
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: exactInput ? -int256(amount) : int256(amount),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        swapRouter.swap(key, swapParams, settings, "");
    }
}
