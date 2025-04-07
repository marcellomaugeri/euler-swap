// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";

library CurveLib {
    error Overflow();
    error CurveViolation();

    /// @notice Returns true iff the specified reserve amounts would be acceptable.
    /// Acceptable points are on, or above and to-the-right of the swapping curve.
    function verify(IEulerSwap.Params memory p, uint256 newReserve0, uint256 newReserve1)
        internal
        pure
        returns (bool)
    {
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) return false;

        if (newReserve0 >= p.equilibriumReserve0) {
            if (newReserve1 >= p.equilibriumReserve1) return true;
            return newReserve0
                >= f(newReserve1, p.priceY, p.priceX, p.equilibriumReserve1, p.equilibriumReserve0, p.concentrationY);
        } else {
            if (newReserve1 < p.equilibriumReserve1) return false;
            return newReserve1
                >= f(newReserve0, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX);
        }
    }

    /// @dev EulerSwap curve definition
    /// Pre-conditions: 0 < x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, Overflow());
            return y0 + (v + (py - 1)) / py;
        }
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // components of quadratic equation
        int256 B = int256((py * (y - y0) + (px - 1)) / px) - (2 * int256(c) - int256(1e18)) * int256(x0) / 1e18;
        uint256 C;
        uint256 fourAC;
        if (x0 < 1e18) {
            C = ((1e18 - c) * x0 * x0 + (1e18 - 1)) / 1e18; // upper bound of 1e28 for x0 means this is safe
            fourAC = Math.mulDiv(4 * c, C, 1e18, Math.Rounding.Ceil);
        } else {
            C = Math.mulDiv((1e18 - c), x0 * x0, 1e36, Math.Rounding.Ceil); // upper bound of 1e28 for x0 means this is safe
            fourAC = Math.mulDiv(4 * c, C, 1, Math.Rounding.Ceil);
        }

        // solve for the square root
        uint256 absB = abs(B);
        uint256 squaredB;
        uint256 discriminant;
        uint256 sqrt;
        if (absB > 1e33) {
            uint256 scale = computeScale(absB);
            squaredB = Math.mulDiv(absB / scale, absB, scale, Math.Rounding.Ceil);
            discriminant = squaredB + fourAC / (scale * scale);
            sqrt = Math.sqrt(discriminant);
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
            sqrt = sqrt * scale;
        } else {
            squaredB = Math.mulDiv(absB, absB, 1, Math.Rounding.Ceil);
            discriminant = squaredB + fourAC; // keep in 1e36 scale for increased precision ahead of sqrt
            sqrt = Math.sqrt(discriminant); // drop back to 1e18 scale
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
        }

        uint256 x;
        if (B <= 0) {
            x = Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 3;
        } else {
            x = Math.mulDiv(2 * C, 1e18, absB + sqrt, Math.Rounding.Ceil) + 3;
        }

        if (x >= x0) {
            return x0;
        } else {
            return x;
        }
    }

    function computeScale(uint256 x) internal pure returns (uint256 scale) {
        uint256 bits = 0;
        uint256 tmp = x;

        while (tmp > 0) {
            tmp >>= 1;
            bits++;
        }

        // absB * absB must be <= 2^256 ⇒ bits(B) ≤ 128
        if (bits > 128) {
            uint256 excessBits = bits - 128;
            // 2^excessBits is how much we need to scale down to prevent overflow
            scale = 1 << excessBits;
        } else {
            scale = 1;
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}
