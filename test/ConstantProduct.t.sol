// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {MaglevConstantProduct as Maglev} from "../src/MaglevConstantProduct.sol";

contract ConstantProductTest is MaglevTestBase {
    Maglev public maglev;

    function setUp() public virtual override {
        super.setUp();

        createMaglev(50e18, 50e18, 0);
    }

    function createMaglev(uint112 debtLimit0, uint112 debtLimit1, uint256 fee) internal {
        vm.prank(owner);
        maglev = new Maglev(getMaglevBaseParams(debtLimit0, debtLimit1, fee));

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(owner);
        maglev.configure();
    }

    function test_basicExactIn() public monotonicHolderNAV {
        uint256 amount = 1e18;

        assetTST.mint(address(this), amount);

        uint256 q = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount);

        assetTST.transfer(address(maglev), amount);

        vm.expectRevert(Maglev.KNotSatisfied.selector);
        maglev.swap(0, q+1, address(this), "");

        maglev.swap(0, q, address(this), "");
        assertEq(assetTST2.balanceOf(address(this)), q);
    }

    function test_fee_exactIn(uint256 amount, bool dir) public monotonicHolderNAV {
        amount = bound(amount, 0.1e18, 25e18);

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);

        uint256 qOrig = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount * 0.998e18 / 1e18);

        createMaglev(50e18, 50e18, 0.002e18);

        uint256 q = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount);

        assertEq(qOrig, q);

        t1.transfer(address(maglev), amount);

        vm.expectRevert(Maglev.KNotSatisfied.selector);
        if (dir) maglev.swap(0, q+1, address(this), "");
        else maglev.swap(q+1, 0, address(this), "");

        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);
    }

    function test_pathIndependent(uint256 amount, bool dir) public monotonicHolderNAV {
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
        assertApproxEqAbs(q, q2, 2);
    }
}
