// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap, EulerSwap} from "../../src/EulerSwap.sol";
import {EulerSwapTestBase} from "./EulerSwapUtils.t.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

/// @title DeltaLP
/// @notice This contract acts as an automated rebalancing agent for a EulerSwap LP.
/// It monitors the LP's health factor and market prices to mitigate impermanent loss
/// by reinstalling the EulerSwap operator with updated parameters.
contract DeltaLP is Test {
    // --- Configuration ---
    uint256 public immutable targetHealthFactor; // e.g., 2e18 for a target of 2.0
    uint256 public immutable healthFactorDelta;  // e.g., 0.2e18 for a +/- 0.2 delta
    uint256 public immutable priceRatioDelta;    // e.g., 0.1e18 for a +/- 10% delta

    // --- System Contracts ---
    address public holder;
    IEulerSwap public eulerSwap;
    IEVault[] public vaults;
    EulerSwapTestBase public utils;

    constructor(
        address _holder,
        IEulerSwap _eulerSwap,
        IEVault[] memory _vaults,
        uint256 _targetHealthFactor,
        uint256 _healthFactorDelta,
        uint256 _priceRatioDelta,
        address _utils
    ) {
        holder = _holder;
        eulerSwap = _eulerSwap;
        vaults = _vaults;
        targetHealthFactor = _targetHealthFactor;
        healthFactorDelta = _healthFactorDelta;
        priceRatioDelta = _priceRatioDelta;
        utils = EulerSwapTestBase(_utils);
    }

    /// @notice Main function to check conditions and trigger rebalancing if needed.
    function rebalance(uint256 currentMarketPrice0, uint256 currentMarketPrice1) external {
        console.log("--- Running Delta LP Rebalancer ---");

        uint256 currentHealthFactor = _getHealthFactor();
        IEulerSwap.Params memory currentParams = eulerSwap.getParams();

        // --- Scenario 1: Health Factor Rebalancing ---
        if (currentHealthFactor < targetHealthFactor - healthFactorDelta || currentHealthFactor > targetHealthFactor + healthFactorDelta) {
            //addmodconsole.log("Health factor out of bounds. Rebalancing concentration...");
            
            uint256 newCx = currentParams.concentrationX;
            uint256 newCy = currentParams.concentrationY;

            // Get the liabilities in both vaults
            (uint256 liability0, uint256 liability1) = _getLiabilities();
            // The goal is to incentivize swaps that reduce the holder's largest liability.
            // By increasing the concentration on the *opposite* side of the largest debt,
            // we make it more profitable for arbitrageurs to sell the debt-asset back to the pool,
            // thus reducing the holder's liability and improving their health factor.
            if (liability0 > liability1) {
                //console.log("Liability in vault0 is higher. Increasing concentrationY to attract asset0.");
                newCy = (newCy * 101) / 100; // Increase concentration by 1%
            } else if (liability1 > liability0) {
                //console.log("Liability in vault1 is higher. Increasing concentrationX to attract asset1.");
                newCx = (newCx * 101) / 100; // Increase concentration by 1%
            }
            // If liabilities are equal or zero, no change is made, but we still proceed to reinstall
            // with potentially updated market prices if the price ratio is also out of bounds.

            eulerSwap = utils.reinstallOperator(eulerSwap, currentMarketPrice0, currentMarketPrice1, newCx, newCy);
            return;
        }

        // --- Scenario 2: Price Ratio Rebalancing ---
        uint256 initialPriceRatio = (currentParams.priceY * 1e18) / currentParams.priceX;
        uint256 currentPriceRatio = (currentMarketPrice1 * 1e18) / currentMarketPrice0;

        if (currentPriceRatio < initialPriceRatio - priceRatioDelta || currentPriceRatio > initialPriceRatio + priceRatioDelta) {
            console.log("Price ratio out of bounds. Rebalancing prices...");

            // Keep concentration the same, just update prices
            eulerSwap = utils.reinstallOperator(
                eulerSwap,
                currentMarketPrice0,
                currentMarketPrice1,
                currentParams.concentrationX,
                currentParams.concentrationY
            );
            vm.stopPrank();
            return;
        }

        console.log("No rebalancing needed.");
        vm.stopPrank();
    }

    /// @notice Calculates the health factor of the holder's account.
    function _getHealthFactor() internal view returns (uint256) {
        try vaults[0].accountLiquidity(holder, true) returns (uint256 collateralValue, uint256 liabilityValue) {
            if (liabilityValue == 0) return type(uint256).max;
            return (collateralValue * 1e18) / liabilityValue;
        } catch {
            return type(uint256).max;
        }
    }

    /// @notice Gets the liability values for the holder in both vaults.
    function _getLiabilities() internal view returns (uint256 liability0, uint256 liability1) {
        try vaults[0].accountLiquidity(holder, false) returns (uint256, uint256 _liability0) {
            liability0 = _liability0;
        } catch { liability0 = 0; }

        try vaults[1].accountLiquidity(holder, false) returns (uint256, uint256 _liability1) {
            liability1 = _liability1;
        } catch { liability1 = 0; }
    }
}
