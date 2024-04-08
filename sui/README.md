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
    db add-model \
    --package "your package id can be found in publish tx digest" \
    --model-name "llama"
```

And then add an echelon to the model.
See the contract documentation for more information on what these parameters mean.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    db add-model \
    --package "your package id can be found when publishing" \
    --model-name "llama" \
    --echelon 1 \
    --fee-in-protocol-token 1000 \
    --relative-performance 100
```

We can change the required collateral for node registration.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    db set-required-registration-toma-collateral \
    --package "your package id can be found when publishing" \
    --new-amount 1
```

Now let's mint some [`TOMA`](#toma-token) tokens and register a new node for the model we created above.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    db register-node \
    --package "your package id can be found when publishing"
```

And let's use the echelon we created above.

```sh
./cli --wallet ~/.sui/sui_config/client.yaml \
    db add-node-to-model \
    --package "0xa9db77975df5c11949463eaa8bdfaab5e1f4ba6d26d95751a150511cf81658eb" \
    --model-name "llama" \
    --echelon 2
```

## `TOMA` token

The `TOMA` token is used as collateral that nodes must lock up to participate.
It's defined in the [`toma` package](./packages/toma).

We can use the CLI to mint `TOMA` tokens to an address.
As the package publisher, you can see your `$ sui client active-address` on [Sui Explorer][sui-explorer].
Find the ID of an object called `TreasuryCap<TOMA>`.
That's your mint cap.
Then, get the package ID in which the `TOMA` token is published.
Use the following template to mint yourself some `TOMA` tokens.

```sh
sui client call \
    --package "0x2" --module "coin" --function "mint_and_transfer" \
    --gas-budget 10000000 \
    --args YOUR_TOMA_MINT_CAP 1000000 RECIPIENT_ADDR \
    --type-args YOUR_TOMA_PACKAGE_ID::toma::TOMA
```

Check that your balance has the tokens.

```sh
sui client balance
```

<!-- List of References -->

[github-sui-std]: https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources
[sui-install]: https://docs.sui.io/guides/developer/getting-started/sui-install
[sui-analyzer]: https://marketplace.visualstudio.com/items?itemName=MoveBit.sui-move-analyzer
[sui-explorer]: https://explorer.sui.io
