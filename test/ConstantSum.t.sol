// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {MaglevConstantSum as Maglev} from "../src/MaglevConstantSum.sol";

contract ConstantSumTest is MaglevTestBase {
    Maglev public maglev;

    function setUp() public override virtual {
        super.setUp();

        vm.prank(owner);
        maglev = new Maglev(
            _getMaglevBaseParams(),
            Maglev.ConstantSumParams({fee: 0, priceA: 1, priceB: 1})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(owner);
        maglev.configure();

        vm.prank(owner);
        maglev.setVirtualReserves(50e18, 50e18);
    }

    function test_basicSwapReport() public {
        uint256 amount = 25e18;
        assetTST.mint(address(this), amount);

        logState(address(maglev));

        assetTST.transfer(address(maglev), amount);
        maglev.swap(0, amount, address(this), "");
        assertEq(assetTST2.balanceOf(address(this)), amount);

        logState(address(maglev));

        uint256 amount2 = 50e18;
        assetTST2.mint(address(this), amount2);
        assetTST2.transfer(address(maglev), amount2);
        maglev.swap(amount2, 0, address(this), "");

        assetTST2.transfer(address(maglev), 1e18);
        maglev.swap(1e18, 0, address(this), "");

        logState(address(maglev));
    }

    function test_reserveLimit() public {
        assertEq(maglev.virtualReserve0(), 50e18);
        assertEq(maglev.virtualReserve1(), 50e18);
        assertEq(maglev.reserve0(), 60e18);
        assertEq(maglev.reserve1(), 60e18);

        assetTST.mint(address(this), 1000e18);

        uint256 snapshot = vm.snapshotState();

        {
            uint256 amount = 60.000001e18;
            assetTST.transfer(address(maglev), amount);
            vm.expectRevert(); // FIXME: which error?
            maglev.swap(0, amount, address(this), "");
        }

        vm.revertToState(snapshot);

        {
            uint256 amount = 60e18;
            assetTST.transfer(address(maglev), amount);
            maglev.swap(0, amount, address(this), "");
        }

        assertEq(eTST2.debtOf(holder), 50e18);
        assertEq(maglev.reserve0(), 120e18);
        assertEq(maglev.reserve1(), 0e18);

        vm.prank(owner);
        maglev.setVirtualReserves(60e18, 55e18);

        assertEq(maglev.reserve0(), 130e18);
        assertEq(maglev.reserve1(), 5e18);

        vm.prank(owner);
        maglev.setVirtualReserves(40e18, 45e18);

        assertEq(maglev.reserve0(), 110e18);
        assertEq(maglev.reserve1(), 0e18);
    }

    function test_basicSwapFuzz(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, 25e18);
        amount2 = bound(amount2, 1e18, 50e18);

        assetTST.mint(address(this), amount1);
        assetTST.transfer(address(maglev), amount1);
        maglev.swap(0, amount1, address(this), "");
        assertEq(assetTST.balanceOf(address(this)), 0);
        assertEq(assetTST2.balanceOf(address(this)), amount1);

        assetTST2.mint(address(this), amount2);
        assetTST2.transfer(address(maglev), amount2);
        maglev.swap(amount2, 0, address(this), "");
        assertEq(assetTST.balanceOf(address(this)), amount2);
        assertEq(assetTST2.balanceOf(address(this)), amount1);
    }

    function test_quoteExactInput() public {
        vm.prank(owner);
        maglev.setConstantSumParams(Maglev.ConstantSumParams({fee: 0.003e18, priceA: 1, priceB: 1}));

        assetTST.mint(address(this), 100e18);
        uint256 q = maglev.quoteExactInput(address(assetTST), address(assetTST2), 1e18);
        assertLt(q, 1e18);
        assetTST.transfer(address(maglev), 1e18);

        maglev.swap(0, q, recipient, "");
        assertEq(assetTST2.balanceOf(recipient), q);
    }

    function test_quoteExactOutput() public {
        vm.prank(owner);
        maglev.setConstantSumParams(Maglev.ConstantSumParams({fee: 0.003e18, priceA: 1, priceB: 1}));

        assetTST.mint(address(this), 100e18);

        uint256 q = maglev.quoteExactOutput(address(assetTST), address(assetTST2), 1e18);
        assertGt(q, 1e18);
        assetTST.transfer(address(maglev), q);

        maglev.swap(0, 1e18, recipient, "");
        assertEq(assetTST2.balanceOf(recipient), 1e18);
    }

    function test_fees(uint256 fee, uint256 amount1, bool token0) public {
        fee = bound(fee, 0, 0.02e18);
        amount1 = bound(amount1, 1e18, 25e18);

        vm.prank(owner);
        maglev.setConstantSumParams(Maglev.ConstantSumParams({fee: uint64(fee), priceA: 1, priceB: 1}));

        assetTST.mint(address(this), 100e18);
        assetTST2.mint(address(this), 100e18);

        uint256 needed = amount1 * 1e18 / (1e18 - fee);
        console.log(amount1, needed, fee);

        TestERC20 tt;
        TestERC20 tt2;
        uint256 a1;
        uint256 a2;

        if (token0) {
            tt = assetTST;
            tt2 = assetTST2;
            a1 = 0;
            a2 = amount1;
        } else {
            tt = assetTST2;
            tt2 = assetTST;
            a1 = amount1;
            a2 = 0;
        }

        tt.transfer(address(maglev), needed - 2);

        vm.expectRevert(Maglev.KNotSatisfied.selector);
        maglev.swap(a1, a2, recipient, "");

        tt.transfer(address(maglev), 2);
        maglev.swap(a1, a2, recipient, "");

        assertEq(tt2.balanceOf(recipient), amount1);
    }
}
