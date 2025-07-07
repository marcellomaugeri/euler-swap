# Eulibra

![Eulibra Logo](logo.jpg)
**Submission for the EulerSwap Builder Competition.**

Eulibra aims in designing strategies and bots that leverage the unique capabilities of **EulerSwap** to maintain the desired **equilibrium** in the case of uncorrelated (or weekly correlated) pairs such as **WSTETH/USDC**.
The current project demonstrates two different point of views:

1.  **Arbitrage Bot:** A bot that systematically exploits price divergences (slippage) in an EulerSwap to earn profits and, indirectly create pressure on a leveraged Liquidity Provider (LP).
2.  **Delta-LP System:** A framework for an automated rebalancing system that allows LPs to provide liquidity for uncorrelated pairs while mitigating impermanent loss.

This repository contains the proof-of-concept and testing environment for the arbitrage bot, showcasing how EulerSwap's mechanics can be used for advanced, targeted financial strategies.

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

## Code Structure

*(Placeholder)*

This section will detail the structure of the contracts and testing environment.

-   `/src`: Core contracts for the EulerSwap pool and operator logic.
-   `/test`: Foundry test suites, including the proof-of-concept for the arbitrage bot.
-   `/scripts`: Deployment and interaction scripts.
-   `/docs`: Project documentation and the EulerSwap whitepaper
  

### IMPORTANT
This repository is a fork of [EulerSwap](https://github.com/euler-xyz/euler-swap). You can find the original readme in the [README_original.md](README_original.md) file.