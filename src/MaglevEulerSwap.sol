// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import {MaglevBase} from "./MaglevBase.sol";

contract MaglevEulerSwap is MaglevBase {

    error KNotSatisfied();

    struct EulerSwapParams {
        uint256 junk;
    }

    constructor(BaseParams memory baseParams, EulerSwapParams memory params) MaglevBase(baseParams) {
        setEulerSwapParams(params);
    }

    function setEulerSwapParams(EulerSwapParams memory params) public onlyOwner {
    }

    function verify(uint256, uint256, uint256 newReserve0, uint256 newReserve1)
        internal
        view
        virtual
        override
    {
        uint256 px = 1e18;
        uint256 py = 1e18;
        uint256 cx = 0.40e18;
        uint256 cy = 0.85e18;

        //require(_verify(49e18, 51e18, px, py, 50e18, 50e18, cx, cy), KNotSatisfied());

        console.log("QQ", newReserve0, newReserve1);
        console.log("ZZ", initialReserve0, initialReserve1);
        require(_verify(newReserve0, newReserve1, px, py, initialReserve0, initialReserve1, cx, cy), KNotSatisfied());
    }

    function computeQuote(uint256, bool, bool)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return 0;
    }



    /////

    function fx(uint xt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (uint){
        require(xt > 0, "Reserves must be greater than zero");
        if (xt <= x0) {
            return fx1(xt, px, py, x0, y0, cx, cy);
        } else {
            return fx2(xt, px, py, x0, y0, cx, cy);
        }
    }

    function fx1(uint xt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (uint){
        require(xt <= x0, "Invalid input coordinate");
        return y0 + px * 1e18 / py * (cx * (2 * x0 - xt) / 1e18 + (1e18 - cx) * x0 / 1e18 * x0 / xt - x0) / 1e18;
    }

    function fx2(uint xt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (uint){
        require(xt > x0, "Invalid input coordinate");
        // intermediate values for solving quadratic equation
        uint a = cy;
        int b = (int(px) * 1e18 / int(py)) * (int(xt) - int(x0)) / 1e18 + int(y0) * (1e18 - 2 * int(cy)) / 1e18;
        int c = (int(cy) - 1e18) * int(y0)**2 / 1e18 / 1e18;
        uint discriminant = uint(int(uint(b**2) / 1e18) - 4 * int(a) * int(c) / 1e18);
        uint numerator = uint(-b + int(uint(sqrt(discriminant) * 1e9)));
        uint denominator = 2 * a;
        return numerator * 1e18 / denominator;
    }

    function fy(uint yt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (uint){
        require(yt > 0, "Reserves must be greater than zero");
        if (yt <= y0) {
            return fx1(yt, py, px, y0, x0, cy, cx);
        } else {
            return fx2(yt, py, px, y0, x0, cy, cx);
        }
    }


    function swap(int dx, int dy, uint xt, uint yt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (int, int) {
        int xtNew = int(xt);
        int ytNew = int(yt);

        if (dx != 0) {
            xtNew += dx;
            ytNew = int(fx(uint(xtNew), px, py, x0, y0, cx, cy));
        }
        if (dy != 0) {
            ytNew += dy;
            xtNew = int(fy(uint(ytNew), px, py, x0, y0, cx, cy));
        }
        dx = xtNew - int(xt);
        dy = ytNew - int(yt);

        //   // check invariant
        //   let invariantPassed = invariantCheck(xtNew, ytNew, parameters);

        return (dx, dy);
    }

    function _verify(uint xt, uint yt, uint px, uint py, uint x0, uint y0, uint cx, uint cy) public pure returns (bool){
        bool passed = false;
        int delta = 0;
        if(xt >= x0) {
            delta = int(xt) - int(fy(yt, px, py, x0, y0, cx, cy));
            console.log("xt: ", int(xt));
            console.log("fy: ", int(fy(yt, px, py, x0, y0, cx, cy)));
        } else {
            delta = int(yt) - int(fx(xt, px, py, x0, y0, cx, cy));
            console.log("yt: ", int(yt));
            console.log("fx: ", int(fx(xt, px, py, x0, y0, cx, cy)));
        }
        
        if (delta >= 0) {
            // if distance is > zero, then point is above the curve, and invariant passes
            passed = true;
        } 
        return passed;
    }

    function sqrt(uint256 x) public pure returns (uint128) {
        if (x == 0) return 0;
        else{
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
            if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
            if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
            if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
            if (xx >= 0x100) { xx >>= 8; r <<= 4; }
            if (xx >= 0x10) { xx >>= 4; r <<= 2; }
            if (xx >= 0x8) { r <<= 1; }
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            uint256 r1 = x / r;
            return uint128 (r < r1 ? r : r1);
        }
    }
}
