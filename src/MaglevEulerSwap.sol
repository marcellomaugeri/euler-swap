// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MaglevBase} from "./MaglevBase.sol";

contract MaglevEulerSwap is MaglevBase {
    uint256 public immutable priceX;
    uint256 public immutable priceY;
    uint256 public immutable concentrationX;
    uint256 public immutable concentrationY;
    uint112 public immutable initialReserve0;
    uint112 public immutable initialReserve1;

    error KNotSatisfied();
    error ReservesZero();
    error InvalidInputCoordinate();

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

    // Due to rounding, computeQuote() may underestimate the amount required to
    // pass the verify() function. In order to prevent swaps from failing, quotes
    // are inflated by this compensation factor. FIXME: solve the rounding.
    uint256 private constant roundingCompensation = 1.0000000000001e18;

    function verify(uint256 newReserve0, uint256 newReserve1) internal view virtual override {
        int256 delta = 0;

        if (newReserve0 >= initialReserve0) {
            delta = int256(newReserve0)
                - int256(fy(newReserve1, priceX, priceY, initialReserve0, initialReserve1, concentrationX, concentrationY));
        } else {
            delta = int256(newReserve1)
                - int256(fx(newReserve0, priceX, priceY, initialReserve0, initialReserve1, concentrationX, concentrationY));
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
                reserve1New = int256(
                    fx(
                        uint256(reserve0New),
                        priceX,
                        priceY,
                        initialReserve0,
                        initialReserve1,
                        concentrationX,
                        concentrationY
                    )
                );
            }
            if (dy != 0) {
                reserve1New += dy;
                reserve0New = int256(
                    fy(
                        uint256(reserve1New),
                        priceX,
                        priceY,
                        initialReserve0,
                        initialReserve1,
                        concentrationX,
                        concentrationY
                    )
                );
            }

            dx = reserve0New - int256(uint256(reserve0));
            dy = reserve1New - int256(uint256(reserve1));
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
            output = output * 1e18 / roundingCompensation;
        } else {
            if (asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
            output = output * roundingCompensation / 1e18;
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
