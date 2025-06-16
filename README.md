# EulerSwap

EulerSwap is an automated market maker (AMM) that integrates with Euler [credit vaults](https://docs.euler.finance/euler-vault-kit-white-paper/) to provide deeper liquidity for swaps. When a user initiates a swap, a smart contract called an EulerSwap operator borrows the required output token using the input token as collateral. This model enables up to 40x the liquidity depth of traditional AMMs by making idle assets in Euler more efficient. Unlike traditional AMMs, which often fragment liquidity across multiple pools, EulerSwap further increases capital efficiency by allowing a single, cross-collateralised credit vault to support multiple asset pairs at once. At its core, EulerSwap uses a flexible AMM curve to optimise swap pricing, ensuring deep liquidity while maintaining market balance. By combining just-in-time liquidity, shared liquidity across pools, and customisable AMM mechanics, EulerSwap reduces inefficiencies in liquidity provision, offering deeper markets, lower costs, and greater control for liquidity providers.

For more information, refer to the [white paper](./docs/whitepaper/EulerSwap_White_Paper.pdf).

## Usage

EulerSwap comes with a comprehensive set of tests written in Solidity, which can be executed using Foundry.

To install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

To clone the repo:

```sh
git clone https://github.com/euler-xyz/euler-swap.git && cd euler-swap
```

## Testing

### in `default` mode

To run the tests in a `default` mode:

```sh
forge test
```

### in `coverage` mode

```sh
forge coverage
```

## Smart Contracts Documentation

```sh
forge doc --serve --port 4000
```

## Deployments

### Mainnet

Uniswap4 Hook Compatible:

- EulerSwapFactory: `0xb013be1D0D380C13B58e889f412895970A2Cf228`
- EulerSwapPeriphery: `0x208fF5Eb543814789321DaA1B5Eb551881D16b06`

### Unichain

Uniswap4 Hook Compatible:

- EulerSwapFactory: `0x45b146BC07c9985589B52df651310e75C6BE066A`
- EulerSwapPeriphery: `0xdAAF468d84DD8945521Ea40297ce6c5EEfc7003a`

## Getting Started

The `script` folder contains scripts for deploying pools, as well as executing test trades on them. See the dedicated [README](./script/README.md)

## Safety

This software is experimental and is provided "as is" and "as available".

No warranties are provided and no liability will be accepted for any loss incurred through the use of this codebase.

Always include thorough tests when using EulerSwap to ensure it interacts correctly with your code.

## Known limitations

Refer to the [white paper](./docs/whitepaper/EulerSwap_White_Paper.pdf) for a list of known limitations and security considerations.

## Contributing

The code is currently in an experimental phase. Feedback or ideas for improving EulerSwap are appreciated. Contributions are welcome from anyone interested in conducting security research, writing more tests including formal verification, improving readability and documentation, optimizing, simplifying, or developing integrations.

## License

(c) 2024-2025 Euler Labs Ltd.

All rights reserved.
