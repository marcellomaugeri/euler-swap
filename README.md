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

- EulerSwapFactory: `0xFb9FE66472917F0F8966506A3bf831Ac0c10caD4`
- EulerSwapPeriphery: `0x52b26d9046BEc495914FaE467Ff0e95762C5ed74`
- EulerSwap Impl: `0xF5d35536482f62c9031b4d6bD34724671BCE33d1`

Only OG interface:

- EulerSwapFactory: `0x806AF31A325bE46812Fc8E8391333c4fA74B1211`
- EulerSwapPeriphery: `0xbAA3acceE85a34cAB03a587cD9b3A3728EC89E3A`
- EulerSwap Impl: `0x05D6C4D46A794468f282469c0E9346f121EA92Ee`

### Unichain

Uniswap4 Hook Compatible:

- EulerSwapFactory: `0xeDA1c70208F2745A4e0720eB48AE7C016d6BC799`
- EulerSwapPeriphery: `0x6FD365537bd39e8a3F492045f76E81120f3CD1E6`
- EulerSwap Impl: `0x33f799F1a46032712D10f511191E27C20c5F4cB8`

Only OG interface:

- EulerSwapFactory: `0x55e5eAe7Ea2a1f84F9536F49d8B5b9796cCC1BC6`
- EulerSwapPeriphery: `0xBf35dd297691d6F6438f7f6f82C020A499018723`
- EulerSwap Impl: `0x4A71aB6Cd0256114c0E139CAe5518CA5B3c3696d`


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
