// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {MaglevBase} from "./MaglevBase.sol";

contract MaglevConstantSum is MaglevBase {
    uint256 public immutable priceX;
    uint256 public immutable priceY;

    error KNotSatisfied();

    struct ConstantSumParams {
        uint256 priceX;
        uint256 priceY;
    }

    constructor(BaseParams memory baseParams, ConstantSumParams memory params) MaglevBase(baseParams) {
        priceX = params.priceX;
        priceY = params.priceY;
    }

    function k(uint256 r0, uint256 r1) public view returns (uint256) {
        return (r0 * priceX) + (r1 * priceY);
    }

    function verify(uint256 newReserve0, uint256 newReserve1) internal view virtual override {
        uint256 kBefore = k(reserve0, reserve1);
        uint256 kAfter = k(newReserve0, newReserve1);
        require(kAfter >= kBefore, KNotSatisfied());
    }

    function computeQuote(uint256 amount, bool, bool) internal view virtual override returns (uint256) {
        // FIXME: use priceX and priceY
        return amount;
    }
}
