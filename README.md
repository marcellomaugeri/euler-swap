# EulerSwap

EulerSwap is an Automated Market Maker (AMM) that uses [Euler lending vaults](https://docs.euler.finance/euler-vault-kit-white-paper/) as leveraged lending products in order to extend the range of its reserves and thereby improve the capital efficiency of liquidity provisioning.

To swappers, EulerSwap presents a hopefully familiar Uniswap2-style interface but internally it supports borrow and repaying, custom pricing curves, and other advanced functionality. Although useable by anyone, it is primarily intended to be invoked by sophisticated actors such as swap aggregators, intents solvers, and MEV bots. Similar to Uniswap, there is a careful separation between the critical core functionality for servicing swaps and the surrounding periphery functions for quoting, etc.

For more information, refer to the [white paper](./docs/white-paper/EulerSwap_White_Paper.pdf).

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

## Safety

This software is experimental and is provided "as is" and "as available".

No warranties are provided and no liability will be accepted for any loss incurred through the use of this codebase.

Always include thorough tests when using EulerSwap to ensure it interacts correctly with your code.

## Known limitations

Refer to the [white paper](./docs/white-paper/EulerSwap_White_Paper.pdf) for a list of known limitations and security considerations.

## Contributing

The code is currently in an experimental phase. Feedback or ideas for improving EulerSwap are appreciated. Contributions are welcome from anyone interested in conducting security research, writing more tests including formal verification, improving readability and documentation, optimizing, simplifying, or developing integrations.

## License

(c) 2024-2025 Euler Labs Ltd.

All rights reserved.
