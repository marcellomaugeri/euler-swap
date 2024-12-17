// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IMaglevBase} from "./IMaglevBase.sol";

interface IMaglevEulerSwap is IMaglevBase {
    function priceX() external view returns (uint256);
    function priceY() external view returns (uint256);
    function concentrationX() external view returns (uint256);
    function concentrationY() external view returns (uint256);
    function initialReserve0() external view returns (uint112);
    function initialReserve1() external view returns (uint112);
}
