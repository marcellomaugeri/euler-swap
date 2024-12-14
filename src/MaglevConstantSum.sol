// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {MaglevBase} from "./MaglevBase.sol";

contract MaglevConstantSum is MaglevBase {
    uint256 public immutable priceA;
    uint256 public immutable priceB;

    error KNotSatisfied();

    struct ConstantSumParams {
        uint256 priceA;
        uint256 priceB;
    }

    constructor(BaseParams memory baseParams, ConstantSumParams memory params) MaglevBase(baseParams) {
        priceA = params.priceA;
        priceB = params.priceB;
    }

    function k(uint256 r0, uint256 r1) public view returns (uint256) {
        return (r0 * priceA) + (r1 * priceB);
    }

    function verify(uint256 newReserve0, uint256 newReserve1) internal view virtual override {
        uint256 kBefore = k(reserve0, reserve1);
        uint256 kAfter = k(newReserve0, newReserve1);
        require(kAfter >= kBefore, KNotSatisfied());
    }

    // FIXME: incorporate priceA and priceB

    function computeQuote(uint256 amount, bool, bool) internal view virtual override returns (uint256) {
        return amount;
    }
}
