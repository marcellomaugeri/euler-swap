// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MaglevBase} from "./MaglevBase.sol";

contract MaglevConstantSum is MaglevBase {
    uint64 fee;
    uint96 priceA;
    uint96 priceB;

    struct ConstantSumParams {
        uint64 fee;
        uint96 priceA;
        uint96 priceB;
    }

    constructor(BaseParams memory baseParams, ConstantSumParams memory params) MaglevBase(baseParams) {
        setConstantSumParams(params);
    }

    function setConstantSumParams(ConstantSumParams memory params) public onlyOwner {
        fee = params.fee;
        priceA = params.priceA;
        priceB = params.priceB;
    }

    function k(uint256 r0, uint256 r1) public view returns (uint256) {
        return (r0 * priceA) + (r1 * priceB);
    }

    function verify(
        uint256 oldReserve0,
        uint256 oldReserve1,
        uint256 amount0In,
        uint256 amount1In,
        uint256 newReserve0,
        uint256 newReserve1
    ) internal view virtual override {
        uint256 kBefore = k(oldReserve0, oldReserve1);
        uint256 kAfter = k(newReserve0 - (amount0In * fee / 1e18), newReserve1 - (amount1In * fee / 1e18));
        require(kAfter >= kBefore, "k not satisfied");
    }

    // FIXME: quote functions should consider limits like reserve size and vault utilisation

    function quoteGivenIn(uint256 amount, bool) public view returns (uint256) {
        return amount * (1e18 - fee) / 1e18;
    }

    function quoteGivenOut(uint256 amount, bool) public view returns (uint256) {
        return amount * 1e18 / (1e18 - fee);
    }
}
