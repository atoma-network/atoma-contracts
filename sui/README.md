# Atoma on Sui

Useful links:

- [Install Sui][sui-install]
- [Sui Move Analyzer][sui-analyzer]
- [Sui standard lib on Github][github-sui-std]

## Dev Environment

There's a [`check` shell script](dev/check) that builds all packages.

As of right now we don't use `localnet` for testing because the Sui CLI support for faucet is broken.

## Useful commands

This would publishes both `atoma` package and `toma` coin package into a single on-chain package.
We skip dependency verification because testnet and mainnet use different stdlib versions.

```sh
sui client publish \
    --with-unpublished-dependencies \
    --skip-dependency-verification \
    --gas-budget 1000000000 \
    --json \
    packages/atoma
```

## `TOMA` token

The `TOMA` token is used as collateral that nodes must lock up to participate.
It's defined in the [`toma` package](./packages/toma).

<!-- List of References -->

[github-sui-std]: https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources
[sui-install]: https://docs.sui.io/guides/developer/getting-started/sui-install
[sui-analyzer]: https://marketplace.visualstudio.com/items?itemName=MoveBit.sui-move-analyzer
