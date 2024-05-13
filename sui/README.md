# Atoma on Sui

Useful links:

- [Install Sui][sui-install]
- [Sui Move Analyzer][sui-analyzer]
- [Sui standard lib on Github][github-sui-std]

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

## How to use the atoma protocol

To use the atoma protocol, you need to interact with the `gate` module of the `atoma` package.
This module is responsible for submitting prompts.

A ubiquitous parameter is the `AtomaDb` shared object ID.
Along with the actual package ID, these are meant be configured once and you should not need to change them.
It's possible to derive the `AtomaDb` object ID from the package ID by querying the first transaction of the package and looking for the shared object with type name `AtomaDb`.

Before we list all the parameters, here are some general rules:

- floats are stored on chain as `u32` integers.
  The conversion from float to `u32` is done with first converting the float to little endian bytes and then interpreting those bytes as a `u32`: `u32::from_le_bytes(xxx_f32.to_le_bytes())`.
  Conversely, to go from `u32` to float you can use `f32::from_le_bytes(xxx_u32.to_le_bytes())`.

As of now, we support these modalities:

- `submit_text2text_prompt` with params `Text2TextPromptParams`:

  - `max_tokens` of output to be generated.
    This value also determines how much `TOMA` tokens are charged from the user submitting the prompt.
    If the output prompt is generated with fewer tokens, the remaining tokens are refunded to the user when the response is generated.
  - `model` is a string identifier of the model to be used.
    It must be a model that supports text to text generation.
    For a list of models supported by the atoma network, see our website.
  - `prompt` is the input text prompt.
    There's no limit to the prompt length in the contract, but a Sui transaction can be 128KB at most.
  - `random_seed` any random number to seed the random generator.
    Necessary so that all the nodes generate the same output for the same prompt for non zero temperature.
    Before Sui stabilizes random generator, you can use `atoma::utils::random_u64`.
  - `repeat_last_n` tells the model to avoid reusing tokens within the last `n` tokens.
  - `repeat_penalty` is a float number that determines how much the model should avoid repeating tokens.
    The higher the number, the less likely the model is to repeat tokens.
  - `temperature` is a float number that determines how much randomness is added to the output.
    The higher the number, the more random the output.
  - `top_k` is an integer that determines how many tokens are considered for the next token generation.
    The higher the number, the more diverse the output.
  - `top_p` is a float number that determines how many tokens are considered for the next token generation.
    The higher the number, the more diverse the output.

- `submit_text2image_prompt` with params `Text2ImagePromptParams`:
  - `guidance_scale` is a float number that determines how much the guidance image is considered.
    The higher the number, the more the guidance image is considered.
  - `height` of the image.
    Along with `width`, it determines how much is the user charged.
  - `img2img` is an optional string. Which image you should use to start generating with stable diffusion?
  - `img2img_strength` is a float number. How much should the model consider the `img2img` image?
    Will be ignored if `img2img` is not provided.
  - `model` see above.
  - `n_steps` is an integer. How many steps should the model take to generate the image?
  - `num_samples` is an integer. How many samples should the model generate?
  - `prompt` see above.
  - `random_seed` see above.
  - `uncond_prompt` is negative word prompt.
  - `width` of the image.
    Along with `height`, it determines how much is the user charged.

You will also need a wallet with some `TOMA` tokens to pay for the prompt.
The payment differs based on the prompt type.
Each model has a pricing for input and output tokens as two separate parameters.
For text to text models, these two parameters are likely to be the same.

- `Text2TextPromptParams` charges `prompt_len * input_token_price + max_tokens * output_token_price` upon the submission of the prompt.
  Once the prompt is settled, the user will be reimbursed for any unused tokens or overestimate.
- `Text2ImagePromptParams` charges `prompt_len * input_token_price + width * height * output_token_price` upon the submission of the prompt.
  Again, the input tokens are reimbursed upon overestimation.

The aforementioned functions have `max_fee_per_token` parameter.
If there are no nodes that can generate the prompt within the budget, the transaction will fail.
The parameter applies to both input and output token prices.

The last parameter is `nodes_to_sample`.
It's optional and defaults to a sensible value.

See `atoma::prompts` module for sample implementations.
If you are writing your own smart contract that should submit prompts, this module is the perfect place to start.

Since the aforementioned functions are `public` but not `entry`, they must be used in Sui's programmable transactions from the client's POV.

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
