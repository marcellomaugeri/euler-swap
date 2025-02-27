// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, IEulerSwap, IEVC, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";

contract EulerSwapFactoryTest is EulerSwapTestBase {
    EulerSwapFactory public eulerSwapFactory;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(creator);
        eulerSwapFactory = new EulerSwapFactory(address(evc));
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.allPoolsLength();

        IEulerSwapFactory.DeployParams memory deployParams = IEulerSwapFactory.DeployParams(
            address(eTST), address(eTST2), holder, 0, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
        );
        bytes32 salt = bytes32(uint256(1234));

        address predictedAddress = predictPoolAddress(address(eulerSwapFactory), deployParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, predictedAddress, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (deployParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        EulerSwap eulerSwap = EulerSwap(eulerSwapFactory.swapAccountToPool(holder));

        uint256 allPoolsLengthAfter = eulerSwapFactory.allPoolsLength();
        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);

        address[] memory poolsList = eulerSwapFactory.getAllPoolsListSlice(0, type(uint256).max);
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], address(eulerSwap));
        assertEq(eulerSwapFactory.allPools(0), address(eulerSwap));

        items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (deployParams, bytes32(uint256(12345))))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.OldOperatorStillInstalled.selector);
        evc.batch(items);   
    }

    function testInvalidGetAllPoolsListSliceQuery() public {
        vm.expectRevert(EulerSwapFactory.InvalidQuery.selector);
        eulerSwapFactory.getAllPoolsListSlice(1, 0);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        bytes32 salt = bytes32(uint256(1234));

        vm.prank(holder);
        vm.expectRevert(EulerSwap.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(
            IEulerSwapFactory.DeployParams(
                address(eTST), address(eTST), holder, 0, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
            ),
            salt
        );
    }

    function testDeployWithBadFee() public {
        bytes32 salt = bytes32(uint256(1234));

        vm.prank(holder);
        vm.expectRevert(EulerSwap.BadFee.selector);
        eulerSwapFactory.deployPool(
            IEulerSwapFactory.DeployParams(
                address(eTST), address(eTST2), holder, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
            ),
            salt
        );
    }

    function predictPoolAddress(address factoryAddress, IEulerSwapFactory.DeployParams memory params, bytes32 salt)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factoryAddress,
                            keccak256(abi.encode(address(params.swapAccount), salt)),
                            keccak256(
                                abi.encodePacked(
                                    type(EulerSwap).creationCode,
                                    abi.encode(
                                        IEulerSwap.Params({
                                            vault0: params.vault0,
                                            vault1: params.vault1,
                                            myAccount: params.swapAccount,
                                            debtLimit0: params.debtLimit0,
                                            debtLimit1: params.debtLimit1,
                                            fee: params.fee
                                        }),
                                        IEulerSwap.CurveParams({
                                            priceX: params.priceX,
                                            priceY: params.priceY,
                                            concentrationX: params.concentrationX,
                                            concentrationY: params.concentrationY
                                        })
                                    )
                                )
                            )
                        )
                    )
                )
            )
        );
    }
}
