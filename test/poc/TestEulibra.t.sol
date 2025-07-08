// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapUtils.t.sol";
import {QuoteLib} from "../../src/libraries/QuoteLib.sol";
import "forge-std/console.sol";
import {ArbitrageBot} from "./ArbitrageBot.sol";
import {DeltaLP} from "./DeltaLP.sol";

struct Swap {
    uint256 timestamp;
    uint256 token;
    uint256 amountIn;
}

struct Round {
    uint256 timestamp;
    uint256 price0;
    uint256 price1;
}

contract EulibraTest is EulerSwapTestBase {
    //EulerSwap public override eulerSwap;
    address bot = makeAddr("dynamicPredatoryBot");

    function setUp() public virtual override {
        super.setUp();

        // Provide initial liquidity to the arbitrage bot
        tokens[0].mint(bot, 1_000_000e6);
        tokens[1].mint(bot, 10_000e18);
    }

    function calculateCumulativeBotHoldings() internal view returns (uint256) {
        // Calculate the cumulative holdings of the bot in terms of USDC
        uint256 usdcBalance = tokens[0].balanceOf(bot);
        uint256 wstethBalance = tokens[1].balanceOf(bot);
        
        // Get the current price of WSTETH in terms of USDC
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        // FIX: Reorder calculation to prevent overflow.
        // Calculate the price of token1 (18 decimals) in terms of token0 (6 decimals), then scale to 18 decimals.
        uint256 wstethPriceInUsdc = (uint256(reserve0) * 1e18 / reserve1) * 1e12;

        return usdcBalance + (wstethBalance * wstethPriceInUsdc) / 1e18;
    }

    /// @notice Logs key metrics for a single round in CSV format.
    function logRoundMetricsCSV(
        uint256 roundNum,
        uint256 timestamp,
        uint256 marketPrice0,
        uint256 marketPrice1
    ) internal {
        // 1. Get Holder's liquidity info
        (uint256 collateralValue, uint256 liabilityValue) = vaults[0].accountLiquidity(holder, true);
        uint256 healthFactor = 0;
        if (liabilityValue > 0) {
            healthFactor = (collateralValue * 1e18) / liabilityValue;
        }

        // 2. Get pool reserves
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        // 3. Get bot's total holdings value
        uint256 botHoldings = calculateCumulativeBotHoldings();

        // 4. Log as a single CSV line
        // Print CSV header for clarity (optional, remove if not needed)
        // console.logString("roundNum,timestamp,healthFactor,collateralValue,liabilityValue,reserve0,reserve1,marketPrice0,marketPrice1,botHoldings");
        string memory csvLine = string(
            abi.encodePacked(
                vm.toString(roundNum), ",",
                vm.toString(timestamp), ",",
                vm.toString(healthFactor), ",",
                vm.toString(collateralValue), ",",
                vm.toString(liabilityValue), ",",
                vm.toString(reserve0), ",",
                vm.toString(reserve1), ",",
                vm.toString(marketPrice0), ",",
                vm.toString(marketPrice1), ",",
                vm.toString(botHoldings)
            )
        );
        console.logString(csvLine);
        
    }

    function test_Eulibra() public monotonicHolderNAV {

        // Perform a quote for an exact input amount
        /*{
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(tokens[1]), address(tokens[0]), 1e2);
            console.log("Quote for exact input amount:", amountOut);
            // expect a SwapLimitExceeded error
            //assertEq(amountOut, 0);
        }*/

        {
            logState(address(eulerSwap));
        }

        /*{
            // Let's create a debt here to simulate a real-world scenario
            uint256 amountIn = 1e18; // 1 WSTETH
            address tokenIn = address(tokens[1]);
            address tokenOut = address(tokens[0]);

            vm.startPrank(depositor);
            tokens[1].mint(address(depositor), 2e18);
            tokens[1].approve(address(periphery), amountIn);

            periphery.swapExactIn(
                address(eulerSwap),
                tokenIn,
                tokenOut,
                amountIn,
                address(depositor),
                0,
                0
            );
            vm.stopPrank();

            logState(address(eulerSwap));
        }*/
        {
            // Read the json file to extract rounds
            string memory configJson = vm.readFile("test/poc/config.json");

            // 1. Define the struct layout for the parser. This must exactly match the structs
            //    defined in EulerSwapUtils.t.sol and the JSON structure.
            string memory typeDescription = "Round(uint256 timestamp,uint256 price0,uint256 price1)";
            
            // 2. Parse the JSON array into ABI-encoded bytes, mirroring the asset parsing logic.
            bytes memory roundsBytes = vm.parseJsonTypeArray(configJson, ".rounds", typeDescription);

            // 3. Decode the bytes into a usable struct array.
            Round[] memory rounds = abi.decode(roundsBytes, (Round[]));

            // 3. You can now loop through the rounds and use the data
            console.log("Successfully parsed %d rounds.", rounds.length);

            ArbitrageBot arbBot = new ArbitrageBot(bot, periphery, tokens, vaults, eulerSwap, holder);

            uint256 targetHealthFactor = 1.5e18; // Set the target health factor for the bot
            uint256 healthFactorDelta = 0.1e18; // Allow a delta of 10% in the health factor
            uint256 priceRatioDelta = 10; // Allow a delta of 30% in the price ratio

            // 4. Define the DeltaLP
            DeltaLP deltaLP = new DeltaLP(
                holder,
                eulerSwap,
                vaults,
                targetHealthFactor,
                healthFactorDelta,
                priceRatioDelta,
                address(this) // Pass the utils contract for logging
            );

            // Provide some liquidity to the bot
            tokens[0].mint(bot, 1_000_000e6); //
            tokens[1].mint(bot, 1000e18); //

            // CSV Header
            console.log("round,timestamp,healthFactor,collateralValue,liabilityValue,reserve0,reserve1,marketPrice0,marketPrice1,botHoldings");


            // For each round, set the price in the oracle
            for (uint256 i = 0; i < rounds.length; i++) {
                Round memory round = rounds[i];

                // FIX: Scale the 6-decimal USDC price to the 18-decimal format required by the oracle.
                uint256 scaledPrice0 = round.price0 * 1e12;

                // Set the price in the oracle
                updatePrice(0 , scaledPrice0);
                updatePrice(1, round.price1);

                // Warp time to the current round's timestamp
                vm.warp(round.timestamp / 1000);

                // Call the DeltaLP bot with the current round prices
                deltaLP.rebalance(scaledPrice0, round.price1); // COMMENT THIS LINE TO DISABLE DELTA-LP 

                // Update the arbBot with the current EulerSwap pool
                arbBot.updatePool(eulerSwap); // COMMENT THIS LINE TO DISABLE ARBITRAGE BOT

                // Call to the arbitrage bot with the current round prices
                arbBot.run(scaledPrice0, round.price1);

                // Log the round metrics
                logRoundMetricsCSV(i, round.timestamp, scaledPrice0, round.price1);

            }
            // Log state at the end and check final holdings
            console.log("Final Cumulative Bot Holdings:", calculateCumulativeBotHoldings());
            logState(address(eulerSwap));
        }
    }
}
