# Architecture

## Operation

Since the level of acceptable borrowing risk may not be the same for every user, pooled deposits are not yet possible, and each EulerSwap instance manages funds for a single user (who of course may operate on behalf of pooled funds).

EulerSwap is a contract designed to be used as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators). This means that the user, known as the _holder_, does not give up control over their funds to a smart contract, but instead retains it in their wallet. The holder can be any compatible address, including standard multisig wallets or even an EOA.

### Usage

The following are the high-level steps required to use EulerSwap:

- Deposit funds into one or both of the vaults
- Deploy the desired EulerSwap contract, choosing parameters such as the vaults and the desired `fee`
- Calculate the desired [virtual reserves](#virtual-reserves) and set these values by invoking `setVirtualReserves()`
- Install the EulerSwap contract as an operator for your account
- Invoke the `configure()` function on the EulerSwap contract

At this point, anyone can invoke `swap()` on the EulerSwap contract, and this will perform borrowing and transferring activity between the two vaults.

### Debt Limits

The initial deposits in the vaults represent the initial investment, and are swapped back and forth in response to swapping activity. In a conventional AMM such as Uniswap, these balance are called _reserves_. However, if swapping was constrained to these assets alone, then this would imply a hard limit on the size of swaps that can be serviced. To increase the effective funds, EulerSwap AMMs are configured with _virtual reserves_. These are typically larger than the size of the conventional reserves, which signifies that not only can all the assets be swapped from one vault to another, but even more assets can be borrowed on the EulerSwap's account.

Virtual reserves control the maximum debt that the EulerSwap contract will attempt to acquire on each of its two vaults. Each vault can be configured independently.

For example, if the initial investment has a NAV of $1000, and virtual reserves are configured at $5000 for each vault, then the maximum LTV loan that the AMM will support will be `5000/6000 = 0.8333`. In order to leave a safety buffer, it is recommended to select a maximum LTV that is below the borrowing LTV of the vault.

Note that it depends on the [curve](#curves) if the maximum LTV can actually be achieved. A constant product will only approach these reserve levels asymptotically, since each unit will get more and more expensive. However, with constant sum, this LTV can be achieved directly.

### Desynchronised Reserves

The EulerSwap contract tracks what it believes the reserves to be by caching their values in storage. These reserves are updated on each swap. However, since the balance is not actually held by the EulerSwap contract (it is simply an operator), the actual underlying balances may get out of sync. This can happen gradually as interest is accrued, or suddenly if the holder moves funds or the position is liquidated.

When this occurs, the `syncVirtualReserves()` should be invoked. This determines the actual balances (and debts) of the holder, and adjusts them by the configured virtual reserve levels.
