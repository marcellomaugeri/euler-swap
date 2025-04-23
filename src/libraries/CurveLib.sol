// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

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

    /// @dev EulerSwap inverse function definition
    /// Pre-conditions: 0 < x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // components of quadratic equation
        int256 B;
        uint256 C;
        uint256 fourAC;
        unchecked {
            B = int256((py * (y - y0) + (px - 1)) / px) - (2 * int256(c) - int256(1e18)) * int256(x0) / 1e18;            
            if (x0 >= 1e18) {
                // if x0 >= 1, scale as normal
                C = Math.mulDiv((1e18 - c), x0 * x0, 1e36, Math.Rounding.Ceil);
                fourAC = 4 * c * C;
            } else {
                // if x0 < 1, then numbers get very small, so decrease scale to 1e18 to increase precision later
                C = ((1e18 - c) * x0 * x0 + (1e18 - 1)) / 1e18;
                fourAC = Math.mulDiv(4 * c, C, 1e18, Math.Rounding.Ceil);
            }
        }
        
        uint256 absB = uint256(B >= 0 ? B : -B);
        uint256 squaredB;
        uint256 discriminant;
        uint256 sqrt;
        if (absB < 1e36) {
            // safe to use naive squaring
            unchecked {
                squaredB = absB * absB;
                discriminant = squaredB + fourAC; // keep in 1e36 scale for increased precision ahead of sqrt
                sqrt = Math.sqrt(discriminant); // drop back to 1e18 scale
                sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
            }                    
        } else {
            // use scaled, overflow-safe path
            uint256 scale = computeScale(absB);
            squaredB = Math.mulDiv(absB / scale, absB, scale, Math.Rounding.Ceil);
            discriminant = squaredB + fourAC / (scale * scale);
            sqrt = Math.sqrt(discriminant);
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
            sqrt = sqrt * scale;
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

    /// @dev Utility to derive optimal scale for computations in fInverse
    function computeScale(uint256 x) internal pure returns (uint256 scale) {
        // calculate number of bits in x
        uint256 bits = 0;
        while (x > 0) {
            x >>= 1;
            bits++;
        }

        // 2^excessBits is how much we need to scale down to prevent overflow when squaring x
        if (bits > 128) {
            uint256 excessBits = bits - 128;            
            scale = 1 << excessBits;
        } else {
            scale = 1;
        }
    }

    /// @dev Less efficient method to compute fInverse. Useful for testing.
    function binarySearch(IEulerSwap.Params memory p, uint256 newReserve1, uint256 xMin, uint256 xMax)
        internal
        pure
        returns (uint256)
    {
        if (xMin < 1) {
            xMin = 1;
        }
        while (xMin < xMax) {
            uint256 xMid = (xMin + xMax) / 2;
            uint256 fxMid = f(xMid, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX);
            if (newReserve1 >= fxMid) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        if (newReserve1 < f(xMin, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX)) {
            xMin += 1;
        }
        return xMin;
    }
}
