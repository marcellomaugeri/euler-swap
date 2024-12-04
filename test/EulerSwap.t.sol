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
        maglev = new Maglev(_getMaglevBaseParams(), Maglev.EulerSwapParams({junk: 0}));

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(owner);
        maglev.configure();

        vm.prank(owner);
        maglev.setVirtualReserves(50e18, 50e18);
    }

    function test_basicSwap() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = 0.3e18;

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }
}
