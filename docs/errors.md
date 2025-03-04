# Errors

## Introduction

The EulerSwap smart contracts throw errors that can help developers debug why EulerSwap instances are failing to provide quotes, satisfy swaps, rebalance, and more. In some cases these errors emerge directly from the EulerSwap smart contracts themselves, while errors can also come from lower level dependencies, such as the Euler Vault Kit (EVK) and Ethereum Vault Connector (EVC). Each error is listed here with its name and a description of when and why it might occur.

## Summary

### E_AccountLiquidity

**Description:** This error is thrown when the liquidity provider account on Euler does not have sufficient liquidity to perform a particular action, such as borrowing or swapping assets. It typically indicates that the collateral value is not enough to cover the desired transaction within the EVK module.

### E_AmountTooLargeToEncode

**Description:** TODO.

### E_BadAddress

**Description:** This error is triggered when an invalid or null address is provided as an input. It is commonly associated with interactions where a recipient, sender, or contract address must be validated before proceeding with a transaction.

### E_BadAssetReceiver

**Description:** Thrown when an asset is directed to an unintended or incompatible receiver contract. This error often prevents token transfers to addresses that do not implement necessary interfaces or are not approved within the EVK and EVC architecture.

### E_BadBorrowCap

**Description:** This error indicates that the specified borrowing cap for an asset is invalid, either being too high or too low according to protocol parameters. It helps maintain stability by enforcing borrowing limits in the EVK.

### E_BadCollateral

**Description:** Raised when an invalid asset is proposed as collateral in a transaction. The EVK system uses this error to ensure only approved and properly configured assets are used to back borrowing positions.

### E_BadFee

**Description:** This error is related to fee calculations within the EulerSwap or associated periphery contracts. It ensures that any fee applied during swaps or vault interactions is within the acceptable bounds set by governance or protocol parameters.

### E_BadMaxLiquidationDiscount

**Description:** Thrown when an invalid maximum liquidation discount is set. Liquidation discounts are critical for maintaining incentives for liquidators while protecting the protocol from excessive losses during liquidation events.

### E_BadSharesOwner

**Description:** This error indicates that the shares of a vault or liquidity pool are owned by an unexpected or unauthorised entity. It ensures that share ownership is consistent with the expected state of the EVK or EVC modules.

## Further reading

For more information, refer to the EulerSwap [White Paper](docs/whitepaper/EulerSwap_White_Paper.pdf) and the smart contract source code.
