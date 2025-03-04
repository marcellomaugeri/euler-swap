# Events

## Introduction

The EulerSwap smart contracts emit several key event types to notify off-chain systems (e.g., frontends, analytics tools) of important state changes. These events facilitate transparency, integration with external systems, and effective monitoring of the protocol's behavior.

Events such as EulerSwapCreated and PoolDeployed are particularly useful for solvers and aggregators. These tools can track new pool creations, allowing them to dynamically update their routing algorithms and ensure trades are optimally routed through EulerSwap pools, enhancing liquidity and trading efficiency.

### Summary

| **Event**          | **Contract**       | **Purpose**                                           | **Use Case**                          |
| ------------------ | ------------------ | ----------------------------------------------------- | ------------------------------------- |
| `AddLiquidity`     | `EulerSwap`        | Emitted when liquidity is added to the pool           | Track liquidity inflows               |
| `RemoveLiquidity`  | `EulerSwap`        | Emitted when liquidity is removed from the pool       | Monitor liquidity outflows            |
| `Swap`             | `EulerSwap`        | Emitted during token swaps                            | Trading analytics and UIs             |
| `CollectFees`      | `EulerSwap`        | Emitted when trading fees are collected               | Revenue and protocol fee management   |
| `StatusChanged`    | `EulerSwap`        | Signals a change in the contract's operational status | DApp integration and state management |
| `DebtLimitUpdated` | `EulerSwap`        | Emitted when debt limits for assets are modified      | Risk management and protocol settings |
| `ErrorOccurred`    | `EulerSwap`        | Captures errors and exceptions                        | Debugging and transaction monitoring  |
| `EulerSwapCreated` | `EulerSwapFactory` | Emitted when a new `EulerSwap` instance is created    | Track creation of new liquidity pools |
| `PoolDeployed`     | `EulerSwapFactory` | Indicates when a new liquidity pool is deployed       | Detecting and listing new pools       |

## Details

### Events in `EulerSwap.sol`

#### Liquidity management events

##### `AddLiquidity`

```solidity
event AddLiquidity(address indexed provider, uint256 amount0, uint256 amount1);
```

- **Purpose:** Emitted when liquidity is added to the pool.
- **Parameters:**
  - `provider`: Address adding liquidity.
  - `amount0`, `amount1`: Quantities of `asset0` and `asset1` added.
- **Use Case:** Helps liquidity providers and analytics tools track liquidity inflows.

##### `RemoveLiquidity`

```solidity
event RemoveLiquidity(address indexed provider, uint256 amount0, uint256 amount1);
```

- **Purpose:** Indicates when liquidity is withdrawn from the pool.
- **Parameters:**
  - `provider`: Address removing liquidity.
  - `amount0`, `amount1`: Quantities of `asset0` and `asset1` withdrawn.
- **Use Case:** Updates frontends and liquidity dashboards with outflows.

#### Trading events

##### `Swap`

```solidity
event Swap(address indexed trader, address indexed assetIn, address indexed assetOut, uint256 amountIn, uint256 amountOut);
```

- **Purpose:** Emitted during token swaps.
- **Parameters:**
  - `trader`: Address executing the swap.
  - `assetIn`, `assetOut`: Assets being swapped.
  - `amountIn`, `amountOut`: Amounts involved in the swap.
- **Use Case:** Crucial for trade analytics, swap history, and integration with trading UIs.

#### Fee & accounting events

##### `CollectFees`

```solidity
event CollectFees(address indexed collector, uint256 fees0, uint256 fees1);
```

- **Purpose:** Tracks when trading fees are collected.
- **Parameters:**
  - `collector`: Address receiving the fees.
  - `fees0`, `fees1`: Fees collected in `asset0` and `asset1`.
- **Use Case:** Important for revenue tracking and protocol fee management.

#### Administrative & status events

##### `StatusChanged`

```solidity
event StatusChanged(uint32 oldStatus, uint32 newStatus);
```

- **Purpose:** Signals a change in the contract's operational status.
- **Parameters:**
  - `oldStatus`, `newStatus`: Numerical representation of the contract status (e.g., `0 = unactivated`, `1 = unlocked`, `2 = locked`).
- **Use Case:** Enables dApps to adjust their behavior based on the contract state.

##### `DebtLimitUpdated`

```solidity
event DebtLimitUpdated(uint112 newDebtLimit0, uint112 newDebtLimit1);
```

- **Purpose:** Notifies when the debt limits for the assets are updated.
- **Parameters:**
  - `newDebtLimit0`, `newDebtLimit1`: New debt limits for `asset0` and `asset1`.
- **Use Case:** Supports risk management and off-chain monitoring of protocol settings.

### Events in `EulerSwapFactory.sol`

##### `EulerSwapCreated`

```solidity
event EulerSwapCreated(address indexed asset0, address indexed asset1);
```

- **Purpose:** Emitted when a new `EulerSwap` instance is created.
- **Parameters:**
  - `asset0`, `asset1`: Addresses of the tokens in the newly created trading pair.
- **Use Case:** Useful for tracking the creation of new liquidity pools and integrating with factory-based analytics.

##### `PoolDeployed`

```solidity
event PoolDeployed(address indexed pool, address indexed asset0, address indexed asset1);
```

- **Purpose:** Indicates when a new liquidity pool is deployed by the `EulerSwapFactory`.
- **Parameters:**
  - `pool`: Address of the newly deployed pool.
  - `asset0`, `asset1`: Addresses of the tokens in the pool.
- **Use Case:** Essential for detecting new pool deployments, often used by front-end interfaces to list available pools dynamically.

### Error handling events

##### `ErrorOccurred`

```solidity
event ErrorOccurred(address indexed account, string message);
```

- **Purpose:** Emitted when an error or unexpected condition occurs.
- **Parameters:**
  - `account`: Address involved in the error.
  - `message`: Description of the error.
- **Use Case:** Useful for debugging and alerting systems about failed transactions or invalid operations.
