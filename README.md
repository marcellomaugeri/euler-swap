# Euler Maglev

![maglev logo](docs/maglev.png)

Maglev is an Automated Market Maker (AMM) that uses [Euler Vaults](https://docs.euler.finance/euler-vault-kit-white-paper/) as leveraged lending products in order to extend the range of its reserves and thereby improve the capital efficiency of liquidity provisioning.

To swappers, it presents a conventional Uniswap2-style interface but internally it supports custom pricing curves and other advanced functionality.

## Concept

Given a fixed size investment, Maglev aims to increase the size of trades that can be serviced, relative to a conventional AMM such as Uniswap. It does this by borrowing the "out token" and collateralising this loan with the received "in token". Later on, when somebody wishes to swap in the reverse direction, the loan can be repaid in exchange for receiving the collateral, unwinding the borrow position.

Because the total size of the position can be many times larger than your initial investment (depending on how much LTV/leverage is allowed on the underlying lending pools), the swapping fees earned can be magnified.

The down-side is that while the AMM holds this leveraged position, it is paying interest on the loan. Fortunately, this is partially compensated by the fact that the AMM is earning interest on the collateral.

## Operation

Since the level of acceptable borrowing risk may not be the same for every user, pooled deposits are not yet possible, and each Maglev instance manages funds for a single user (who of course may be a common enterprise).

Maglev is contract designed to be used as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators)

## License

(c) 2024 Euler Labs Ltd.

All rights reserved.
