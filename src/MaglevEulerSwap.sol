// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MaglevBase} from "./MaglevBase.sol";
import {IMaglevEulerSwap} from "./interfaces/IMaglevEulerSwap.sol";

contract MaglevEulerSwap is IMaglevEulerSwap, MaglevBase {
    uint256 public immutable priceX;
    uint256 public immutable priceY;
    uint256 public immutable concentrationX;
    uint256 public immutable concentrationY;
    uint112 public immutable initialReserve0;
    uint112 public immutable initialReserve1;

    struct EulerSwapParams {
        uint256 priceX;
        uint256 priceY;
        uint256 concentrationX;
        uint256 concentrationY;
    }

    constructor(BaseParams memory baseParams, EulerSwapParams memory params) MaglevBase(baseParams) {
        priceX = params.priceX;
        priceY = params.priceY;
        concentrationX = params.concentrationX;
        concentrationY = params.concentrationY;

        initialReserve0 = reserve0;
        initialReserve1 = reserve1;
    }

    function fx(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        return y0 + px * 1e18 / py * (c * (2 * x0 - xt) / 1e18 + (1e18 - c) * x0 / 1e18 * x0 / xt - x0) / 1e18;
    }

    function verify(uint256 newReserve0, uint256 newReserve1) internal view virtual override returns (bool) {
        if (newReserve0 >= initialReserve0) {
            if (newReserve1 >= initialReserve1) return true;
            return newReserve0 >= fx(newReserve1, priceY, priceX, initialReserve1, initialReserve0, concentrationY);
        } else {
            if (newReserve1 < initialReserve1) return false;
            return newReserve1 >= fx(newReserve0, priceX, priceY, initialReserve0, initialReserve1, concentrationX);
        }
    }
}
