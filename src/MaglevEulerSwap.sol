// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MaglevBase} from "./MaglevBase.sol";

contract MaglevEulerSwap is MaglevBase {
    uint256 public _px;
    uint256 public _py;
    uint256 public _cx;
    uint256 public _cy;

    error KNotSatisfied();

    struct EulerSwapParams {
        uint256 px;
        uint256 py;
        uint256 cx;
        uint256 cy;
    }

    constructor(BaseParams memory baseParams, EulerSwapParams memory params) MaglevBase(baseParams) {
        setEulerSwapParams(params);
    }

    function setEulerSwapParams(EulerSwapParams memory params) public onlyOwner {
        _px = params.px;
        _py = params.py;
        _cx = params.cx;
        _cy = params.cy;
    }

    function verify(uint256, uint256, uint256 newReserve0, uint256 newReserve1) internal view virtual override {
        require(
            verifyCurve(newReserve0, newReserve1, _px, _py, initialReserve0, initialReserve1, _cx, _cy), KNotSatisfied()
        );
    }

    uint256 private constant roundingCompensation = 1.0000000000001e18;

    function computeQuote(uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        int256 dx;
        int256 dy;

        if (exactIn) {
            if (asset0IsInput) dx = int256(amount);
            else dy = int256(amount);
        } else {
            if (asset0IsInput) dy = -int256(amount);
            else dx = -int256(amount);
        }

        (dx, dy) = simulateSwap(dx, dy, reserve0, reserve1, _px, _py, initialReserve0, initialReserve1, _cx, _cy);

        uint256 output;

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
            output = output * 1e18 / roundingCompensation;
        } else {
            if (asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
            output = output * roundingCompensation / 1e18;
        }

        return output;
    }

    /////

    function fx(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(xt > 0, "Reserves must be greater than zero");
        if (xt <= x0) {
            return fx1(xt, px, py, x0, y0, cx, cy);
        } else {
            return fx2(xt, px, py, x0, y0, cx, cy);
        }
    }

    function fx1(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256)
        internal
        pure
        returns (uint256)
    {
        require(xt <= x0, "Invalid input coordinate");
        return y0 + px * 1e18 / py * (cx * (2 * x0 - xt) / 1e18 + (1e18 - cx) * x0 / 1e18 * x0 / xt - x0) / 1e18;
    }

    function fx2(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(xt > x0, "Invalid input coordinate");
        // intermediate values for solving quadratic equation
        uint256 a = cy;
        int256 b = (int256(px) * 1e18 / int256(py)) * (int256(xt) - int256(x0)) / 1e18
            + int256(y0) * (1e18 - 2 * int256(cy)) / 1e18;
        int256 c = (int256(cy) - 1e18) * int256(y0) ** 2 / 1e18 / 1e18;
        uint256 discriminant = uint256(int256(uint256(b ** 2)) - 4 * int256(a) * int256(c));
        uint256 numerator = uint256(-b + int256(uint256(Math.sqrt(discriminant))));
        uint256 denominator = 2 * a;
        return numerator * 1e18 / denominator;
    }

    function fy(uint256 yt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(yt > 0, "Reserves must be greater than zero");
        if (yt <= y0) {
            return fx1(yt, py, px, y0, x0, cy, cx);
        } else {
            return fx2(yt, py, px, y0, x0, cy, cx);
        }
    }

    function simulateSwap(
        int256 dx,
        int256 dy,
        uint256 xt,
        uint256 yt,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 cx,
        uint256 cy
    ) internal pure returns (int256, int256) {
        int256 xtNew = int256(xt);
        int256 ytNew = int256(yt);

        if (dx != 0) {
            xtNew += dx;
            ytNew = int256(fx(uint256(xtNew), px, py, x0, y0, cx, cy));
        }
        if (dy != 0) {
            ytNew += dy;
            xtNew = int256(fy(uint256(ytNew), px, py, x0, y0, cx, cy));
        }
        dx = xtNew - int256(xt);
        dy = ytNew - int256(yt);

        return (dx, dy);
    }

    function verifyCurve(uint256 xt, uint256 yt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        internal
        pure
        returns (bool)
    {
        int256 delta = 0;

        if (xt >= x0) {
            delta = int256(xt) - int256(fy(yt, px, py, x0, y0, cx, cy));
        } else {
            delta = int256(yt) - int256(fx(xt, px, py, x0, y0, cx, cy));
        }

        // if distance is > zero, then point is above the curve, and invariant passes
        return (delta >= 0);
    }
}
