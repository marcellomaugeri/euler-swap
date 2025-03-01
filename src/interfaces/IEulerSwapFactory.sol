// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IEulerSwap} from "./IEulerSwap.sol";

interface IEulerSwapFactory {
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
        external
        returns (address);

    function allPools(uint256 index) external view returns (address);
    function allPoolsLength() external view returns (uint256);
    function getAllPoolsListSlice(uint256 start, uint256 end) external view returns (address[] memory);
}
