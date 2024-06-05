# Atoma on Sui

## What is Atoma

TODO: Jorge

## How we design Atoma

TODO: Jorge

## Smart contract logic overview

## Sampling consensus mechanism

## How to submit prompts to Atoma

## Parameters explanation

## Time to settlement

        /// If a node does not respond to a prompt within the timeout, it is
        /// slashed by this ‰ amount.
        permille_to_slash_node_on_timeout: u64,

                /// If settlement is not done within this time, we attempt to settle
        /// without waiting for nodes that did not respond.
        settlement_timeout_ms: u64,

## Pricing

        /// How much per input token is charged by nodes in this group.
        /// In TOMA tokens.
        input_fee_per_token: u64,
        /// How much per output token is charged by nodes in this group.
        /// In TOMA tokens.
        ///
        /// The difference between input and output is made because the input
        /// could be text and output could be an image, in which case this is
        /// interpreted as a fee per pixel.
        output_fee_per_token: u64,

            /// The fee is per input and output tokens.
    /// The provided estimation of the number of tokens is used to calculate
    /// the charged amount.
    /// However, the real fee is calculated when the nodes submit the results.
    /// The difference is refunded to the user.

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
