# Atoma on Sui

Useful links:

- [Install Sui][sui-install]
- [Sui Move Analyzer][sui-analyzer]
- [Sui standard lib on Github][github-sui-std]

The packages and CLI is pointed to the currently released Sui _mainnet_ version tag.

Upgrade your CLI to the appropriate mainnet version that matches the [`Move.toml`](packages/atoma/Move.toml):

```sh
cargo install --locked --git https://github.com/MystenLabs/sui.git --tag mainnet-vX.Y.Z sui
```

When upgrading, the version needs to be changed in

- [`atoma` package](packages/atoma/Move.toml)
- [`toma` package](packages/toma/Move.toml)
- [`cli` binary](cli/Cargo.toml)

## Events

- `db::NodeRegisteredEvent` is emitted when a new node puts up collateral to register.
- `db::NodeSubscribedToModelEvent` is emitted when a node subscribes to a model echelon and is ready to receive prompts.
- `gate::Text2TextPromptEvent` is emitted when a user submits a text to text prompt.
- `gate::Text2ImagePromptEvent` is emitted when a user submits a text to image prompt.
- `settlement::FirstSubmissionEvent` is emitted when a node submits the _first_ response to a prompt.
- `settlement::DisputeEvent` is emitted when a node disputes a submission.
  Now, we want for an oracle to resolve the dispute.
- `settlement::SettledEvent` is emitted when a ticket is settled and fee is distributed.
- `settlement::NewlySampledNodesEvent` is emitted when a new set of nodes is sampled for a prompt because of timeout.
- `settlement::RetrySettlementEvent` is emitted when settlement cannot progress because there are not enough nodes in the ticket's selected echelon.
  It has a property that tells the off chain clients how many nodes are required before retry.

## How to use the atoma protocol

To interact with the Atoma protocol, utilize the `gate` module within the `atoma` package, responsible for prompt submission.

A crucial parameter is the shared object ID for `AtomaDb`.
These, along with the package ID, should be configured once and remain unchanged.
The `AtomaDb` object ID can be derived from the package ID by querying the first transaction of the package and locating the shared object with the type name `AtomaDb` _if necessary_.

Before we list all the parameters, here are some general rules:

- Floats are stored on-chain as `u32` integers.
  To convert from float to `u32`, convert the float to little-endian bytes and then interpret those bytes as a little-endian `u32`: `u32::from_le_bytes(xxx_f32.to_le_bytes())`
  Conversely, to convert from `u32` to float, use the reverse process.

As of now, the supported modalities are:

- `submit_text2text_prompt` with params `Text2TextPromptParams`:

  - `max_tokens`: determines the maximum output to be generated and also the amount of `TOMA` tokens charged.
    Unused tokens are refunded upon response generation.
    We discuss pricing below.
  - `model`: a string identifier of the model for text-to-text generation.
    Refer to our website for supported models.
  - `prompt`: input text prompt.
    There's no limit to the prompt length at the protocol level, but a Sui transaction can be at most 128KB.
  - `random_seed`: any random number to seed the random generator for consistent output across nodes.
    Before Sui stabilizes random generator, you can use `atoma::utils::random_u64`.
  - `repeat_last_n`: instructs the model to avoid reusing tokens within the last `n` tokens.
  - `repeat_penalty`: a float number determining token repetition avoidance.
  - `temperature`: a float number determining randomness in the output.
  - `top_k`: an integer determining token consideration for the next generation.
  - `top_p`: a float number determining token consideration for the next generation.

- `submit_text2image_prompt` with params `Text2ImagePromptParams`:

  - `guidance_scale`: a float number determining the consideration of the guidance image.
  - `height`: height of the image.
    See pricing below.
  - `img2img`: an optional string indicating the image to start generating with stable diffusion.
  - `img2img_strength`: a float number indicating the consideration of the `img2img` image.
  - `model`: same as above.
  - `n_steps`: an integer indicating how many steps the model should take to generate the image.
  - `num_samples`: an integer indicating how many samples the model should generate.
  - `prompt`: same as above.
  - `random_seed`: same as above.
  - `uncond_prompt`: negative word prompt.
  - `width`: width of the image.

A wallet with `TOMA` tokens is required for prompt payment, with charges varying based on prompt type.
Pricing for input and output tokens differs for each model.
Each model has a pricing for input and output tokens as two separate parameters.
For text to text models, these two parameters are likely to be the same.

The parameter `nodes_to_sample` is optional and defaults to a sensible value.
Higher number of nodes means higher confidence in the generated output.
However, the price is also higher as nodes multiply the prompt price.

- `Text2TextPromptParams` charges `nodes_to_sample * (prompt_len * input_token_price + max_tokens * output_token_price)` upon prompt submission.
- `Text2ImagePromptParams` charges `nodes_to_sample * (prompt_len * input_token_price + num_samples * output_token_price)` upon submission.

Unused tokens are reimbursed upon response generation by sending a `Coin<TOMA>` object to the prompt submitter.

`submit_text2text_prompt` function has a `max_fee_per_token` parameter.
This applies to both input and output token prices.
If no nodes can generate the prompt within the budget, the transaction fails.

`submit_text2image_prompt` has a `max_fee_per_input_token` and `max_fee_per_output_token` parameters.
These apply to input and output token prices, respectively.

The last parameter is `nodes_to_sample`.
It's optional and defaults to a sensible value.
Higher number of nodes means higher confidence in the generated output.
However, the price is also higher as nodes multiply the prompt price.

Refer to the `atoma::prompts` module for sample implementations.
If you are developing a custom smart contract for prompt submission, this module is a great starting point.

Since these functions are `public` but not `entry`, they must be used in Sui's programmable transactions from the client's perspective.

## Dev Environment

There's a [`check` shell script](dev/check) that builds all packages.

As of right now we don't use `localnet` for testing because the Sui CLI support for faucet is broken.

## CLI

### Env

The CLI loads values from environment variables.
You can set these in your shell or in a `.env` file in the root of the repository.

If any value is not provided, the CLI does best effort to figure it out from the context.
For example, if you provide package ID but not atoma DB object ID, the CLI will query Sui to find it.

```text
WALLET_PATH=
PACKAGE_ID=
ATOMA_DB_ID=
MANAGER_BADGE_ID=
NODE_BADGE_ID=
NODE_ID=
TOMA_WALLET_ID=
GAS_BUDGET=
```

You can also generate these values by running the following command:

```sh
./cli db print-env --package "YOUR PACKAGE ID"
```

### Examples

These commands should get you started once you have the Sui binary installed.

```sh
# check what environment (localnet, devnet, testnet) you're in
sui client active-env
# check what is your active address
sui client active-address
# get some coins into the active address from the faucet
sui client faucet
```

Following series of commands can be replicated all in one go with [`oneclicksetup`](./dev/oneclicksetup) script.

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
./cli db add-model \
    --package "your package id can be found in publish tx digest" \
    --name "llama"
```

And then add an echelon to the model.
See the contract documentation for more information on what these parameters mean.

```sh
./cli db add-model-echelon \
    --package "your package id can be found when publishing" \
    --model "llama" \
    --echelon 1 \
    --input-fee-per-token 1000 \
    --relative-performance 100
```

We can change the required collateral for node registration.

```sh
./cli db set-required-registration-toma-collateral \
    --package "your package id can be found when publishing" \
    --new-amount 1
```

Now let's mint some [`TOMA`](#toma-token) tokens and register a new node for the model we created above.

```sh
./cli db register-node \
    --package "your package id can be found when publishing"
```

And let's use the echelon we created above.

```sh
./cli db add-node-to-model \
    --package "your package id can be found when publishing" \
    --model "llama" \
    --echelon 1
```

Now that the network has a model, echelon and a node, we can send a test prompt:

```sh
./cli gate submit-tell-me-a-joke-prompt \
    --package "your package id can be found when publishing" \
    --model "llama"
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
    --args YOUR_TOMA_MINT_CAP 1000000 $(sui client active-address) \
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
