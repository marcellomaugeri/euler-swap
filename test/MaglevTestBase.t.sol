// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {EVaultTestBase, TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

import {MaglevBase} from "../src/MaglevBase.sol";

contract MaglevTestBase is EVaultTestBase {
    address public depositor = makeAddr("depositor");
    address public owner = makeAddr("owner");
    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");

    function setUp() public override virtual {
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
    }

    function _getMaglevBaseParams() internal view returns (MaglevBase.BaseParams memory) {
        return MaglevBase.BaseParams({evc: address(evc), vault0: address(eTST), vault1: address(eTST2), myAccount: holder});
    }

    function _mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        TestERC20 tok = TestERC20(vault.asset());
        tok.mint(who, amount);

        vm.prank(who);
        tok.approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }
}
