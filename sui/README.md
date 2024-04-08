# Atoma on Sui

Useful links:

- [Install Sui][sui-install]
- [Sui Move Analyzer][sui-analyzer]
- [Sui standard lib on Github][github-sui-std]

## Dev Environment

There's a [`check` shell script](dev/check) that builds all packages.

As of right now we don't use `localnet` for testing because the Sui CLI support for faucet is broken.

## Useful commands

These commands should get you started once you have the Sui binary installed.

```sh
# check what environment (localnet, devnet, testnet) you're in
sui client active-env
# check what is your active address
sui client active-address
# get some coins into the active address from the faucet
sui client faucet
```

This publishes both `atoma` package and `toma` coin package into a single on-chain package.
We skip dependency verification because testnet and mainnet use different stdlib versions.
Your current directory has to be where this README is located.

```sh
sui client publish \
    --with-unpublished-dependencies \
    --skip-dependency-verification \
    --gas-budget 1000000000 \
    --json \
    packages/atoma
```

Use the CLI tool to add a model to the previously published package.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    gate add-model \
    --package "your package id can be found in publish tx digest" \
    --model-name "llama"
```

And then add an echelon to the model.
See the contract documentation for more information on what these parameters mean.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    gate add-model \
    --package "your package id can be found when publishing" \
    --model-name "llama" \
    --echelon 1 \
    --fee-in-protocol-token 1000 \
    --relative-performance 100
```

## `TOMA` token

The `TOMA` token is used as collateral that nodes must lock up to participate.
It's defined in the [`toma` package](./packages/toma).

<!-- List of References -->

[github-sui-std]: https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources
[sui-install]: https://docs.sui.io/guides/developer/getting-started/sui-install
[sui-analyzer]: https://marketplace.visualstudio.com/items?itemName=MoveBit.sui-move-analyzer
