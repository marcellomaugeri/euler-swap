## Implementation of `f`

### Derivation

Formula 15 from the whitepaper:

    y0 + (px / py) * (x0 - x) * (c + (1 - c) * (x0 / x))

Multiply second term by `x/x`:

    y0 + (px / py) * (x0 - x) * ((c * x) + (1 - c) * x0) / x

`c` is scaled by `1e18`:

    y0 + (px / py) * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18)

Re-order division by `py`:

    y0 + px * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18) / py

Use `mulDiv` to avoid intermediate overflow:

    y0 + Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18) / py

Round up for both divisions (operation is distributive):

    y0 + (Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil) + (py-1)) / py

### Boundary Analysis

Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18

None of the computations for the arguments to `mulDiv` can overflow:

* Arg 1: `px * (x0 - x)`
  * Upper-bound: `1e36*(2**112 - 1) =~ 232 bits`
* Arg 2: `c * x + (1e18 - c) * x0`
  * Upper-bound: `1e18*(2**112 - 1)*2 =~ 173 bits`
* Arg 3: `x * 1e18`
  * Upper-bound: `1e18*(2**112 - 1) =~ 172 bits`

If amounts/prices are large, and we travel too far down the curve, then `mulDiv` (or the subsequent `y0` addition) could overflow because its output value cannot be represented as a `uint256`. However, these output values would never be valid anyway, because they exceed `type(uint112).max`.
