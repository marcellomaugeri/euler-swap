// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";

contract LimitsTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_basicLimits() public {
        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18); // max uint minus 110 (100 deposited by depositor, 10 by holder)
        assertEq(outLimit, 60e18);
    }

    function test_supplyCapExceeded() public {
        eTST.setCaps(uint16(2.72e2 << 6) | 18, 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, 0); // cap exceeded
        assertEq(outLimit, 60e18);
    }

    function test_supplyCapExtra() public {
        eTST.setCaps(uint16(2.72e2 << 6) | (18 + 2), 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, 162e18); // 272 - 110
        assertEq(outLimit, 60e18);
    }

    function test_utilisation() public {
        vm.prank(depositor);
        eTST2.withdraw(95e18, address(depositor), address(depositor));

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18);
        assertEq(outLimit, 15e18); // 110 - 95
    }

    function test_borrowCap() public {
        eTST2.setCaps(0, uint16(8.5e2 << 6) | 18);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18);
        assertEq(outLimit, 18.5e18); // 10 in balance, plus 8.5 borrow cap
    }
}
