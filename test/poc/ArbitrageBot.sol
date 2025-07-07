// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap} from "../../src/EulerSwap.sol";
import {EulerSwapPeriphery} from "../../src/EulerSwapPeriphery.sol";
import {TestERC20} from "./EulerSwapUtils.t.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract ArbitrageBot is Test {
    address public botAddress;
    EulerSwapPeriphery public periphery;
    TestERC20[] public tokens;
    IEVault[] public vaults;
    IEulerSwap public eulerSwap;
    address public holder;

    constructor(
        address _botAddress,
        EulerSwapPeriphery _periphery,
        TestERC20[] memory _tokens,
        IEVault[] memory _vaults,
        IEulerSwap _eulerSwap,
        address _holder
    ) {
        botAddress = _botAddress;
        periphery = _periphery;
        tokens = _tokens;
        vaults = _vaults;
        eulerSwap = _eulerSwap;
        holder = _holder;
    }

    /// @notice Update the EulerSwap pool address after reinstallation
    function updatePool(IEulerSwap _eulerSwap) external {
        eulerSwap = _eulerSwap;
    }

    function run(uint256 marketPrice0, uint256 marketPrice1) external {
        //console.log("--- Running Dynamic Predatory Arbitrage Bot ---");
        vm.startPrank(botAddress);

        uint256 debt0 = vaults[0].debtOf(holder);
        uint256 debt1 = vaults[1].debtOf(holder);

        uint256 realMarketPrice = (marketPrice1 * 1e18) / marketPrice0;

        (uint112 r0, uint112 r1, ) = eulerSwap.getReserves();
        uint256 poolPrice;
        if (r1 > 0) {
            poolPrice = (uint256(r0) * 1e12 * 1e18) / r1;
        } else {
            poolPrice = type(uint256).max;
        }

        //console.log("Real Market Price (WSTETH/USDC):", realMarketPrice);
        //console.log("Pool's Internal Price (WSTETH/USDC):", poolPrice);
        //console.log("Holder's USDC Debt (token0):", debt0);
        //console.log("Holder's WSTETH Debt (token1):", debt1);

        _executeArbitrage(debt0, debt1, realMarketPrice, poolPrice);

        vm.stopPrank();
        //console.log("--- Dynamic Predatory Arbitrage Bot Finished ---");
    }

    function _executeArbitrage(
        uint256 debt0,
        uint256 debt1,
        uint256 realMarketPrice,
        uint256 poolPrice
    ) private {
        uint256 threshold = (realMarketPrice * 5) / 1000; // 0.5%
        uint256 largeTradeBps = 9000; // 90%
        uint256 smallTradeBps = 1000;   // 10%

        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        if (poolPrice < realMarketPrice && poolPrice + threshold < realMarketPrice) {
            //console.log("Arbitrage opportunity: Buying cheap WSTETH from pool.");
            
            uint256 tradeBps = (debt1 > debt0) ? largeTradeBps : smallTradeBps;
            uint256 amountToSwap = (reserve0 * tradeBps) / 10000;
            if (amountToSwap == 0) amountToSwap = 1;

            //console.log("Decision: Swapping %d USDC.", amountToSwap);
            tokens[0].approve(address(periphery), amountToSwap);
            periphery.swapExactIn(address(eulerSwap), address(tokens[0]), address(tokens[1]), amountToSwap, botAddress, 0, 0);

        } else if (poolPrice > realMarketPrice && poolPrice > realMarketPrice + threshold) {
            //console.log("Arbitrage opportunity: Selling expensive WSTETH to pool.");

            uint256 tradeBps = (debt0 > debt1) ? largeTradeBps : smallTradeBps;
            uint256 amountToSwap = (reserve1 * tradeBps) / 10000;
            if (amountToSwap == 0) amountToSwap = 1;

            //console.log("Decision: Swapping %d WSTETH.", amountToSwap);
            tokens[1].approve(address(periphery), amountToSwap);
            periphery.swapExactIn(address(eulerSwap), address(tokens[1]), address(tokens[0]), amountToSwap, botAddress, 0, 0);
        } else {
            //console.log("No profitable arbitrage opportunity found.");
        }
    }
}
