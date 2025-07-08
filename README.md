# Eulibra

![Eulibra Logo](logo.jpg)
**Submission for the EulerSwap Builder Competition.**

Eulibra aims in designing strategies and bots that leverage the unique capabilities of **EulerSwap** to maintain the desired **equilibrium** in the case of uncorrelated (or weekly correlated) pairs such as **WSTETH/USDC**.
The current project demonstrates two different point of views:

1.  **Arbitrage Bot:** A bot that systematically exploits price divergences (slippage) in an EulerSwap to earn profits and, indirectly create pressure on a leveraged Liquidity Provider (LP).
2.  **Delta-LP System:** A framework for an automated rebalancing system that allows LPs to provide liquidity for uncorrelated pairs while mitigating impermanent loss.

This repository contains the proof-of-concept and backtesting environment for the arbitrage bot, showcasing how EulerSwap's mechanics can be used for advanced, targeted financial strategies.

**Important:** the current implementation is a **proof-of-concept** written in Solidity. This is intended to backtest the strategies and the environment (which can be tuned with the config.json file).
Real bots can be implemented in any language and easily interact with the EulerSwap contracts via the provided interfaces and is left as future work.

---

## Motivation: The Uncorrelated Pair Dilemma

Providing liquidity for uncorrelated asset pairs (e.g., WSTETH/USDC) is notoriously challenging due to **impermanent loss**.
When the market price of the assets diverges, LPs suffer a loss compared to simply holding the assets.
This risk discourages liquidity provision for volatile pairs, leading to thinner markets.

EulerSwap's unique architecture, where each pool is controlled by a single LP, turns this challenge into an opportunity.
It allows for sophisticated, targeted strategies that are impossible in traditional pooled AMMs.

### Leveraging Impermanent Loss as an Arbitrage Vector

The same market mechanics that cause impermanent loss for the LP create clear arbitrage opportunities.
When the pool's internal price deviates from the real market price, a profitable trade exists.
The **Predatory Arbitrage Bot** is designed to exploit this.

The bot's logic is simple yet effective:

1.  **Monitor Prices:** It continuously compares the EulerSwap pool's internal price against a reliable real-world market price from an oracle.
2.  **Identify Opportunity:** If the price difference exceeds a predefined threshold (e.g., 0.5%), an arbitrage opportunity is flagged.
    *   If `poolPrice < realMarketPrice`, the asset is cheap in the pool. The bot buys it.
    *   If `poolPrice > realMarketPrice`, the asset is expensive in the pool. The bot sells to it.
3.  **Execute Predatory Trade:** In our scenario, the bot's secondary goal is to amplify the debt of the pool's owner (the `holder`).
    *   It checks which asset the `holder` has more debt in.
    *   It executes a **large trade** (e.g., swapping 50% of the pool's reserves) specifically designed to *increase* the holder's largest debt, thereby worsening their position and health factor.

This creates a powerful feedback loop where the bot profits from re-aligning the pool's price while simultaneously putting the leveraged LP under financial stress.

### Dynamic Hedging via Operator Reinstallation

The EulerSwap's whitepaper highlights a key feature for LPs: mitigating impermanent loss through dynamic hedging.
For an LP, rebalancing a position in a traditional AMM is costly and complex.

EulerSwap simplifies this dramatically.
Since the entire AMM logic is encapsulated within a swappable `operator` contract, an LP can rebalance their entire strategy by simply:

1.  **Uninstalling** the current EulerSwap operator contract from their EVC account.
2.  **Reinstalling** a new operator with an updated AMM curve (e.g., new prices `px`, `py` or concentration `cx`, `cy` parameters).

This atomic, low-cost operation allows an LP to adjust their exposure in response to market movements. A planned feature of Eulibra is to build a system that automates this process on-chain, creating a truly delta-neutral LP strategy for volatile, uncorrelated pairs.

---

## Arbitrage Bot Logic

The predatory arbitrage bot operates on a simple yet effective loop. It's configured with several key parameters that dictate its behavior.

### Inputs & Configuration

*   **`Price Threshold`**: A percentage (e.g., 0.5%). The bot will only act if the difference between the pool price and the real market price exceeds this threshold. This prevents trading on minor, unprofitable fluctuations.
*   **`Large Trade Percentage`**: A large percentage (e.g., 90%). This is the portion of the pool's reserves the bot will swap when it wants to apply maximum pressure on the LP.
*   **`Small Trade Percentage`**: A small percentage (e.g., 1%). This is the portion of the pool's reserves the bot will swap when it is not targeting the LP's primary debt.

### Pseudocode

The bot's core logic can be simplified into the following steps for each round of the simulation:

```
FUNCTION runArbitrageRound:

  // 1. GATHER INTEL
  // Get the real-world price from a trusted oracle.
  realMarketPrice = getOraclePrice(WSTETH/USDC)

  // Get the pool's internal price, calculated directly from its reserves
  poolPrice = calculatePoolPriceFromReserves()

  // Get the LP's current debt position. -> This is for simulating an attack on the LP.
  holderUsdcDebt = getHolderDebt(USDC)
  holderWstethDebt = getHolderDebt(WSTETH)


  // 2. ANALYSE & DECIDE
  // Check if the asset is significantly cheaper in the pool.
  IF poolPrice < (realMarketPrice - Price Threshold):
    
    // DECISION: Buy cheap WSTETH from the pool.
    
    // PREDATORY SIZING: Is the holder's WSTETH debt larger?
    // If so, make a large trade to worsen their position.
    IF holderWstethDebt > holderUsdcDebt:
      tradePercentage = Large Trade Percentage
    ELSE:
      tradePercentage = Small Trade Percentage
      
    // EXECUTE: Swap a percentage of the pool's USDC reserve for WSTETH.
    amountToSwap = pool.usdcReserve * tradePercentage
    executeSwap(USDC, amountToSwap)

  // Check if the asset is significantly more expensive in the pool.
  ELSE IF poolPrice > (realMarketPrice + Price Threshold):

    // DECISION: Sell expensive WSTETH to the pool.

    // PREDATORY SIZING: Is the holder's USDC debt larger?
    // If so, make a large trade to worsen their position.
    IF holderUsdcDebt > holderWstethDebt:
      tradePercentage = Large Trade Percentage
    ELSE:
      tradePercentage = Small Trade Percentage

    // EXECUTE: Swap a percentage of the pool's WSTETH reserve for USDC.
    amountToSwap = pool.wstethReserve * tradePercentage
    executeSwap(WSTETH, amountToSwap)

  ELSE:
    // No profitable opportunity found.
    DO NOTHING

```

## Delta-LP System

Eulibra provides "Delta-LP" rebalancer for market makers.  
Every round it:

1.  Checks the LP's health factor (collateral ÷ liability).  
2.  If health is out of a target band, it boosts the AMM's concentration parameters to attract the more-profitable side of the pool, shifting swaps in your favor.  
3.  If the price ratio drifts from your original curve parameters, it uninstalls the old operator and installs a fresh one with updated prices.

This low-gas "operator swap" lets LPs hedge impermanent loss by rewriting the entire AMM logic atomically.
Note that the effectiveness is not immediate, as it depends on the reaction of the market to the new curve parameters.
However, this could be combined with other solutions which perform hedging also by leveraging a perpetual market, for example like [NoetherBot by Telos Consilium](https://github.com/Telos-Consilium/noether-bot).

---

## Running the Full Simulation

You can backtest both bots and log every round’s CSV metrics:

```bash
forge test --match-path test/poc/TestEulibra.t.sol -vv
```

Note that it takes a while to run. Also, you can disable the calls to the arbitrage bot or the delta LP by commenting the respective calls in the `TestEulibra` contract.

You will see a CSV dump like:
```
round,timestamp,healthFactor,collateralValue,liabilityValue,reserve0,reserve1,marketPrice0,marketPrice1,botHoldings
0,1743465600000,2000000000000000000,218524000000000000000000,109262000000000000000000,10000000000000,10000000000000000000,999989000000000000000000,2185259801013775237120,100000000000000000000
1,1743552000000,1800000000000000000,196000000000000000000000,108889000000000000000000,10010000000000,9990000000000000000000,999950000000000000000000,2285434269922083733504,200000000000000000000
…  
```

You can copy and paste this into the `test/poc/log.csv` file to analyse the results with this Python script:

```bash
python3 plot_metrics.py
```

It will generate three JPEGs under `test/poc/plots/`:

#### LP Health vs. Bot Profit
Blue: LP health factor over time
Green: cumulative bot holdings in USDC
You should see health steadily decay as the bot profits.

#### Pool Reserves vs. Market Price
Orange & purple: on-chain reserve levels
Teal dashed: external market price (wstETH ↔ USDC)
Watch how arbitrage and reinstallation keep the pool near equilibrium.

#### Impermanent Loss Over Time
Red: difference between a HODL portfolio and actual LP P&L
Ideally your Delta-LP rebalancer flattens this line.


### Run the simulations with other data
The code is undergoing a refactor to allow for more flexible simulations.
In general, you can run the simulations with different data by changing the `config.json` file.
But there could be hardcoded values in the code that need to be changed as well, this will be fixed soon, as the code is being refactored to be more modular and flexible.

The backtesting environment is designed in rounds, where each round contains the prices for the assets.
These can be created from real-world data extracted from CoinGecko and there is a script to fill the rounds from two JSON files from CoinGecko.

You can call `python3 fill_rounds.py` to populate the rounds. Note that there are two hardcoded json files that you can change to use different data. This will be refactored in the future to allow for more flexible data input.

## Code Structure

This folder contains the proof-of-concept simulation for both the Predatory Arbitrage Bot and the Delta-LP rebalancer.

```plaintext
test/poc/
├── [ArbitrageBot.sol]
│   Monitors pool vs. market prices, executes “pressure” trades to worsen the LP’s position.
│
├── DeltaLP.sol
│   Checks LP health factor each round and, if needed, updates the AMM operator (price/concentration) to hedge impermanent loss.
│
├── EulerSwapUtils.t.sol
│   Shared test utilities and helpers.  
│   - JSON config parsing (assets / rounds)  
│   - Vault & pool deployment (createEulerSwap*)  
│   - Price updates, logging, health-factor helper
│
├── TestEulibra.t.sol
│   Main Foundry integration test.  
│   - Initialises both bots  
│   - Iterates over rounds from config.json  
│   - Logs CSV metrics (health, reserves, bot holdings)  
│
├── config.json
│   Simulation parameters:  
│     • "assets"  → name, symbol, decimals, initialPrice
│     • "eulerSwap" → initial pool reserves & curve params  
│     • "rounds" → timestamp + raw prices for each test step
│
├── wsteth-to-usd-*.json
│   Historical WSTETH/USD price feed (Coingecko format).
│
├── usdc-to-usd-*.json
│   Historical USDC/USD price feed (Coingecko format).
│
├── log_no_delta.csv
│   Example CSV output from TestEulibra.t.sol with Delta-LP disabled.
│
├── plots_no_delta/
│   Pre-generated JPEGs from `log_no_delta.csv`:  
│
└── plots_with_delta/
    Placeholder for plots when Delta-LP is enabled.
  

### IMPORTANT
This repository is a fork of [EulerSwap](https://github.com/euler-xyz/euler-swap). You can find the original readme in the [README_original.md](README_original.md) file.