// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {BaseAMMLev} from "./BaseAMMLev.sol";

/// @dev Simple constant-sum curve. FIXME: Assumes tokens are 1:1 pegged and have same decimals.
contract AMMLevConstantSum is BaseAMMLev {
    uint256 fee;

    constructor(BaseAMMLev.Params memory params, uint256 _fee) BaseAMMLev(params) {
        fee = _fee;
    }

    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    }

    function k(uint256 r0, uint256 r1) internal pure returns (uint256) {
        return r0 + r1;
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
