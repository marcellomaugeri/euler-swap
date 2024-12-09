// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {console} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MaglevBase} from "./MaglevBase.sol";

contract MaglevEulerSwap is MaglevBase {
    uint256 public _px;
    uint256 public _py;
    uint256 public _cx;
    uint256 public _cy;
    uint256 public _fee;

    error KNotSatisfied();
    error ReservesZero();
    error InvalidInputCoordinate();

    struct EulerSwapParams {
        uint256 px;
        uint256 py;
        uint256 cx;
        uint256 cy;
        uint256 fee;
    }

    constructor(BaseParams memory baseParams, EulerSwapParams memory params) MaglevBase(baseParams) {
        setEulerSwapParams(params);
    }

    function setEulerSwapParams(EulerSwapParams memory params) public onlyOwner {
        _px = params.px;
        _py = params.py;
        _cx = params.cx;
        _cy = params.cy;
        _fee = Math.max(params.fee, 1.0000000000001e18); // minimum fee required to compensate for rounding
    }

    // FIXME: how to charge fees?
    function verify(uint256, uint256, uint256 newReserve0, uint256 newReserve1) internal view virtual override {
        int256 delta = 0;

        if (newReserve0 >= initialReserve0) {
            delta = int256(newReserve0) - int256(fy(newReserve1, _px, _py, initialReserve0, initialReserve1, _cx, _cy));
        } else {
            delta = int256(newReserve1) - int256(fx(newReserve0, _px, _py, initialReserve0, initialReserve1, _cx, _cy));
        }

        // if delta is >= zero, then point is on or above the curve
        require(delta >= 0, KNotSatisfied());
    }

    function computeQuote(uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        virtual
        override
        returns (uint256 output)
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

        {
            int256 reserve0New = int256(uint256(reserve0));
            int256 reserve1New = int256(uint256(reserve1));

            if (dx != 0) {
                reserve0New += dx;
                reserve1New = int256(fx(uint256(reserve0New), _px, _py, initialReserve0, initialReserve1, _cx, _cy));
            }
            if (dy != 0) {
                reserve1New += dy;
                reserve0New = int256(fy(uint256(reserve1New), _px, _py, initialReserve0, initialReserve1, _cx, _cy));
            }

            dx = reserve0New - int256(uint256(reserve0));
            dy = reserve1New - int256(uint256(reserve1));
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
            output = output * 1e18 / _fee;
        } else {
            if (asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
            output = output * _fee / 1e18;
        }
    }

    ///// Curve math routines

    function fx(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(xt > 0, ReservesZero());
        if (xt <= x0) {
            return fx1(xt, px, py, x0, y0, cx, cy);
        } else {
            return fx2(xt, px, py, x0, y0, cx, cy);
        }
    }

    function fy(uint256 yt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(yt > 0, ReservesZero());
        if (yt <= y0) {
            return fx1(yt, py, px, y0, x0, cy, cx);
        } else {
            return fx2(yt, py, px, y0, x0, cy, cx);
        }
    }

    function fx1(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256)
        internal
        pure
        returns (uint256)
    {
        require(xt <= x0, InvalidInputCoordinate());
        return y0 + px * 1e18 / py * (cx * (2 * x0 - xt) / 1e18 + (1e18 - cx) * x0 / 1e18 * x0 / xt - x0) / 1e18;
    }

    function fx2(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256, uint256 cy)
        internal
        pure
        returns (uint256)
    {
        require(xt > x0, InvalidInputCoordinate());
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
}
