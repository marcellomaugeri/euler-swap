// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault, IERC20, IBorrowing, IERC4626} from "evk/EVault/IEVault.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";

import {BaseAMMLev} from "../../src/AMMLev/BaseAMMLev.sol";
import {AMMLevConstantSum as AMMLev} from "../../src/AMMLev/AMMLevConstantSum.sol";

contract AMMLevTest is EVaultTestBase {
    AMMLev public ammlev;

    address public depositor = makeAddr("depositor");
    address public owner = makeAddr("owner");
    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");

    function setUp() public override {
        super.setUp();

        // Vault config

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2.setLTV(address(eTST), 0.9e4, 0.9e4, 0);

        // Pricing

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);

        oracle.setPrice(address(assetTST), address(assetTST2), 1e18);
        oracle.setPrice(address(assetTST2), address(assetTST), 1e18);

        // Funding

        _mintAndDeposit(depositor, eTST, 100e18);
        _mintAndDeposit(depositor, eTST2, 100e18);

        _mintAndDeposit(holder, eTST, 10e18);
        _mintAndDeposit(holder, eTST2, 10e18);

        // Setup AMMLev

        vm.prank(owner);
        ammlev = new AMMLev(
            BaseAMMLev.Params({evc: address(evc), vault0: address(eTST), vault1: address(eTST2), myAccount: holder}), 0
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(ammlev), true);

        vm.prank(owner);
        ammlev.configure(100e18, 100e18);
    }

    function _mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        TestERC20 tok = TestERC20(vault.asset());
        tok.mint(who, amount);

        vm.prank(who);
        tok.approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }

    function test_basicSwapReport() public {
        uint256 amount = 25e18;
        assetTST.mint(address(this), amount);

        logState();

        assetTST.transfer(address(ammlev), amount);
        ammlev.swap(0, amount, address(this), "");
        assertEq(assetTST2.balanceOf(address(this)), amount);

        logState();

        uint256 amount2 = 50e18;
        assetTST2.mint(address(this), amount2);
        assetTST2.transfer(address(ammlev), amount2);
        ammlev.swap(amount2, 0, address(this), "");

        assetTST2.transfer(address(ammlev), 1e18);
        ammlev.swap(1e18, 0, address(this), "");

        logState();
    }

    function test_basicSwapFuzz(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1e18, 25e18);
        amount2 = bound(amount2, 1e18, 50e18);

        assetTST.mint(address(this), amount1);
        assetTST.transfer(address(ammlev), amount1);
        ammlev.swap(0, amount1, address(this), "");
        assertEq(assetTST.balanceOf(address(this)), 0);
        assertEq(assetTST2.balanceOf(address(this)), amount1);

        assetTST2.mint(address(this), amount2);
        assetTST2.transfer(address(ammlev), amount2);
        ammlev.swap(amount2, 0, address(this), "");
        assertEq(assetTST.balanceOf(address(this)), amount2);
        assertEq(assetTST2.balanceOf(address(this)), amount1);
    }

    function logState() internal view {
        console.log("--------------------");
        console.log("Account States:");
        console.log("HOLDER");
        console.log("  eTST Vault assets:  ", eTST.convertToAssets(eTST.balanceOf(holder)));
        console.log("  eTST Vault debt:    ", eTST.debtOf(holder));
        console.log("  eTST2 Vault assets: ", eTST2.convertToAssets(eTST2.balanceOf(holder)));
        console.log("  eTST2 Vault debt:   ", eTST2.debtOf(holder));
    }

    function test_quoteGivenIn() public {
        vm.prank(owner);
        ammlev.setFee(0.003e18);

        assetTST.mint(address(this), 100e18);
        uint256 q = ammlev.quoteGivenIn(1e18, true);
        assertLt(q, 1e18);
        assetTST.transfer(address(ammlev), 1e18);

        ammlev.swap(0, q, recipient, "");
        assertEq(assetTST2.balanceOf(recipient), q);
    }

    function test_quoteGivenOut() public {
        vm.prank(owner);
        ammlev.setFee(0.003e18);

        assetTST.mint(address(this), 100e18);

        uint256 q = ammlev.quoteGivenOut(1e18, true);
        assertGt(q, 1e18);
        assetTST.transfer(address(ammlev), q);

        ammlev.swap(0, 1e18, recipient, "");
        assertEq(assetTST2.balanceOf(recipient), 1e18);
    }

    function test_fees(uint256 fee, uint256 amount1, bool token0) public {
        fee = bound(fee, 0, 0.02e18);
        amount1 = bound(amount1, 1e18, 25e18);

        vm.prank(owner);
        ammlev.setFee(fee);

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

        tt.transfer(address(ammlev), needed - 2);

        vm.expectRevert(bytes("k not satisfied"));
        ammlev.swap(a1, a2, recipient, "");

        tt.transfer(address(ammlev), 2);
        ammlev.swap(a1, a2, recipient, "");

        assertEq(tt2.balanceOf(recipient), amount1);
    }
}
