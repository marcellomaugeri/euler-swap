// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
// import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";
import {MaglevEulerSwap as Maglev, MaglevBase} from "../src/MaglevEulerSwap.sol";
import {MaglevEulerSwapFactory} from "../src/MaglevEulerSwapFactory.sol";

contract MaglevEulerSwapFactoryTest is MaglevTestBase {
    MaglevEulerSwapFactory public eulerSwapFactory;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(creator);
        eulerSwapFactory = new MaglevEulerSwapFactory(address(evc));
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.allPoolsLength();

        vm.prank(creator);
        Maglev maglev = Maglev(
            eulerSwapFactory.deployPool(
                address(eTST), address(eTST2), holder, 50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18
            )
        );

        uint256 allPoolsLengthAfter = eulerSwapFactory.allPoolsLength();

        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);
        assertEq(eulerSwapFactory.getPool(maglev.asset0(), maglev.asset1(), maglev.feeMultiplier()), address(maglev));
        assertEq(eulerSwapFactory.getPool(maglev.asset1(), maglev.asset0(), maglev.feeMultiplier()), address(maglev));

        address[] memory poolsList = eulerSwapFactory.getAllPoolsListSlice(0, type(uint256).max);
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], address(maglev));
        assertEq(eulerSwapFactory.allPools(0), address(maglev));
    }

    function testDeployPoolWhenAldreadyRegistered() public {
        vm.prank(creator);
        eulerSwapFactory.deployPool(address(eTST), address(eTST2), holder, 50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        vm.prank(creator);
        vm.expectRevert(MaglevEulerSwapFactory.PoolAlreadyDeployed.selector);
        eulerSwapFactory.deployPool(address(eTST), address(eTST2), holder, 50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function testInvalidGetAllPoolsListSliceQuery() public {
        vm.expectRevert(MaglevEulerSwapFactory.InvalidQuery.selector);
        eulerSwapFactory.getAllPoolsListSlice(1, 0);
    }

    function testDeployWithUnsupportedPair() public {
        vm.prank(creator);
        vm.expectRevert(MaglevBase.UnsupportedPair.selector);
        eulerSwapFactory.deployPool(address(eTST), address(eTST), holder, 50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function testDeployWithBadFee() public {
        vm.prank(creator);
        vm.expectRevert(MaglevBase.BadFee.selector);
        eulerSwapFactory.deployPool(
            address(eTST), address(eTST2), holder, 50e18, 50e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18
        );
    }
}
