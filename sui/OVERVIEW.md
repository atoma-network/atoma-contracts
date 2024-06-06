# Atoma on Sui

## What is Atoma

TODO: Jorge

## How we design Atoma

TODO: Jorge

## Smart contract logic overview

There are three key modules in the Atoma smart contract:

- `atoma::db` which holds the state of the network.
  In this module you will find endpoints that let you manage your node's participation in the network.
- `atoma::gate` is relevant for users who submit prompts.
- `atoma:settlement` has endpoints that nodes use to submit their commitments in order to receive their fees.

## Sampling consensus mechanism

TODO

## How to submit prompts to Atoma

TODO

## Parameters explanation

TODO

## Time to settlement

How much time does the node have to submit its commitment is dictated by a model parameter `settlement_timeout_ms`.
If the node does not respond within this allotted time, it is slashed by some percentage value and new node is selected to replace it.

## Pricing

All pricing is calculated in `TOMA` tokens.

Pricing is configured per model's echelon (HW group).
It varies based on the prompt modality and based on how many nodes were selected to respond to the prompt.

For _text to text_ prompts, the input and output tokens are the text tokens fed to or emitted by the model, respectively.
However, for _text to image_ prompts, while the input tokens are text tokens fed to the model, the output tokens actually refer to the number of images generated.
Therefore, the price per _output_ token on text to image models is going to be much higher than the price per _input_ token, just because one output token is one image.

When the prompt is submitted the smart contract overestimates number of tokens that will be used.
When the nodes submit settlement, they provide the real number of tokens used.
The prompt payer is then reimbursed the difference between the overestimated and real number of tokens used.

To be more concrete:

```
P_{txt2txt} = (input_tokens * input_token_fee + output_tokens * output_token_fee) * number_of_sampled_nodes

P_{txt2img} = (input_tokens * input_token_fee + num_samples * output_token_fee) * number_of_sampled_nodes
```

However, the above is only valid if the number of sampled nodes is provided.
TODO: Cross validation pricing

## How to register a node

First, you will need to get ahold of `TOMA` tokens that are kept in the Atoma network as collateral to ensure the node is serious about its participation.
The Atoma network has a parameter `registration_collateral_in_protocol_token` that dictates how many `TOMA` tokens you need.
The collateral will be returned when the node unregisters from the network unless it has been slashed for bad behavior.
Then, call `atoma::db::register_node` which prints an authentication object called `NodeBadge` to the sender of the transaction.
This object is important as it serves as node's identification when interacting with the network.

Now, the node is ready to subscribe to [models](#which-models-are-supported) and start receiving prompts.
Find out what [HW group](#which-hardware-is-supported) does the node belong.
Use the `db::atoma::add_node_to_model` endpoint to start receiving prompts.

## How to unregister your node

To remove a node from a specific model but keep registered for other models, there is an endpoint `atoma::db::remove_node_from_model`.

> Note: This endpoint has a tiny chance of sporadically failing due to blockchain timing technicality.
> In such case, it's appropriate to retry the operation.

Completely leaving the Atoma network is a two step process:

1.  Call `atoma::db::permanently_disable_node`.
    No more prompts in any model will be sent to this node.
2.  After a wait period of 2 Sui epoch, call `atoma::db::destroy_disabled_node`.
    This gives any remaining fees and the collateral back to the node.

## How nodes accrue fees over epochs

Atoma stores all fees in an object `Balance<TOMA>` named `fee_treasury`.
Each node in Atoma has following relevant associated fields:

- `available_fee_amount` is a number of `TOMA` tokens that are available for _immediate_ withdrawal by the node.
  The node can use the `atoma::db::withdraw_fees` endpoint to collect their fees.
- `last_fee_epoch` is the Sui epoch number of the last fee settlement that was done for this node.
- `last_fee_epoch_amount` is the amount of fees that were collected for the node in the epoch `last_fee_epoch`.

When a new Sui epoch starts, ie. current epoch does not equal the `last_fee_epoch`, then the amount `last_fee_epoch_amount` is moved to `available_fee_amount`.

In the nutshell, for each prompt settlement a node is part of, its fee is available for withdrawal in the next Sui epoch.

## Which models are supported

TODO: Jorge

## Which hardware is supported

TODO: Jorge
