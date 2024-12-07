// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {MaglevEulerSwap as Maglev} from "../src/MaglevEulerSwap.sol";

contract EulerSwapTest is MaglevTestBase {
    Maglev public maglev;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(owner);
        maglev =
            new Maglev(_getMaglevBaseParams(), Maglev.EulerSwapParams({px: 1e18, py: 1e18, cx: 0.4e18, cy: 0.85e18}));

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(owner);
        maglev.configure();

        vm.prank(owner);
        maglev.setDebtLimit(50e18, 50e18);
    }

    function test_basicSwap() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = maglev.quoteExactInput(address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_pathIndependent(uint256 amount, bool dir) public {
        amount = bound(amount, 0.1e18, 25e18);

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);

        uint256 q = maglev.quoteExactInput(address(t1), address(t2), amount);

        t1.transfer(address(maglev), amount);
        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.transfer(address(maglev), q);
        if (dir) maglev.swap(amount - 2, 0, address(this), ""); // - 2 due to rounding

        else maglev.swap(0, amount - 2, address(this), "");

        uint256 q2 = maglev.quoteExactInput(address(t1), address(t2), amount);
        assertApproxEqAbs(q, q2, 0.00000001e18);
    }
}
