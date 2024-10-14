module atoma::db {
    //! At the heart of the Atoma network protocol is on-chain database.
    //! It keeps track of nodes and models.

    use atoma::atoma::ATOMA;
    use std::ascii;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_field;
    use sui::object_table::{Self, ObjectTable};
    use sui::package::{Self, Publisher};
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use toma::toma::TOMA;

    /// How many epochs after the stack expires during which any disputes must be resolved.
    const VAULT_DISPUTE_SETTLEMENT_DELAY: u64 = 2;

    /// Number of bytes per hash commitment
    const BYTES_PER_HASH_COMMITMENT: u64 = 32;

    /// How much collateral is required at the time of package publication.
    const InitialCollateralRequiredForRegistration: u64 = 1_000;
    /// Maximum time nodes can take to settle a prompt before we attempt to
    /// settle without them.
    /// This is the initial value and can change.
    const InitialSettlementTimeoutMs: u64 = 60_000;
    /// If a node does not respond to a prompt within the timeout, it is slashed
    /// by this ‰ amount.
    const InitialPermilleToSlashNodeOnTimeout: u64 = 100;
    /// How many tokens ‰ from all the confiscated slashed tokens should go to
    /// the oracle that settled the dispute.
    const InitialPermilleForOracleOnDispute: u64 = 100;
    /// Nodes that submitted correct (according to the oracle) results will get
    /// this ‰ of the slashed tokens.
    const InitialPermilleForHonestNodesOnDispute: u64 = 200;
    /// The probability of cross validation.
    /// We perform cross validation when the user does not specify how many
    /// nodes to sampled.
    /// See `gate` and `settlement` modules for more info.
    const InitialCrossValidationProbabilityPermille: u64 = 10;
    /// How many extra nodes to sample when cross validating.
    const InitialCrossValidationExtraNodesCount: u64 = 1;
    /// A small increment on the sampling consensus charge permille for each extra attestation node sampled
    const InitialCrossValidationExtraAttestationNodesChargePermille: u64 = 12;
    /// Security level for the task
    const SamplingConsensusSecurityLevel: u16 = 1;

    /// Additional fee charged per compute unit for the Sampling Consensus 
    /// attestation of the stack settlement ticket
    const InitialSamplingConsensusChargePermille: u64 = 1200; // Additional 20% charge

    /// Start value for reputation scores. It is the same
    /// for every node, in the initial state.
    const REPUTATION_SCORE_START: u8 = 100;

    /// To be able to identify the errors faster in the logs, we start the
    /// counter from a number that's leet for "error_000".
    const EBase: u64 = 312012_000;
    const ENodeRegDisabled: u64 = EBase + 0;
    const EModelDisabled: u64 = EBase + 1;
    const ENotAuthorized: u64 = EBase + 2;
    const EProtocolFeeCannotBeZero: u64 = EBase + 3;
    const ERelativePerformanceCannotBeZero: u64 = EBase + 4;
    const EEchelonNotFound: u64 = EBase + 5;
    const EEchelonAlreadyExistsForModel: u64 = EBase + 6;
    /// One cannot distribute more than 1000 ‰ of the total slashed collateral.
    /// So the ‰ that goes to the oracle plus the ‰ that goes to the honest
    /// nodes cannot be more than 1000 ‰.
    const ETotalPermilleMustBeLessThan1000: u64 = EBase + 7;
    const ENodeAlreadySubscribedToModel: u64 = EBase + 9;
    const ENodeNotSubscribedToModel: u64 = EBase + 10;
    /// This can happen due to race conditions in endpoint
    /// `remove_node_from_model`.
    /// The CLI depends on this error code when sending the tx.
    const ENodeIndexMismatch: u64 = EBase + 11;
    const ENodeAlreadyDisabled: u64 = EBase + 12;
    /// There's a 2 epoch wait.
    /// Ie., if you disable a node in epoch N, you can only destroy it in epoch
    /// N + 2.
    const ENodeMustWaitBeforeDestroy: u64 = EBase + 13;
    const ECannotSampleZeroNodes: u64 = EBase + 14;
    const ETaskDeprecated: u64 = EBase + 15;
    const ENodeAlreadySubscribedToTask: u64 = EBase + 16;
    const ETaskNotFound: u64 = EBase + 17;
    const ENodeNotSubscribedToTask: u64 = EBase + 18;
    const ENotEnoughEpochsPassed: u64 = EBase + 19;
    const ETaskNotDeprecated: u64 = EBase + 20;
    const EInvalidNodeIndex: u64 = EBase + 21;
    const EModelNotFound: u64 = EBase + 22;
    const ENoNodesSubscribedToTask: u64 = EBase + 23;
    const ENoNodesEligibleForTask: u64 = EBase + 25;
    const ENotStackOwner: u64 = EBase + 26;
    const ENodeNotSelectedForStack: u64 = EBase + 28;
    const EStackInSettlementDispute: u64 = EBase + 29;
    const ETooManyComputedUnits: u64 = EBase + 30;
    const EStackDoesNotRequireSamplingConsensus: u64 = EBase + 32;
    const EStackNotFound: u64 = EBase + 33;
    const EStackNotInSettlementDispute: u64 = EBase + 34;
    const EStackDisputePeriodOver: u64 = EBase + 35;
    const ENodeNotSelectedForAttestation: u64 = EBase + 36;
    const EStackInDispute: u64 = EBase + 37;
    const EStackDisputePeriodIsNotOver: u64 = EBase + 38;
    const ENodeNotSelectedForSettlement: u64 = EBase + 39;

    /// Emitted once upon publishing.
    public struct PublishedEvent has copy, drop {
        /// ID of the AtomaDb object
        db: ID,
        manager_badge: ID,
    }

    public struct NodeRegisteredEvent has copy, drop {
        /// ID of the NodeBadge object
        badge_id: ID,
        node_small_id: SmallId,
    }

    public struct NodeSubscribedToModelEvent has copy, drop {
        node_small_id: SmallId,
        model_name: ascii::String,
        echelon_id: EchelonId,
    }

    public struct NodeSubscribedToTaskEvent has copy, drop {
        task_small_id: SmallId,
        node_small_id: SmallId,
        price_per_compute_unit: u64,
    }

    public struct TaskRegisteredEvent has copy, drop {
        /// ID of the Task object
        task_id: ID,
        task_small_id: SmallId,
    }

    public struct TaskDeprecationEvent has copy, drop {
        /// ID of the Task object
        task_id: ID,
        task_small_id: SmallId,
        /// The epoch in which the task was deprecated.
        epoch: u64,
    }

    public struct StackCreatedEvent has copy, drop {
        /// ID of the Stack object
        stack_id: ID,
        small_id: SmallId,
        selected_node: SmallId,
        num_compute_units: u64,
        price: u64,
    }

    public struct StackTrySettleEvent has copy, drop {
        stack_small_id: SmallId,
        /// The node selected to process the requests in the stack
        selected_node_id: SmallId,
        /// Nodes selected for attestation of the commitment output, either
        /// of size 0 or size `CrossValidationExtraNodesCount`.
        requested_attestation_nodes: vector<SmallId>,
        /// Corresponds to the `committed_stack_proof` in the `settlement` module.
        /// It is computed as a '2-dimensional' Merkle root of the each (input, output) pair
        /// that is processed through the stack, iterated over the range [0, CrossValidationExtraNodesCount).
        /// More precisely, the Merkle tree root is constructed as follows:
        /// 1. For each i in [0, CrossValidationExtraNodesCount):
        ///    a. We construct a Merkle tree whose leaves are computed as H(input, output, i).
        ///    b. We compute the root of the i-th Merkle tree root, as MH_stack(i).
        /// 2. Then compute the Merkle root of the `CrossValidationExtraNodesCount`-ary Merkle tree
        ///    whose leaves are the `CrossValidationExtraNodesCount` roots MH_stack(i), for i in [0, CrossValidationExtraNodesCount),
        ///    denoted as MH_stack.
        /// 3. The result MH_stack is then committed as `committed_stack_proof` (in big-endian bytes encoding).
        /// Note: We use Blake2b-256 as the cryptographic hash function H and Merkle tree hash function MH_stack.
        committed_stack_proof: vector<u8>,
        /// The leaf of the Merkle tree MH_stack(0), where 
        stack_merkle_leaf: vector<u8>,
        // /// Proof of storage of all the request/response plus execution state generated by the node,
        // /// and stored on the Data Availability layer of the protocol (Walrus).
        // /// To be used by subsequent iterations of the protocol.
        // proof_of_storage: vector<u8>,
        /// Number of compute units claimed by the user.
        num_claimed_compute_units: u64,
    }

    /// Event emitted when a stack settlement ticket is fully settled and verified.
    ///
    /// This event represents the successful completion of the stack execution and verification process.
    /// It provides details about the executed stack, the node that processed it, and the attestation process.
    ///
    /// # Fields
    /// * `stack_small_id`: The unique identifier of the settled stack.
    /// * `selected_node_id`: The identifier of the node that processed the stack's requests.
    /// * `num_claimed_compute_units`: The number of compute units claimed by the processing node.
    /// * `requested_attestation_nodes`: A vector of node identifiers that were selected to attest 
    ///   the stack execution results. This vector will have a size of either 0 (if no attestation 
    ///   was required) or `CrossValidationExtraNodesCount` (if the associated Task has a security 
    ///   level set to `SamplingConsensusSecurityLevel`).
    /// * `dispute_settled_at_epoch`: The epoch at which the stack attestation was fully settled,
    ///   indicating when all verifications were completed.
    /// * `committed_stack_proof`: A cryptographic proof of the stack execution, typically a Merkle 
    ///   root of the execution results.
    ///
    /// # Note
    /// This event is crucial for tracking the completion of stack executions and their verification
    /// in the Atoma network. It serves as a record of successful settlements and can be used for 
    /// auditing, reward distribution, and system monitoring purposes.
    public struct StackSettlementTicketEvent has copy, drop {
        stack_small_id: SmallId,
        /// The node selected to process the requests in the stack
        selected_node_id: SmallId,
        /// Number of claimed computed units
        num_claimed_compute_units: u64,
        /// Nodes selected for attestation of the commitment output, either
        /// of size 0 or size `CrossValidationExtraNodesCount`, if the associated `Task` has security level set to `SamplingConsensusSecurityLevel`.
        requested_attestation_nodes: vector<SmallId>,
        /// The epoch at which the stack attestion is completely settled
        dispute_settled_at_epoch: u64,
        /// The committed stack proof
        committed_stack_proof: vector<u8>,
    }

    /// Event emitted when a stack settlement ticket is claimed and the associated funds are distributed.
    ///
    /// This event is triggered when a node successfully claims the funds for a completed stack execution
    /// and any remaining funds are refunded to the user.
    ///
    /// # Note
    /// This event helps track the final settlement of stacks, including the distribution of funds
    /// between the executing node and the refund to the user. It's useful for auditing and
    /// monitoring the financial aspects of stack executions in the Atoma network.
    public struct StackSettlementTicketClaimedEvent has copy, drop {
        /// The unique identifier of the stack that was settled.
        stack_small_id: SmallId,
        /// The identifier of the node that processed the stack and is claiming the funds.
        selected_node_id: SmallId,
        /// The nodes that have attested to the stack settlement ticket commitment, if any
        attestation_nodes: vector<SmallId>,
        /// The number of compute units actually used and claimed by the node.
        num_claimed_compute_units: u64,
        /// The amount of funds refunded to the user for unused compute units.
        user_refund_amount: u64,
    }

    public struct StackAttestationDisputeEvent has copy, drop {
        stack_small_id: SmallId,
        attestation_commitment: vector<u8>,
        attestation_node_id: SmallId,
        original_node_id: SmallId,
        original_commitment: vector<u8>,
    }

    /// Owned object.
    ///
    /// Represents authority over the package.
    public struct AtomaManagerBadge has key, store {
        id: UID,
    }

    /// Owned object, transferred to each node.
    ///
    /// Proof of registration for a node.
    public struct NodeBadge has key, store {
        id: UID,
        small_id: SmallId,
    }

    /// Owned object, transferred to the creator of a task.
    ///
    /// Proof of task creation.
    public struct TaskBadge has key, store {
        id: UID,
        small_id: SmallId,
    }

    /// Owned object, transferred to the creator of a stack.
    ///
    /// Proof of stack creation.
    public struct StackBadge has key, store {
        id: UID,
        small_id: SmallId,
    }

    /// Since referring to node is ubiquitous and potentially large collections
    /// are at stake, we assign a u64 ID to each node instead of using Sui
    /// address which is 32 bytes.
    public struct SmallId has store, copy, drop {
        /// # Important
        /// We start from 1 because 0 is reserved an empty node, which might
        /// become valuable to represent in future.
        inner: u64,
    }

    /// Represents a computational task on the Atoma network.
    /// Tasks can include model inference, text embeddings, fine-tuning, training,
    /// or other arbitrary computations.
    public struct Task has key, store {
        id: UID,
        /// The specific role or purpose of the task (e.g., "inference", "embedding", "fine-tuning")
        role: TaskRole,
        /// An optional unique identifier for a `ModelEntry`, if the task is associated with a particular model
        model_name: Option<ascii::String>,
        /// Indicates whether the task is deprecated and should no longer be used
        /// Deprecated tasks may be kept for historical reasons but should not be assigned to nodes
        is_deprecated: bool,
        /// The epoch until which this task is valid (inclusive)
        /// If Some(epoch), the task expires after this epoch. If None, the task doesn't expire
        valid_until_epoch: Option<u64>,
        /// Deprecated at epoch
        deprecated_at_epoch: Option<u64>,
        /// Unique set of optimizations that can be applied to the task
        optimizations: vector<u16>,
        /// Security level for the task
        security_level: u16,
        /// Efficiency metrics for the task (e.g. throughput, latency, cost, energy).
        /// Note: we might want to support multiple combined input efficiency metrics in the future.
        task_metrics: TaskMetrics,
        /// Subscribed nodes table, where key is node SmallId and value is price per compute unit
        /// for this current task.
        subscribed_nodes: TableVec<NodePriceData>,
    }

    /// Systems's efficiency metrics
    public struct TaskMetrics has store, copy, drop {
        /// The unit of compute for the efficiency metric
        compute_unit: u16,
        /// The time unit for which to evaluate the efficiency of the system required to complete the task.
        time_unit: Option<u16>,
        /// The value of the efficiency metric
        /// For example, if compute_unit corresponds to number of tokens, and time_unit corresponds to seconds,
        /// then the value represents the number of tokens processed per second.
        value: Option<u64>,
    }

    /// Represents the role or purpose of a computational task in the Atoma network.
    /// Each role is associated with a specific type of operation or computation,
    /// according to the predefined values above.
    public struct TaskRole has store, copy, drop { 
        inner: u16,
    }

    /// Reputation score of a node
    public struct ReputationScore has store, copy, drop {
        inner: u8,
    }

    /// Data about a node's price per compute unit for a task
    public struct NodePriceData has store, copy, drop {
        node_id: SmallId,
        /// Price per compute unit in TOMA for the current task
        price_per_compute_unit: u64,
        /// The maximum number of compute units that the node is willing to process for the current task
        max_num_compute_units: u64,
    }

    /// Stacks are owned by users and used to buy compute units for specific tasks.
    public struct Stack has store {
        /// Address of the owner of the stack
        owner: address,
        /// Price per compute unit in TOMA
        price: u64,
        /// Number of compute units remaining in the stack
        num_compute_units: u64,
        /// Node selected to process the requests in the stack
        selected_node: SmallId,
        /// The associated task SmallId
        task_small_id: SmallId,
    }

    public struct StackSettlementTicket has key, store {
        id: UID,
        /// The associated stack SmallId
        stack_small_id: SmallId,
        /// The node selected to process the requests in the stack
        selected_node_id: SmallId,
        /// Number of claimed computed units
        num_claimed_compute_units: u64,
        /// Nodes selected for attestation of the commitment output, either
        /// of size 0 or size `CrossValidationExtraNodesCount`, if the associated `Task` has security level set to `SamplingConsensusSecurityLevel`.
        requested_attestation_nodes: vector<SmallId>,
        /// The epoch after which the stack dispute is settled
        dispute_settled_at_epoch: u64,
        /// Corresponds to the `committed_stack_proof` in the `settlement` module.
        committed_stack_proof: vector<u8>,
        /// Corresponds to the `stack_merkle_leaf` in the `settlement` module.
        stack_merkle_leaves_vector: vector<u8>,
        /// Nodes that have already attested to the stack settlement ticket commitment (initialized to empty vector)
        already_attested_nodes: vector<SmallId>,
        /// Checks if the current ticket is in dispute or not
        is_in_dispute: bool,
    }

    /// Shared object.
    ///
    /// Database of the package.
    /// It stores information about each node and which models are supported by
    /// each node.
    ///
    /// It's primary accesses are:
    /// - random node selection per model
    /// - O(1) access to node metadata
    /// - O(1) access to model
    /// - O(1) access to tasks
    public struct AtomaDb has key {
        id: UID,
        /// Settlement is done via tickets that are associated with the
        /// database.
        ///
        /// We expose UID instead of an object table to avoid cyclic deps.
        tickets: UID,
        /// We keep track of total registered nodes so that we can generate
        /// SmallId for newly registered nodes as these IDs are sequential.
        next_node_small_id: SmallId,
        /// We keep track of registered tasks so taht we can generate
        /// SmallId for newly registered tasks as these IDs are sequential.
        next_task_small_id: SmallId,
        /// We keep track of registered stacks so that we can generate
        /// SmallId for newly registered stacks as these IDs are sequential.
        next_stack_small_id: SmallId,
        /// Holds information about each node.
        nodes: Table<SmallId, NodeEntry>,
        /// Each model is represented here and stores which nodes support it.
        models: ObjectTable<ascii::String, ModelEntry>,
        /// Each task is represented here and stores which nodes support it.
        tasks: ObjectTable<SmallId, Task>,
        /// Holds information about each stack
        stacks: Table<SmallId, Stack>,
        /// Holds information about each stack settlement ticket
        stack_settlement_tickets: ObjectTable<SmallId, StackSettlementTicket>,
        /// All fees and honest node rewards go here.
        /// We then do book-keeping on NodeEntry objects to calculate how much
        /// is available for withdrawal by each node.
        fee_treasury: Balance<TOMA>,
        /// When nodes get slashed, some of the collateral goes here.
        communal_treasury: Balance<TOMA>,
        /// We have a probabilistic cross validation feature.
        /// If the user submits a prompt but does not specify number of nodes
        /// to sample, we sample just one.
        /// Then, with this probability, we sample extra nodes to verify the
        /// results.
        cross_validation_probability_permille: u64,
        /// If we decide to sample extra nodes, this is how many we sample.
        cross_validation_extra_nodes_count: u64,
        /// Additional charge for the Sampling Consensus feature
        sampling_consensus_charge_permille: u64,
        /// Additional charge for the Cross Validation feature
        cross_validation_extra_nodes_charge_permille: u64,

        // Configuration

        /// If set to true, no new nodes can be registered.
        is_registration_disabled: bool,
        /// How many protocol tokens (ignoring decimal places) are required to
        /// be collateralized by a node in order to be registered.
        ///
        /// This setting can change as each node's collateralized balance
        /// is stored in the node's account data.
        registration_collateral_in_protocol_token: u64,
        /// If a node does not respond to a prompt within the timeout, it is
        /// slashed by this ‰ amount.
        permille_to_slash_node_on_timeout: u64,
        /// How many tokens ‰ from all the confiscated slashed tokens should go
        /// to the oracle that settled the dispute.
        permille_for_oracle_on_dispute: u64,
        /// Nodes that submitted correct (according to the oracle) results will
        /// get this ‰ of the slashed tokens.
        /// This plus `permille_for_oracle_on_dispute` must be less 1000.
        permille_for_honest_nodes_on_dispute: u64,
    }

    /// Field of AtomaDb.
    public struct NodeEntry has store {
        /// Once the node is disabled, it cannot be re-enabled.
        /// It must also wait for a certain number of epochs before it can be
        /// deleted and collateral reclaimed.
        was_disabled_in_epoch: Option<u64>,
        /// It can get slashed if node is not responding or if it submitted
        /// results that do not match the oracle's results.
        collateral: Balance<TOMA>,
        /// What's the epoch number of the last fee settlement.
        last_fee_epoch: u64,
        /// These fees have been deposited in epoch `last_fee_epoch`.
        /// They won't be available for withdrawal until the next epoch.
        last_fee_epoch_amount: u64,
        /// These fees are unlocked for the node to collect.
        available_fee_amount: u64,
        /// The relative performance of the node.
        ///
        /// We start from 100 and increase the reputation by 1,
        /// every epoch in which nodes are responsive
        /// and accurate.
        /// Nodes that are offline or produce incorrect results 
        /// will have their reputation score decreased, by 1 or more points.
        /// To a minimum of 0, in which case the node is slashed from the network.
        reputation_score: ReputationScore,
    }

    /// Object field of AtomaDb.
    public struct ModelEntry has key, store {
        id: UID,
        /// UTF8 model identifier.
        name: ascii::String,
        /// The modality of the model.
        /// Determines what kind of requests it can serve.
        modality: u64,
        /// Whether the model is disabled and cannot be used to serve prompts.
        is_disabled: bool,
        /// Which echelons (groups of nodes) support this model.
        ///
        /// EchelonId must be enabled by the package owner for each
        /// model.
        /// This allows the package owner to enable appropriate echelons
        /// for each model, e.g. large models might not even support low spec
        /// echelons.
        ///
        /// We use vector because mostly we just need to iterate the whole thing
        /// and filter out echelons that are not eligible to be considered in
        /// the selection process.
        echelons: vector<ModelEchelon>,
    }

    /// Stored in ModelEntry.
    public struct ModelEchelon has store {
        id: EchelonId,
        /// If settlement is not done within this time, we attempt to settle
        /// without waiting for nodes that did not respond.
        settlement_timeout_ms: u64,
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
        /// The higher this number, the more likely this echelon is to be
        /// selected to serve a prompt.
        /// Read it as "relative performance compared to other echelons".
        relative_performance: u64,
        /// Nodes that are elevated to an oracle level.
        /// These nodes are trusted and can settle disputes.
        oracles: VecSet<SmallId>,
        /// Which nodes support this model.
        /// We group nodes by HW and SW specs, because different echelons
        /// might end up having different outputs for the same model due to
        /// e.g. floating point arithmetics.
        /// Using a vector allows for a random access using an index.
        /// The order of nodes will not be preserved because we use
        /// `swap_remove` op on table vec.
        nodes: TableVec<SmallId>,
    }

    /// An opaque identifier for an echelon.
    /// We group echelons off-chain.
    /// Nodes must know at the time of registration which echelon they
    /// belong to.
    /// If they chose the wrong echelon, they might end up getting slashed
    /// for serving incorrect results.
    public struct EchelonId has store, copy, drop {
        id: u64
    }

    #[allow(unused_function)]
    fun init(ctx: &mut TxContext) {
        let atoma_db = AtomaDb {
            id: object::new(ctx),
            tickets: object::new(ctx),
            nodes: table::new(ctx),
            models: object_table::new(ctx),
            tasks: object_table::new(ctx),
            stacks: table::new(ctx),
            stack_settlement_tickets: object_table::new(ctx),
            fee_treasury: balance::zero(),
            communal_treasury: balance::zero(),
            // IMPORTANT: we start from 1 because 0 is reserved
            next_node_small_id: SmallId { inner: 1 },
            next_task_small_id: SmallId { inner: 1 },
            next_stack_small_id: SmallId { inner: 1 },
            is_registration_disabled: false,
            registration_collateral_in_protocol_token:
                InitialCollateralRequiredForRegistration,
            permille_to_slash_node_on_timeout:
                InitialPermilleToSlashNodeOnTimeout,
            permille_for_oracle_on_dispute: InitialPermilleForOracleOnDispute,
            permille_for_honest_nodes_on_dispute:
                InitialPermilleForHonestNodesOnDispute,
            cross_validation_probability_permille:
                InitialCrossValidationProbabilityPermille,
            cross_validation_extra_nodes_count:
                InitialCrossValidationExtraNodesCount,
            sampling_consensus_charge_permille:
                InitialSamplingConsensusChargePermille,
            cross_validation_extra_nodes_charge_permille:
                InitialCrossValidationExtraAttestationNodesChargePermille,
        };

        // Create a manager badge for the package owner for convenience.
        // More can be created later.
        let atoma_manager_badge = AtomaManagerBadge {
            id: object::new(ctx),
        };

        sui::event::emit(PublishedEvent {
            db: object::id(&atoma_db),
            manager_badge: object::id(&atoma_manager_badge),
        });

        transfer::share_object(atoma_db);
        transfer::transfer(atoma_manager_badge, ctx.sender());
    }

    /// Takes collateral from the sender's wallet and transfers them the node
    /// badge.
    public entry fun register_node_entry(
        self: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        ctx: &mut TxContext,
    ) {
        let badge = register_node(self, wallet.balance_mut(), ctx);
        transfer::transfer(badge, ctx.sender());
    }


    /// Creates a new task in the Atoma network and transfers the resulting TaskBadge to the sender.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `role` - A u16 representing the task role.
    /// * `model_name` - An optional ASCII string representing the model name.
    /// * `valid_until_epoch` - An optional u64 representing the epoch until which the task is valid.
    /// * `optimizations` - A vector of u16 representing optimization types.
    /// * `security_level` - An u16 representing the security level.
    /// * `efficiency_compute_units` - A u16 representing the compute units for efficiency metrics.
    /// * `efficiency_time_units` - An optional u16 representing the time units for efficiency metrics.
    /// * `efficiency_value` - An optional u64 representing the value for efficiency metrics.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Effects
    /// - Creates a new task in the AtomaDb.
    /// - Generates a TaskBadge for the newly created task.
    /// - Transfers the TaskBadge to the transaction sender.
    ///
    /// # Events
    /// Emits a TaskRegisteredEvent containing details about the newly created task.
    public entry fun create_task_entry(
        self: &mut AtomaDb,
        role: u16,
        model_name: Option<ascii::String>,
        valid_until_epoch: Option<u64>,
        optimizations: vector<u16>,
        security_level: u16,
        efficiency_compute_units: u16,
        efficiency_time_units: Option<u16>,
        efficiency_value: Option<u64>,
        ctx: &mut TxContext,
    ) {
        let badge = create_task(
            self,
            role,
            model_name,
            valid_until_epoch,
            optimizations,
            security_level,
            TaskMetrics {
                compute_unit: efficiency_compute_units,
                time_unit: efficiency_time_units,
                value: efficiency_value,
            },
            ctx,
        );
        transfer::transfer(badge, ctx.sender());
    }

    /// Creates a new task in the Atoma network and returns a TaskBadge.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `model_name` - An optional ASCII string representing the model name.
    /// * `role` - A u16 representing the task role.
    /// * `modality` - A u16 representing the task modality.
    /// * `valid_until_epoch` - An optional u64 representing the epoch until which the task is valid.
    /// * `optimizations` - An optional vector of u16 representing optimization types.
    /// * `security_level` - An u16 representing the security level.
    /// * `task_metrics` - An optional vector of EfficiencyMetric representing efficiency metrics.
    /// * `performance_unit` - An optional u16 representing the performance unit.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Returns
    /// A TaskBadge object representing the created task.
    public fun create_task(
        self: &mut AtomaDb,
        role: u16,
        mut model_name: Option<ascii::String>,
        valid_until_epoch: Option<u64>,
        optimizations: vector<u16>,
        security_level: u16,
        task_metrics: TaskMetrics,
        ctx: &mut TxContext,
    ): TaskBadge {
        let small_id = self.next_task_small_id;
        self.next_task_small_id.inner = self.next_task_small_id.inner + 1;

        if (model_name.is_some()) {
            let model_name = model_name.extract();
            assert!(self.models.contains(model_name), EModelNotFound);
        };

        let task = Task {
            id: object::new(ctx),
            role: TaskRole { inner: role },
            model_name,
            is_deprecated: false,
            valid_until_epoch,
            deprecated_at_epoch: option::none(),
            optimizations,
            security_level,
            task_metrics,
            subscribed_nodes: table_vec::empty(ctx),
        };
        let task_id = object::new(ctx);
        object_table::add(&mut self.tasks, small_id, task);
        
        sui::event::emit(TaskRegisteredEvent {
            task_id: object::uid_to_inner(&task_id),
            task_small_id: small_id,
        });

        TaskBadge {
            id: task_id,
            small_id,
        }
    }

    /// Deprecates a task in the Atoma network.
    ///
    /// This function marks a task as deprecated, preventing it from being used for new computations.
    /// It also records the epoch at which the task was deprecated.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `task_badge` - A mutable reference to the TaskBadge of the task to be deprecated.
    /// * `task_small_id` - The SmallId of the task to be deprecated.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Errors
    /// * `ETaskNotFound` - If the task specified by the TaskBadge is not found in the AtomaDb.
    ///
    /// # Effects
    /// * Sets the `is_deprecated` field of the task to `true`.
    /// * Sets the `deprecated_at_epoch` field of the task to the current epoch.
    /// * Emits a `TaskDeprecationEvent` with the task's SmallId and the current epoch.
    ///
    /// # Events
    /// Emits a `TaskDeprecationEvent` containing:
    /// * `task_small_id` - The SmallId of the deprecated task.
    /// * `epoch` - The epoch at which the task was deprecated.
    ///
    /// # Note
    /// This function does not delete the task from the database. It only marks it as deprecated,
    /// allowing for historical record-keeping while preventing future use of the task.
    public entry fun deprecate_task(
        self: &mut AtomaDb,
        task_badge: &mut TaskBadge,
        ctx: &mut TxContext,
    ) {
        let task_small_id = task_badge.small_id;
        assert!(self.tasks.contains(task_small_id), ETaskNotFound);

        let task = self.tasks.borrow_mut(task_badge.small_id);
        task.is_deprecated = true;
        task.deprecated_at_epoch = option::some(tx_context::epoch(ctx));

        sui::event::emit(TaskDeprecationEvent {
            task_id: object::uid_to_inner(&task.id),
            task_small_id: task_badge.small_id,
            epoch: tx_context::epoch(ctx),
        });
    }

    /// Removes a deprecated task from the task table.
    /// It only allows to remove deprecated tasks that 
    /// were deprecated at least 2 epochs from the current task.
    public entry fun remove_deprecated_task(
        self: &mut AtomaDb,
        task_badge: TaskBadge,
        ctx: &mut TxContext,
    ) {
        let TaskBadge {
            id: task_badge_id,
            small_id: task_small_id,
        } = task_badge;
        // Check if the task exists
        assert!(object_table::contains(&self.tasks, task_small_id), ETaskNotFound);

        let task = object_table::borrow(&self.tasks, task_small_id);
        
        // Check if the task is deprecated
        assert!(task.is_deprecated, ETaskNotDeprecated);
        
        // Check if the deprecated_at_epoch exists and if 4 epochs have passed
        assert!(option::is_some(&task.deprecated_at_epoch), ETaskNotDeprecated);
        let deprecated_epoch = *option::borrow(&task.deprecated_at_epoch);
        assert!(ctx.epoch() >= deprecated_epoch + 2, ENotEnoughEpochsPassed);

        // If all checks pass, remove the task from the object table
        // and drop the task object altogether
        let task = object_table::remove(&mut self.tasks, task_small_id);
        let Task {
            id: task_id,
            role: _,
            model_name: _,
            is_deprecated: _,
            valid_until_epoch: _,
            deprecated_at_epoch: _,
            optimizations: _,
            security_level: _,
            task_metrics: _,
            subscribed_nodes,
        } = task;

        task_badge_id.delete();
        task_id.delete();
        subscribed_nodes.drop();
    }

    /// Splits the collateral from the sender's wallet and registers a new node.
    /// Returns a node badge.
    /// The node badge is intended to be owned by the node as a proof of
    /// registration.
    /// It can be used later to add or remove available models, delete account,
    /// subscribe to new tasks, unsubscribe from previous tasks, etc.
    public fun register_node(
        self: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        ctx: &mut TxContext,
    ): NodeBadge {
        assert!(!self.is_registration_disabled, ENodeRegDisabled);

        let collateral =
            wallet.split(self.registration_collateral_in_protocol_token);

        let small_id = self.next_node_small_id;
        self.next_node_small_id.inner = self.next_node_small_id.inner + 1;

        let node_entry = NodeEntry {
            collateral,
            was_disabled_in_epoch: option::none(),
            last_fee_epoch: ctx.epoch(),
            last_fee_epoch_amount: 0,
            available_fee_amount: 0,
            reputation_score: ReputationScore { inner: REPUTATION_SCORE_START },
        };
        self.nodes.add(small_id, node_entry);

        let badge_id = object::new(ctx);
        sui::event::emit(NodeRegisteredEvent {
            badge_id: object::uid_to_inner(&badge_id),
            node_small_id: small_id,
        });
        NodeBadge {
            id: badge_id,
            small_id,
        }
    }

    /// Subscribes a node to a specific task.
    /// 
    /// This function allows a node to subscribe to a task, enabling it to participate in
    /// the execution of that task within the Atoma network.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A mutable reference to the NodeBadge of the subscribing node.
    /// * `task_small_id` - The SmallId of the task to subscribe to.
    ///
    /// # Errors
    /// * `ETaskNotFound` - If the specified task does not exist in the AtomaDb.
    /// * `ETaskDeprecated` - If the specified task has been deprecated.
    /// * `ENodeAlreadySubscribedToTask` - If the node is already subscribed to the task.
    ///
    /// # Events
    /// Emits a `NodeSubscribedToTaskEvent` upon successful subscription.
    public entry fun subscribe_node_to_task(
        self: &mut AtomaDb,
        node_badge: &mut NodeBadge,
        task_small_id: u64,
        price_per_compute_unit: u64,
        max_num_compute_units: u64,
    ) {
        let task_small_id = SmallId { inner: task_small_id };
        assert!(self.tasks.contains(task_small_id), ETaskNotFound);

        let task = self.tasks.borrow_mut(task_small_id);
        assert!(!task.is_deprecated, ETaskDeprecated);

        // a node can subscribe to a task only once
        assert!(
            !dynamic_field::exists_(&node_badge.id, task_small_id),
            ENodeAlreadySubscribedToTask,
        );
        table_vec::push_back(&mut task.subscribed_nodes, NodePriceData {
            node_id: node_badge.small_id,
            price_per_compute_unit,
            max_num_compute_units,
        });
        // Associate the task_small_id with the node badge
        dynamic_field::add(&mut node_badge.id, task_small_id, true);

        sui::event::emit(NodeSubscribedToTaskEvent {
            node_small_id: node_badge.small_id,
            task_small_id,
            price_per_compute_unit,
        });
    }

    /// Unsubscribes a node from a specific task.
    ///
    /// This function removes a node's subscription to a task, updating both the node's
    /// dynamic fields and the task's list of subscribed nodes.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A mutable reference to the NodeBadge of the node being unsubscribed.
    /// * `task_small_id` - The SmallId of the task from which the node is unsubscribing.
    ///
    /// # Errors
    /// * `ENodeNotSubscribedToTask` - If the node is not subscribed to the specified task.
    /// * `ENodeIndexMismatch` - If the node is not found in the task's subscribed_nodes list.
    public entry fun unsubscribe_node_from_task(
        self: &mut AtomaDb,
        node_badge: &mut NodeBadge,
        task_small_id: u64,
    ) {
        let task_small_id = SmallId { inner: task_small_id };
        let perhaps_task_small_id: Option<bool> = dynamic_field::remove_if_exists(&mut node_badge.id, task_small_id);
        assert!(perhaps_task_small_id.is_some(), ENodeNotSubscribedToTask);

        let task = self.tasks.borrow_mut(task_small_id);
        let mut node_index = find_node_index(&task.subscribed_nodes, node_badge.small_id);
        assert!(node_index.is_some(), ENodeNotSubscribedToTask);

        let node_index = option::extract(&mut node_index);

        let removed_node_price_data = table_vec::swap_remove(&mut task.subscribed_nodes, node_index);
        assert!(
            removed_node_price_data.node_id.inner == node_badge.small_id.inner,
            ENodeIndexMismatch,
        );
    }

    /// Unsubscribes a node from a specific task, provided the index of the node in the task's subscribed_nodes list.
    /// This method is similar to `unsubscribe_node_from_task` but takes an additional `node_index` parameter, and 
    /// has potential lower gas costs.
    ///
    /// This function removes a node's subscription to a task, updating both the node's
    /// dynamic fields and the task's list of subscribed nodes.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A mutable reference to the NodeBadge of the node being unsubscribed.
    /// * `task_small_id` - The SmallId of the task from which the node is unsubscribing.
    /// * `node_index` - The index of the node in the task's subscribed_nodes list.
    ///
    /// # Errors
    /// * `ENodeNotSubscribedToTask` - If the node is not subscribed to the specified task.
    /// * `ENodeIndexMismatch` - If the node at the given index doesn't match the node being unsubscribed.
    /// * `EInvalidNodeIndex` - If the provided node_index is out of bounds.
    public entry fun unsubscribe_node_from_task_by_index(
        self: &mut AtomaDb,
        node_badge: &mut NodeBadge,
        task_small_id: u64,
        node_index: u64,
    ) {
        let task_small_id = SmallId { inner: task_small_id };
        let perhaps_task_small_id: Option<bool> = dynamic_field::remove_if_exists(&mut node_badge.id, task_small_id);
        assert!(perhaps_task_small_id.is_some(), ENodeNotSubscribedToTask);

        let task = self.tasks.borrow_mut(task_small_id);
        
        // Check if the provided node_index is valid
        assert!(node_index < task.subscribed_nodes.length(), EInvalidNodeIndex);

        let removed_node_price_data = task.subscribed_nodes.swap_remove(node_index);
        assert!(
            removed_node_price_data.node_id.inner == node_badge.small_id.inner,
            ENodeIndexMismatch,
        );
    }

    /// Creates a new stack for a specific task and transfers the resulting StackBadge to the sender.
    ///
    /// This entry function is a wrapper around the `acquire_new_stack` function, handling the creation
    /// of a random number generator and the transfer of the StackBadge to the transaction sender.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `wallet` - A mutable reference to the Coin<TOMA> object to pay for the stack.
    /// * `task_small_id` - The SmallId of the task associated with this stack.
    /// * `num_compute_units` - The number of compute units allocated to this stack.
    /// * `price` - The price per compute unit in TOMA tokens.
    /// * `random` - A reference to a Random object for generating random numbers.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Effects
    /// - Creates a new stack in the AtomaDb.
    /// - Generates a StackBadge for the newly created stack.
    /// - Transfers the StackBadge to the transaction sender.
    /// - Deducts the cost of compute units from the provided wallet.
    ///
    /// # Aborts
    /// This function may abort if:
    /// - The task specified by `task_small_id` does not exist.
    /// - There are no eligible nodes to process the stack's requests.
    /// - The wallet does not have sufficient balance to pay for the compute units.
    ///
    /// # Events
    /// Emits a StackCreatedEvent containing details about the newly created stack.
    entry fun acquire_new_stack_entry(
        self: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        task_small_id: u64,
        num_compute_units: u64,
        price: u64,
        random: &sui::random::Random,
        ctx: &mut TxContext,
    ) {
        let mut rng = random.new_generator(ctx);
        let stack_badge = acquire_new_stack(
            self, 
            wallet.balance_mut(),
            task_small_id, 
            num_compute_units, 
            price, 
            &mut rng, 
            ctx,
        );
        transfer::transfer(stack_badge, ctx.sender());
    }

    /// Creates a new stack for a specific task and returns a StackBadge.
    ///
    /// This function creates a new stack associated with a given task, selects a node to process
    /// the requests, and initializes the stack with the specified parameters.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `task_small_id` - The SmallId of the task associated with this stack.
    /// * `num_compute_units` - The number of compute units allocated to this stack.
    /// * `expiration_epoch` - An optional expiration epoch for the stack.
    /// * `price` - The price per compute unit in TOMA tokens.
    /// * `rng` - A mutable reference to a RandomGenerator for node selection.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Returns
    /// A StackBadge object representing the newly created stack.
    ///
    /// # Aborts
    /// * If the expiration epoch is not greater than the current epoch (when provided).
    ///
    /// # Events
    /// Emits a StackCreatedEvent containing details about the newly created stack.
    ///
    /// # Notes
    /// - The function selects a node for the stack using the `sample_node_for_stack` method.
    /// - The stack is initialized as not being in dispute.
    /// - A new SmallId is assigned to the stack, incrementing the `next_stack_small_id` counter.
    fun acquire_new_stack(
        self: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        task_small_id: u64,
        num_compute_units: u64,
        price: u64,
        rng: &mut sui::random::RandomGenerator,
        ctx: &mut TxContext,
    ): StackBadge {
        let owner = ctx.sender();
        let stack_id = object::new(ctx);
        let task_small_id = SmallId { inner: task_small_id };
        let selected_node = self.sample_node_for_stack(task_small_id, price, num_compute_units, rng);
        let task = self.tasks.borrow(task_small_id);

        let stack = Stack { 
            owner,
            task_small_id,
            num_compute_units,
            selected_node,
            price,
        };

        let stack_small_id = self.next_stack_small_id;
        self.next_stack_small_id = SmallId { 
            inner: self.next_stack_small_id.inner + 1 
        };
        self.stacks.add(stack_small_id, stack);

        // transfer the funds for compute units to the contract
        let fee_amount = if (task.security_level == SamplingConsensusSecurityLevel) {
            (price * num_compute_units * (self.get_sampling_consensus_charge_permille() + self.get_cross_validation_extra_nodes_charge_permille())) / 1000
        } else {
            (price * num_compute_units) / 1000
        };
        let funds = wallet.split(fee_amount);
        self.deposit_to_fee_treasury(funds);

        sui::event::emit(StackCreatedEvent {
            stack_id: object::uid_to_inner(&stack_id),
            small_id: stack_small_id,
            selected_node,
            num_compute_units,
            price,
        });

        StackBadge {
            id: stack_id,
            small_id: stack_small_id,
        }
    }

    /// Attempts to settle a stack by creating a settlement ticket.
    ///
    /// This function is called by a node to claim completion of a stack's compute units and initiate the settlement process.
    /// It creates a StackSettlementTicket, which represents the node's claim and allows for potential dispute resolution.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A mutable reference to the NodeBadge of the node attempting to settle.
    /// * `stack_small_id` - The SmallId of the stack being settled.
    /// * `num_claimed_compute_units` - The number of compute units the node claims to have processed.
    /// * `committed_stack_proof` - A vector<u8> representing the cryptographic proof of the stack's execution.
    /// * `stack_merkle_leaf` - A vector<u8> representing the commitment to the leaf of the stack's Merkle tree.
    /// * `random` - A reference to a Random object for generating random numbers.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Errors
    /// * `ENotStackOwner` - If the transaction sender is not the owner of the stack.
    /// * `ENodeNotSelectedForStack` - If the node attempting to settle was not selected for this stack.
    /// * `ETooManyComputedUnits` - If the claimed compute units exceed the stack's total compute units.
    /// * `EStackAlreadySettled` - If a settlement ticket already exists for this stack.
    ///
    /// # Effects
    /// - Creates a StackSettlementTicket and adds it to the AtomaDb's stack_settlement_tickets.
    /// - For tasks with SamplingCrossValidation security level, may sample additional attestation nodes.
    /// - Emits a StackTrySettleEvent with details of the settlement attempt.
    ///
    /// # Security Considerations
    /// - The function uses a random number generator to determine if additional attestation nodes should be sampled.
    /// - The dispute settlement epoch is set to a future epoch to allow time for potential disputes.
    ///
    /// # Events
    /// Emits a StackTrySettleEvent containing:
    /// - `small_id`: The SmallId of the settled stack.
    /// - `num_claimed_compute_units`: The number of compute units claimed by the node.
    /// - `requested_attestation_nodes`: A vector of SmallIds representing additional nodes sampled for attestation (if any).
    /// - `committed_stack_proof`: The cryptographic proof of the stack's execution.
    /// - `stack_merkle_leaf`: The commitment to the leaf of the stack's Merkle tree.
    entry fun try_settle_stack(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        stack_small_id: u64,
        num_claimed_compute_units: u64,
        committed_stack_proof: vector<u8>,
        stack_merkle_leaf: vector<u8>,
        random: &sui::random::Random,
        ctx: &mut TxContext,
    ) {
        let stack_small_id = SmallId { inner: stack_small_id };
        // Get all necessary values from self before any mutable borrows
        let cross_validation_probability = self.get_cross_validation_probability_permille();
        let cross_validation_extra_nodes_count = self.get_cross_validation_extra_nodes_count();

        let stack = self.stacks.borrow(stack_small_id);
        assert!(stack.owner == ctx.sender(), ENotStackOwner);

        let node_small_id = node_badge.small_id;
        assert!(node_small_id == stack.selected_node, ENodeNotSelectedForStack);
        assert!(num_claimed_compute_units <= stack.num_compute_units, ETooManyComputedUnits);
        assert!(!self.stack_settlement_tickets.contains(stack_small_id), EStackInSettlementDispute);

        let task_small_id = stack.task_small_id;
        let task = self.tasks.borrow(task_small_id);
        let security_level = task.security_level;
        let stack_price = stack.price;

         // Only Sampling Consensus security level needs to sample attestation nodes
        let attestation_nodes: vector<SmallId> = if (security_level == SamplingConsensusSecurityLevel) {      
            let mut rng = random.new_generator(ctx);
            let random_number = (rng.generate_u64() % 1000) + 1;
            if (random_number <= cross_validation_probability) {
                self.sample_attestation_nodes(task_small_id, stack_price, stack.num_compute_units, &mut rng)
            } else {
                vector::empty()
            }
        } else {
            vector::empty()
        };

        // Populate the stack merkle leaves vector, by copying the stack merkle leaf
        // for the first BYTES_PER_HASH_COMMITMENT bytes, and then padding with 0s
        // for the remaining cross_validation_extra_nodes_count * BYTES_PER_HASH_COMMITMENT bytes 
        let mut stack_merkle_leaves_vector = vector::empty();
        let mut i = 0;
        while (i < BYTES_PER_HASH_COMMITMENT) {
            vector::push_back(&mut stack_merkle_leaves_vector, stack_merkle_leaf[i]);
            i = i + 1;
        };

        let mut j = 0;
        while (j < cross_validation_extra_nodes_count * BYTES_PER_HASH_COMMITMENT) {
            vector::push_back(&mut stack_merkle_leaves_vector, 0);
            j = j + 1;
        };

        let ticket_id = object::new(ctx);
        let stack_settlement_ticket = StackSettlementTicket {
            id: ticket_id,
            stack_small_id: stack_small_id,
            selected_node_id: node_small_id,
            num_claimed_compute_units,
            requested_attestation_nodes: attestation_nodes,
            dispute_settled_at_epoch: ctx.epoch() + VAULT_DISPUTE_SETTLEMENT_DELAY,
            committed_stack_proof,
            stack_merkle_leaves_vector,
            already_attested_nodes: vector::empty(),
            is_in_dispute: false,
        };

        self.stack_settlement_tickets.add(stack_small_id, stack_settlement_ticket);

        sui::event::emit(StackTrySettleEvent {
            stack_small_id: stack_small_id,
            selected_node_id: node_small_id,
            num_claimed_compute_units,
            requested_attestation_nodes: attestation_nodes,
            committed_stack_proof,
            stack_merkle_leaf,
        });
    }

    /// Submits an attestation for a stack settlement in the Atoma network.
    ///
    /// This function allows an attestation node to submit its verification of a stack's execution results.
    /// It's part of the consensus mechanism for tasks with a Sampling Consensus security level.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A reference to the NodeBadge of the attesting node.
    /// * `stack_small_id` - The SmallId of the stack being attested.
    /// * `committed_stack_proof` - A vector<u8> representing the cryptographic proof of the stack's execution.
    /// * `stack_merkle_leaf` - A vector<u8> representing the Merkle leaf for this attestation.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Behavior
    /// 1. Verifies the existence of the stack and its settlement ticket.
    /// 2. Checks if the stack's associated task requires Sampling Consensus.
    /// 3. Ensures the dispute period is still ongoing.
    /// 4. Verifies that the attesting node was selected for attestation.
    /// 5. Records the attestation in the stack's Merkle tree.
    /// 6. If all attestations are received, computes the Merkle root and verifies consensus.
    ///
    /// # Errors
    /// * `EStackNotFound` - If the specified stack does not exist.
    /// * `EStackNotInSettlementDispute` - If there's no ongoing settlement for the stack.
    /// * `EStackDoesNotRequireSamplingConsensus` - If the stack's task doesn't use Sampling Consensus.
    /// * `EStackDisputePeriodOver` - If the dispute period has ended.
    /// * `ENodeNotSelectedForAttestation` - If the attesting node wasn't selected for this stack.
    ///
    /// # Events
    /// Emits a `StackSettlementTicketEvent` if all attestations are received and agree.
    ///
    /// # Notes
    /// - This function is crucial for the decentralized verification of task executions in Atoma.
    /// - It implements a multi-party consensus mechanism to ensure the integrity of computation results.
    /// - In case of disagreement, it triggers a dispute resolution process.
    public entry fun submit_stack_settlement_attestation(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        stack_small_id: u64,
        committed_stack_proof: vector<u8>,
        stack_merkle_leaf: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let stack_small_id = SmallId { inner: stack_small_id };

        // 1. Verify that both the stack and the stack settlement ticket exist
        assert!(self.stacks.contains(stack_small_id), EStackNotFound);
        assert!(self.stack_settlement_tickets.contains(stack_small_id), EStackNotInSettlementDispute);

        let stack = self.stacks.borrow(stack_small_id);
    
        // 2. Verify that the stack requires sampling consensus security level
        let task_small_id = stack.task_small_id;
        let security_level = self.tasks.borrow(task_small_id).security_level;
        assert!(security_level == SamplingConsensusSecurityLevel, EStackDoesNotRequireSamplingConsensus);

        // 3. Verify that the dispute challenge is ongoing
        let dispute_settled_at_epoch = self.stack_settlement_tickets.borrow(stack_small_id).dispute_settled_at_epoch;
        assert!(dispute_settled_at_epoch >= ctx.epoch(), EStackDisputePeriodOver);

        // 4. Check that the current node was selected as an attestation node
        let attestation_nodes = self.stack_settlement_tickets.borrow(stack_small_id).requested_attestation_nodes;
        assert!(vector::contains(&attestation_nodes, &node_badge.small_id), ENodeNotSelectedForAttestation);

        // 5. Obtain the index of the current attestation node in the attestation_nodes vector
        let mut attestation_node_index = 0;
        while (attestation_node_index < vector::length(&attestation_nodes)) {
            if (*vector::borrow(&attestation_nodes, attestation_node_index) == node_badge.small_id) {
                break
            };
            attestation_node_index = attestation_node_index + 1;
        };

        // 6. Verify that the committed stack proof agrees with the stack merkle commitment
        let original_committed_stack_proof = self.stack_settlement_tickets.borrow(stack_small_id).committed_stack_proof;
        if (committed_stack_proof != original_committed_stack_proof) {
            // Start attestation dispute and return immediately
            self.start_attestation_dispute(node_badge, stack_small_id.inner, committed_stack_proof);
            return
        };

        let stack_settlement_ticket = self.stack_settlement_tickets.borrow_mut(stack_small_id);

        // 6. Write the merkle leaf to the stack
        let mut i = 0;
        while (i < BYTES_PER_HASH_COMMITMENT) { 
            let starts_at = attestation_node_index * BYTES_PER_HASH_COMMITMENT;
            *vector::borrow_mut(&mut stack_settlement_ticket.stack_merkle_leaves_vector, starts_at + i) = stack_merkle_leaf[i];
            i = i + 1;
        };

        // 7. Check if the attestation node is the last one to submit the merkle leaf
        let num_of_committments = vector::length(&stack_settlement_ticket.already_attested_nodes);
        vector::push_back(&mut stack_settlement_ticket.already_attested_nodes, node_badge.small_id);
        let num_attestation_nodes = vector::length(&attestation_nodes);
        if (num_of_committments == num_attestation_nodes) {
            // 8. If the last node has submitted the merkle leaf, 
            //    compute the root hash of the merkle tree
            //    and check that it agrees with the committed stack proof
            let stack_merkle_leaves_vector = stack_settlement_ticket.stack_merkle_leaves_vector;
            let stack_merkle_root = sui::hash::blake2b256(&stack_merkle_leaves_vector);
            if (stack_merkle_root != committed_stack_proof) {
                // 9. In case the committed `stack_merkle_root` does not agree with the computed `stack_merkle_root`,
                //    start between the original node and every attestation node
                //    to determine which one of them are faulty
                self.start_attestation_dispute(node_badge, stack_small_id.inner, committed_stack_proof);
            } else {
                // 10. If the `stack_merkle_root` agrees with the committed `stack_merkle_root`,
                //     then the attestation settlement is complete and we emit a StackSettlementTicketEvent
                sui::event::emit(StackSettlementTicketEvent {
                    stack_small_id,
                    selected_node_id: stack.selected_node,
                    num_claimed_compute_units: stack_settlement_ticket.num_claimed_compute_units,
                    requested_attestation_nodes: attestation_nodes,
                    dispute_settled_at_epoch: ctx.epoch(),
                    committed_stack_proof,
                });
            }
        };
    }

    /// Claims funds for settled stacks and distributes rewards to nodes and users.
    ///
    /// This function allows a node to claim funds for multiple settled stacks. It processes each
    /// settled stack, distributes rewards to the selected node and attestation nodes (if any),
    /// refunds unused funds to the user, and cleans up the associated data structures.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A reference to the NodeBadge of the claiming node.
    /// * `settled_ticket_ids` - A vector of u64 representing the IDs of settled stack tickets to process.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Behavior
    /// For each settled stack ticket:
    /// 1. Retrieves the stack settlement ticket, stack, and associated task information.
    /// 2. Verifies that the stack is not in dispute and the dispute period has ended.
    /// 3. Calculates the reward for the selected node based on the number of claimed compute units and security level.
    /// 4. Calculates any refund due to the user for unused compute units.
    /// 5. If attestation nodes were involved:
    ///    - Distributes rewards to attestation nodes that submitted attestations.
    ///    - Slashes collateral of attestation nodes that failed to submit attestations.
    /// 6. Transfers funds to the selected node and refunds the user.
    /// 7. Deletes the stack settlement ticket and stack data.
    /// 8. Emits a StackSettlementTicketClaimedEvent for each processed stack.
    ///
    /// # Aborts
    /// * If any stack settlement ticket is still in dispute (EStackInDispute).
    /// * If the dispute period for any stack has not yet ended (EStackDisputePeriodIsNotOver).
    ///
    /// # Events
    /// Emits a StackSettlementTicketClaimedEvent for each successfully processed stack, containing:
    /// - The stack's small ID
    /// - The ID of the selected node
    /// - The list of attestation nodes (if any)
    /// - The number of claimed compute units
    /// - The amount refunded to the user
    ///
    /// # Important Notes
    /// - This function handles both regular and sampling consensus security levels differently.
    /// - It ensures that funds are correctly distributed among all participating nodes and users.
    /// - The function cleans up data structures, removing processed stacks and tickets.
    /// - It's designed to handle multiple stack settlements in a single transaction, improving efficiency.
    public entry fun claim_funds(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        settled_ticket_ids: vector<u64>,
        ctx: &mut TxContext,
    ) { 
        // 1. The node claims the funds to which it was selected to process the stack
        let num_settled_tickets = vector::length(&settled_ticket_ids);
        let mut index = 0;

        let sampling_consensus_charge_permille = self.get_sampling_consensus_charge_permille();
        let cross_validation_extra_nodes_count = self.get_cross_validation_extra_nodes_count();

        while (index < num_settled_tickets) {
        let stack_small_id = SmallId { inner: *vector::borrow(&settled_ticket_ids, index) };
            // 2. Fetch relevant data
            let (security_level, stack_price, num_compute_units, owner, selected_node_id, num_claimed_compute_units, attestation_nodes) = {
                let stack_settlement_ticket = self.stack_settlement_tickets.borrow(stack_small_id);
                let stack = self.stacks.borrow(stack_small_id);
                let task = self.tasks.borrow(stack.task_small_id);
                
                assert!(stack_settlement_ticket.selected_node_id == node_badge.small_id, ENodeNotSelectedForSettlement);
                assert!(!stack_settlement_ticket.is_in_dispute, EStackInDispute);
                assert!(
                    ctx.epoch() >= stack_settlement_ticket.dispute_settled_at_epoch, 
                    EStackDisputePeriodIsNotOver
                );
                
                (
                    task.security_level,
                    stack.price,
                    stack.num_compute_units,
                    stack.owner,
                    stack_settlement_ticket.selected_node_id,
                    stack_settlement_ticket.num_claimed_compute_units,
                    stack_settlement_ticket.requested_attestation_nodes
                )
            };

            // 6. Compute the funds, for the current stack, to send to the node
            let node_fee_amount = if (security_level == SamplingConsensusSecurityLevel) {
                (num_claimed_compute_units * stack_price * sampling_consensus_charge_permille) / 1000
            } else {
                num_claimed_compute_units * stack_price
            };

            // 7. Check if there are remaining funds to be sent back to the user
            let remaining_compute_units = num_compute_units - num_claimed_compute_units;
            let user_refund_amount = if (security_level == SamplingConsensusSecurityLevel) {
                (remaining_compute_units * stack_price * sampling_consensus_charge_permille) / 1000
            } else {
                remaining_compute_units * stack_price
            };

            // 8. Check if there are any attestation nodes for the current stack
            let num_attestation_nodes = vector::length(&attestation_nodes);
            if (num_attestation_nodes > 0) {
                // 9. If there are attestation nodes, compute the amount of funds to send to each attestation node
                let mut attestation_node_index = 0;
                while (attestation_node_index < num_attestation_nodes) {
                    let attestation_node_id = *vector::borrow(&attestation_nodes, attestation_node_index);
                    let already_attested = {
                        let stack_settlement_ticket = self.stack_settlement_tickets.borrow(stack_small_id);
                        vector::contains(&stack_settlement_ticket.already_attested_nodes, &attestation_node_id)
                    };

                    if (already_attested) {
                        // 10. In this case, the selected attestation node has already submitted its attestation
                        //     so we add the node fee amount to the node's available fee amount
                        let attestation_node_fee = (node_fee_amount / cross_validation_extra_nodes_count);
                        let node_entry = self.nodes.borrow_mut(attestation_node_id);
                        node_entry.available_fee_amount = node_entry.available_fee_amount + attestation_node_fee;
                    } else {
                        // 11. In this case, the selected attestation node has not submitted its attestation
                        //     so we should partially slash its collateral
                        let conficasted_balance = self.slash_node_on_timeout(attestation_node_id);
                        self.deposit_to_communal_treasury(conficasted_balance);
                    };
                    attestation_node_index = attestation_node_index + 1;
                }
            };

            // 12. Send the remaining funds back to the user
            self.transfer_funds(node_fee_amount, ctx.sender(), ctx);
            self.transfer_funds(user_refund_amount, owner, ctx);

            // 13. Remove the stack settlement ticket from the ObjectTable
            let StackSettlementTicket {
                id,
                stack_small_id: _,
                num_claimed_compute_units: _,
                stack_merkle_leaves_vector: _,
                already_attested_nodes: _,
                committed_stack_proof: _,
                dispute_settled_at_epoch: _,
                is_in_dispute: _,
                requested_attestation_nodes: _,
                selected_node_id: _,
            } = object_table::remove(&mut self.stack_settlement_tickets, stack_small_id);
            id.delete();

            // 14. Remove the stack from the Table
            let Stack {
                task_small_id: _,
                selected_node: _,
                owner: _,
                price: _,
                num_compute_units: _,
            } = table::remove(&mut self.stacks, stack_small_id);

            // 15. Emit a StackSettlementTicketClaimedEvent
            sui::event::emit(StackSettlementTicketClaimedEvent {
                stack_small_id,
                selected_node_id: selected_node_id,
                attestation_nodes: attestation_nodes,
                num_claimed_compute_units,
                user_refund_amount,
            });

            // 16. Increment the index
            index = index + 1;
        };

        // 17. Finally, we distribute the remaning funds to the node
        self.withdraw_fees(node_badge, ctx);
    }

//     public entry fun claim_funds(
//     self: &mut AtomaDb,
//     node_badge: &NodeBadge,
//     settled_ticket_ids: vector<u64>,
//     ctx: &mut TxContext,
// ) { 
//     let num_settled_tickets = vector::length(&settled_ticket_ids);
//     let mut index = 0;

//     let sampling_consensus_charge_permille = self.get_sampling_consensus_charge_permille();
//     let cross_validation_extra_nodes_count = self.get_cross_validation_extra_nodes_count();
    
//     while (index < num_settled_tickets) {
//         let stack_small_id = SmallId { inner: *vector::borrow(&settled_ticket_ids, index) };
        
//         // Fetch necessary data without mutable borrows
//         let (security_level, stack_price, num_compute_units, owner, selected_node_id, num_claimed_compute_units, attestation_nodes) = {
//             let stack_settlement_ticket = self.stack_settlement_tickets.borrow(stack_small_id);
//             let stack = self.stacks.borrow(stack_small_id);
//             let task = self.tasks.borrow(stack.task_small_id);
            
//             assert!(stack_settlement_ticket.selected_node_id == node_badge.small_id, ENodeNotSelectedForSettlement);
//             assert!(!stack_settlement_ticket.is_in_dispute, EStackInDispute);
//             assert!(
//                 ctx.epoch() >= stack_settlement_ticket.dispute_settled_at_epoch, 
//                 EStackDisputePeriodIsNotOver
//             );
            
//             (
//                 task.security_level,
//                 stack.price,
//                 stack.num_compute_units,
//                 stack.owner,
//                 stack_settlement_ticket.selected_node_id,
//                 stack_settlement_ticket.num_claimed_compute_units,
//                 stack_settlement_ticket.requested_attestation_nodes
//             )
//         };

//         // Compute fees
//         let node_fee_amount = if (security_level == SamplingConsensusSecurityLevel) {
//             (num_claimed_compute_units * stack_price * sampling_consensus_charge_permille) / 1000
//         } else {
//             num_claimed_compute_units * stack_price
//         };

//         let remaining_compute_units = num_compute_units - num_claimed_compute_units;
//         let user_refund_amount = if (security_level == SamplingConsensusSecurityLevel) {
//             (remaining_compute_units * stack_price * sampling_consensus_charge_permille) / 1000
//         } else {
//             remaining_compute_units * stack_price
//         };

//         // Handle attestation nodes
//         let num_attestation_nodes = vector::length(&attestation_nodes);
//         if (num_attestation_nodes > 0) {
//             let mut attestation_node_index = 0;
//             while (attestation_node_index < num_attestation_nodes) {
//                 let attestation_node_id = *vector::borrow(&attestation_nodes, attestation_node_index);
//                 let already_attested = {
//                     let stack_settlement_ticket = self.stack_settlement_tickets.borrow(stack_small_id);
//                     vector::contains(&stack_settlement_ticket.already_attested_nodes, &attestation_node_id)
//                 };
                
//                 if (already_attested) {
//                     let attestation_node_fee = (node_fee_amount / cross_validation_extra_nodes_count);
//                     let node_entry = self.nodes.borrow_mut(attestation_node_id);
//                     node_entry.available_fee_amount = node_entry.available_fee_amount + attestation_node_fee;
//                 } else {
//                     let confiscated_balance = self.slash_node_on_timeout(attestation_node_id);
//                     self.deposit_to_communal_treasury(confiscated_balance);
//                 };
//                 attestation_node_index = attestation_node_index + 1;
//             }
//         };

//         // Transfer funds
//         self.transfer_funds(node_fee_amount, ctx.sender(), ctx);
//         self.transfer_funds(user_refund_amount, owner, ctx);

//         // Remove stack settlement ticket and stack
//         let StackSettlementTicket {
//             id,
//             stack_small_id: _,
//             num_claimed_compute_units: _,
//             stack_merkle_leaves_vector: _,
//             already_attested_nodes: _,
//             committed_stack_proof: _,
//             dispute_settled_at_epoch: _,
//             is_in_dispute: _,
//             requested_attestation_nodes: _,
//             selected_node_id: _,
//         } = object_table::remove(&mut self.stack_settlement_tickets, stack_small_id);
//         id.delete();

//         let Stack {
//             task_small_id: _,
//             selected_node: _,
//             owner: _,
//             price: _,
//             num_compute_units: _,
//         } = table::remove(&mut self.stacks, stack_small_id);

//         // Emit event
//         sui::event::emit(StackSettlementTicketClaimedEvent {
//             stack_small_id,
//             selected_node_id,
//             attestation_nodes,
//             num_claimed_compute_units,
//             user_refund_amount,
//         });

//         index = index + 1;
//     };

//     // Distribute remaining funds to the node
//     self.withdraw_fees(node_badge, ctx);
// }

    /// Claims funds for an attestation node that participated in stack settlements.
    ///
    /// This function allows an attestation node to claim its rewards for participating in the
    /// cross-validation of stack settlements. It processes multiple settled tickets, verifies
    /// the node's participation, and distributes rewards or applies penalties accordingly.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `node_badge` - A reference to the NodeBadge of the claiming attestation node.
    /// * `settled_ticket_ids` - A vector of u64 representing the IDs of settled stack tickets to process.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Behavior
    /// For each settled stack ticket:
    /// 1. Retrieves the stack settlement ticket, stack, and associated task information.
    /// 2. Verifies that the stack requires sampling consensus security level.
    /// 3. Checks that the stack settlement is not in dispute and the dispute period has ended.
    /// 4. Verifies if the claiming node has submitted its attestation.
    /// 5. If the node submitted an attestation, it receives a reward.
    /// 6. If the node failed to submit an attestation, its collateral is slashed.
    ///
    /// After processing all tickets, the function withdraws the accumulated fees for the node.
    ///
    /// # Aborts
    /// * `EStackDoesNotRequireSamplingConsensus` - If any stack doesn't use sampling consensus.
    /// * `EStackInDispute` - If any stack settlement ticket is still in dispute.
    /// * `EStackDisputePeriodIsNotOver` - If the dispute period for any stack has not yet ended.
    ///
    /// # Important Notes
    /// - This function is specifically for attestation nodes participating in cross-validation.
    /// - It handles both reward distribution and penalty application based on the node's performance.
    /// - The function assumes that the caller has verified the node's eligibility to claim these funds.
    /// - Rewards are calculated based on the number of cross-validation nodes set in the AtomaDb.
    ///
    /// # Security Considerations
    /// - Only nodes that were selected for attestation can claim rewards through this function.
    /// - The function enforces that claims can only be made after the dispute period has ended.
    /// - Slashing of collateral for non-participation serves as a deterrent for negligent behavior.
    public entry fun claim_funds_for_attestation_node(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        settled_ticket_ids: vector<u64>,
        ctx: &mut TxContext,
    ) {
        // 1. The node claims the funds to which it was selected to attest the stacks
        let attestation_node_id = node_badge.small_id;
        let num_settled_tickets = vector::length(&settled_ticket_ids);
        let cross_validation_extra_nodes_count = self.get_cross_validation_extra_nodes_count();
        let mut index = 0;
        while (index < num_settled_tickets) {
            // 2. Fetch the stack settlement ticket, the stack and the task
            let stack_small_id = SmallId { inner: *settled_ticket_ids.borrow(index) };
            let stack_settlement_ticket = self.stack_settlement_tickets.borrow(stack_small_id);
            let stack = self.stacks.borrow(stack_small_id);
            let task = self.tasks.borrow(stack.task_small_id);

            let node_fee_amount = (stack_settlement_ticket.num_claimed_compute_units * stack.price * self.get_sampling_consensus_charge_permille()) / 1000;

            // 3. Check that the stack requires sampling consensus security level
            let security_level = task.security_level;
            if (security_level != SamplingConsensusSecurityLevel) {
                abort EStackDoesNotRequireSamplingConsensus
            };

            // 4. Check that the stack settlement ticket is not in dispute
            if (stack_settlement_ticket.is_in_dispute) {
                abort EStackInDispute
            };

            // 5. Check that the dispute_settled_at_epoch is in the past
            if (stack_settlement_ticket.dispute_settled_at_epoch >= ctx.epoch()) {
                abort EStackDisputePeriodIsNotOver
            };
            
            // 6. Retrieve the attestation node id for the current attestation node
            let attestation_nodes = stack_settlement_ticket.requested_attestation_nodes;
            let mut attestation_node_index = 0;
            while (attestation_node_index < vector::length(&attestation_nodes)) {
                if (vector::borrow(&attestation_nodes, attestation_node_index) == node_badge.small_id) {
                    break
                };
                attestation_node_index = attestation_node_index + 1;
            };

            // 7. Check if the current attestation node has submitted its attestation
            if (vector::contains(&stack_settlement_ticket.already_attested_nodes, &attestation_node_id)) {
                // 8. If the current attestation node has already submitted its attestation,
                //    add the node fee amount to the node's available fee amount
                let node_entry = self.nodes.borrow_mut(attestation_node_id);
                node_entry.available_fee_amount = node_entry.available_fee_amount + (node_fee_amount / cross_validation_extra_nodes_count); 
            } else {
                // 9. If the current attestation node has not submitted its attestation,
                //    slash the node's collateral
                let confiscated_balance = self.slash_node_on_timeout(attestation_node_id);
                self.deposit_to_communal_treasury(confiscated_balance);
            };

            index = index + 1;
        };

        withdraw_fees(self, node_badge, ctx);
    }

    public entry fun start_attestation_dispute(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        stack_small_id: u64,
        attestation_commitment: vector<u8>,
    ) {
        let stack_small_id = SmallId { inner: stack_small_id };
        let stack_settlement_ticket = self.stack_settlement_tickets.borrow_mut(stack_small_id);
        stack_settlement_ticket.is_in_dispute = true;

        sui::event::emit(StackAttestationDisputeEvent {
            stack_small_id,
            attestation_commitment,
            attestation_node_id: node_badge.small_id,
            original_node_id: stack_settlement_ticket.selected_node_id,
            original_commitment: stack_settlement_ticket.committed_stack_proof,
        });
    }

    /// The node owner announces that they can serve prompts for the given
    /// model.
    /// Fails if the model name is not registered, or if the model does not
    /// support the echelon.
    /// For information about the echelon, see `EchelonId`
    /// type.
    public entry fun add_node_to_model(
        self: &mut AtomaDb,
        node_badge: &mut NodeBadge,
        model_name: ascii::String,
        echelon: u64,
    ) {
        let model = self.models.borrow_mut(model_name);
        assert!(!model.is_disabled, EModelDisabled);

        // a node can be subscribed to a model only once irrespective of echelon
        assert!(
            !dynamic_field::exists_(&node_badge.id, model_name),
            ENodeAlreadySubscribedToModel,
        );

        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        table_vec::push_back(&mut echelon.nodes, node_badge.small_id);
        dynamic_field::add(&mut node_badge.id, model_name, echelon_id);

        sui::event::emit(NodeSubscribedToModelEvent {
            node_small_id: node_badge.small_id,
            model_name,
            echelon_id,
        });
    }

    /// We are using dynamic fields (table vec) to hold a large number of nodes.
    /// The disadvantage is that we cannot iterate over all nodes in a model.
    /// Therefore, the offchain logic needs to find the index of the node ID in
    /// the echelon nodes table vec.
    ///
    /// # Retries
    /// Note that the index can change if another node is removed from the
    /// echelon because we use swap remove.
    /// It's possible that due to a race condition this call fails because the
    /// node was moved to a different index.
    /// In such case, it's appropriate to retry the operation (with the new
    /// index).
    public entry fun remove_node_from_model(
        self: &mut AtomaDb,
        node_badge: &mut NodeBadge,
        model_name: ascii::String,
        node_index: u64,
    ) {
        let mut perhaps_echelon_id =
            dynamic_field::remove_if_exists(&mut node_badge.id, model_name);
        assert!(perhaps_echelon_id.is_some(), ENodeNotSubscribedToModel);
        let echelon_id = perhaps_echelon_id.extract();

        let model = self.models.borrow_mut(model_name);
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        assert!(echelon.nodes.length() > node_index, ENodeIndexMismatch);
        let removed_id = echelon.nodes.swap_remove(node_index);
        // as per the endpoint docs, there's a legitimate reason for this error
        // in some circumstances
        assert!(removed_id == node_badge.small_id, ENodeIndexMismatch);
    }

    /// This node will accept no more prompts.
    /// It must however finish serving open prompts if any.
    ///
    /// There's a wait period before the node can collect its collateral by
    /// calling `destroy_disabled_node`.
    public entry fun permanently_disable_node(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        ctx: &mut TxContext,
    ) {
        let node = self.nodes.borrow_mut(node_badge.small_id);
        assert!(node.was_disabled_in_epoch.is_none(), ENodeAlreadyDisabled);
        node.was_disabled_in_epoch = option::some(ctx.epoch());
    }

    /// Node operators must wait 4 epochs after `permanently_disable_node` before they can
    /// destroy the node and collect the collateral.
    /// This prevents nodes that disable themselves just before a new epoch
    /// starts and then destroy themselves immediately once it starts,
    /// potentially causing problems with open prompts without any repercussions.
    /// It also guarantees that all tasks for which the node has subscribed to
    /// have been settled for user requests.
    ///
    /// Also, 4 epochs guarantee that all the fees have been settled and are
    /// available for withdrawal, so the node is not cut short.
    ///
    /// This function assumes the node has already been disabled (see `permanently_disable_node`).
    public entry fun destroy_disabled_node(
        self: &mut AtomaDb,
        node_badge: NodeBadge,
        ctx: &mut TxContext,
    ) {
        withdraw_fees(self, &node_badge, ctx);

        let NodeEntry {
            collateral,
            mut was_disabled_in_epoch,

            last_fee_epoch: _,
            // will be zero because we force a wait before destroying a node
            // that's one epoch longer than the fee withdrawal delay
            last_fee_epoch_amount: _,
            available_fee_amount: _,
            reputation_score: _,
        } = self.nodes.remove(node_badge.small_id);

        let was_disabled_in_epoch = was_disabled_in_epoch.extract();
        assert!(was_disabled_in_epoch + 4 <= ctx.epoch(), ENodeMustWaitBeforeDestroy);

        let wallet = coin::from_balance(collateral, ctx);
        transfer::public_transfer(wallet, ctx.sender());

        let NodeBadge { id: badge_id, small_id: _ } = node_badge;
        badge_id.delete();
    }

    /// Transfers a coin object to the sender if there are some fees to be
    /// claimed for this node.
    public entry fun withdraw_fees(
        self: &mut AtomaDb,
        node_badge: &NodeBadge,
        ctx: &mut TxContext,
    ) {
        let node_id = node_badge.small_id;
        // This is a hack that moves all fees that can be withdrawn to the
        // available balance.
        // Attributing 0 fee doesn't otherwise do anything.
        self.attribute_fee_to_node(node_id, 0, ctx);

        let node = self.nodes.borrow_mut(node_id);
        let amount = node.available_fee_amount;
        if (amount > 0) {
            node.available_fee_amount = 0;
            let wallet = coin::from_balance(self.fee_treasury.split(amount), ctx);
            transfer::public_transfer(wallet, ctx.sender());
        };
    }

    public fun is_oracle(
        self: &AtomaDb,
        model_name: ascii::String,
        echelon_id: EchelonId,
        node_id: SmallId,
    ): bool {
        let model = self.models.borrow(model_name);
        let echelon = get_echelon(&model.echelons, echelon_id);
        echelon.oracles.contains(&node_id)
    }

    public fun get_permille_for_oracle_on_dispute(self: &AtomaDb): u64 {
        self.permille_for_oracle_on_dispute
    }

    public fun get_permille_for_honest_nodes_on_dispute(self: &AtomaDb): u64 {
        self.permille_for_honest_nodes_on_dispute
    }   

    // Models

    public fun get_model_echelons_if_enabled(
        self: &AtomaDb, model_name: ascii::String,
    ): &vector<ModelEchelon> {
        let model = self.models.borrow(model_name);
        assert!(!model.is_disabled, EModelDisabled);
        &model.echelons
    }

    public fun get_model_echelon(
        self: &AtomaDb, model_name: ascii::String, echelon_id: EchelonId,
    ): &ModelEchelon {
        let model = self.models.borrow(model_name);
        get_echelon(&model.echelons, echelon_id)
    }

    public fun get_model_echelon_id(self: &ModelEchelon): EchelonId { self.id }

    public fun get_model_echelon_fees(self: &ModelEchelon): (u64, u64) {
        (self.input_fee_per_token, self.output_fee_per_token)
    }

    public fun get_model_echelon_nodes(self: &ModelEchelon): &TableVec<SmallId> {
        &self.nodes
    }

    public fun get_model_echelon_performance(self: &ModelEchelon): u64 {
        self.relative_performance
    }

    public fun get_model_echelon_settlement_timeout_ms(self: &ModelEchelon): u64 {
        self.settlement_timeout_ms
    }

    public fun get_node_id(self: &NodeBadge): SmallId { self.small_id }

    public fun get_opaque_inner_id(self: SmallId): u64 { self.inner }

    public fun get_model_modality(self: &AtomaDb, model_name: ascii::String): u64 {
        self.models.borrow(model_name).modality
    }

    public fun get_cross_validation_probability_permille(self: &AtomaDb): u64 {
        self.cross_validation_probability_permille
    }

    public fun get_cross_validation_extra_nodes_count(self: &AtomaDb): u64 {
        self.cross_validation_extra_nodes_count
    }

    public fun get_sampling_consensus_charge_permille(self: &AtomaDb): u64 {
        self.sampling_consensus_charge_permille
    }

    public fun get_cross_validation_extra_nodes_charge_permille(self: &AtomaDb): u64 {
        self.cross_validation_extra_nodes_charge_permille
    }

    // Tasks 

    public fun get_task(self: &AtomaDb, task_small_id: SmallId): &Task {
        self.tasks.borrow(task_small_id)
    }

    public fun get_task_role(self: &AtomaDb, task_small_id: SmallId): TaskRole {
        self.tasks.borrow(task_small_id).role
    }

    public fun get_task_model_name(self: &AtomaDb, task_small_id: SmallId): Option<ascii::String> {
        self.tasks.borrow(task_small_id).model_name
    }

    public fun is_task_deprecated(self: &AtomaDb, task_small_id: SmallId): bool {
        self.tasks.borrow(task_small_id).is_deprecated
    }

    public fun get_task_valid_until_epoch(self: &AtomaDb, task_small_id: SmallId): Option<u64> {
        self.tasks.borrow(task_small_id).valid_until_epoch
    }

    public fun get_task_deprecated_at_epoch(self: &AtomaDb, task_small_id: SmallId): Option<u64> {
        self.tasks.borrow(task_small_id).deprecated_at_epoch
    }

    public fun get_task_optimizations(self: &AtomaDb, task_small_id: SmallId): vector<u16> {
        self.tasks.borrow(task_small_id).optimizations
    }

    public fun get_task_security_level(self: &AtomaDb, task_small_id: SmallId): u16 {
        self.tasks.borrow(task_small_id).security_level
    }

    public fun get_task_task_metrics(self: &AtomaDb, task_small_id: SmallId): TaskMetrics {
        self.tasks.borrow(task_small_id).task_metrics
    }  

    public fun get_task_subscribed_nodes(self: &AtomaDb, task_small_id: SmallId): &TableVec<NodePriceData> {
        &self.tasks.borrow(task_small_id).subscribed_nodes
    }

    // =========================================================================
    //                          Package private functions
    // =========================================================================


    public(package) fun refund_to_user(
        self: &mut AtomaDb,
        who: address,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        if (amount > 0) {
            let wallet = coin::from_balance(self.fee_treasury.split(amount), ctx);
            transfer::public_transfer(wallet, who);
        }
    }

    /// Settlement tickets are dynamic objects of this UID.
    /// Tickets must not be accessible outside of the package.
    public(package) fun get_tickets_uid_mut(self: &mut AtomaDb): &mut UID { &mut self.tickets }

    /// When a node does not respond to a prompt within the timeout, it is
    /// slashed by some ‰ amount.
    /// It's possible that the node is slashed to zero balance, in which case it
    /// won't participate in new prompts.
    public(package) fun slash_node_on_timeout(
        self: &mut AtomaDb, node_id: SmallId,
    ): Balance<TOMA> {
        let has_node = self.nodes.contains(node_id);
        if (!has_node) {
            // this node has already been removed
            return balance::zero()
        };

        let node = self.nodes.borrow_mut(node_id);
        let collateral = node.collateral.value();
        if (collateral == 0) {
            // node has already been slashed, nothing to do
            balance::zero()
        } else {
            let p = self.permille_to_slash_node_on_timeout;
            let amount_to_slash = std::u64::divide_and_round_up(
                   collateral * p,
            // -------------------
                       1000
            );
            node.collateral.split(amount_to_slash)
        }
    }

    /// Takes away all node's collateral.
    public(package) fun slash_node_on_dispute(
        self: &mut AtomaDb, node_id: SmallId,
    ): Balance<TOMA> {
        if (!self.nodes.contains(node_id)) {
            // this node has already been removed
            balance::zero()
        } else {
            self.nodes.borrow_mut(node_id).collateral.withdraw_all()
        }
    }

    /// Make sure that the fee has been inserted into the treasury!
    public(package) fun attribute_fee_to_node(
        self: &mut AtomaDb,
        node_id: SmallId,
        fee_amount: u64,
        ctx: &TxContext,
    ) {
        if (!self.nodes.contains(node_id)) {
            // this node has been deleted, unlikely scenario but perhaps at
            // some point possible? better than to error is to simply not give
            // the fee to anyone
            return
        };

        let node = self.nodes.borrow_mut(node_id);
        let current_epoch = ctx.epoch();
        if (node.last_fee_epoch == current_epoch) {
            node.last_fee_epoch_amount =
                node.last_fee_epoch_amount + fee_amount;
        } else {
            // epoch has passed, we can now unlock the previous fee
            node.available_fee_amount =
                node.available_fee_amount + node.last_fee_epoch_amount;
            node.last_fee_epoch_amount = fee_amount;
            node.last_fee_epoch = current_epoch;
        };
    }

    public(package) fun deposit_fee_to_node(
        self: &mut AtomaDb,
        node_id: SmallId,
        fee: Balance<TOMA>,
        ctx: &TxContext,
    ) {
        if (!self.nodes.contains(node_id)) {
            // this node has been deleted, unlikely scenario but perhaps at
            // some point possible? better than to error is to simply store
            // this fee for later
            self.deposit_to_communal_treasury(fee);
        } else {
            self.attribute_fee_to_node(node_id, fee.value(), ctx);
            self.fee_treasury.join(fee);
        };
    }

    public(package) fun deposit_to_communal_treasury(
        self: &mut AtomaDb, wallet: Balance<TOMA>,
    ) { self.communal_treasury.join(wallet); }

    public(package) fun deposit_to_fee_treasury(
        self: &mut AtomaDb, wallet: Balance<TOMA>,
    ) { self.fee_treasury.join(wallet); }

    /// From the given model's echelon, pick a random node.
    /// If the picked node has been slashed, remove it from the echelon and
    /// repeat until a valid node is found.
    ///
    /// In case all nodes have been slashed returns none.
    public(package) fun sample_node_by_echelon_id(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon_id: EchelonId,
        rng: &mut sui::random::RandomGenerator,
    ): Option<SmallId> {
        let model = self.models.borrow_mut(model_name);
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        sample_node(&self.nodes, &mut echelon.nodes, rng)
    }

    /// Attempts to sample `count` unique nodes from the given model's echelon.
    /// It's possible that there are not enough nodes to sample.
    public(package) fun sample_unique_nodes_by_echelon_id(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon_id: EchelonId,
        count: u64,
        rng: &mut sui::random::RandomGenerator,
    ): vector<SmallId> {
        let model = self.models.borrow_mut(model_name);
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        sample_unique_nodes(&self.nodes, &mut echelon.nodes, count, rng)
    }

    /// Same as `sample_unique_nodes_by_echelon_id` but uses echelon index instead.
    public(package) fun sample_unique_nodes_by_echelon_index(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon_index: u64,
        count: u64,
        rng: &mut sui::random::RandomGenerator,
    ): vector<SmallId> {
        let model = self.models.borrow_mut(model_name);
        let echelon = model.echelons.borrow_mut(echelon_index);
        sample_unique_nodes(&self.nodes, &mut echelon.nodes, count, rng)
    }

    /// Samples a node for a given stack based on task requirements and node eligibility.
    ///
    /// This function selects a random node from the pool of eligible nodes for a given task.
    /// A node is considered eligible if it meets the following criteria:
    /// 1. It is subscribed to the task.
    /// 2. Its price per compute unit is less than or equal to the specified price cap.
    /// 3. Its maximum number of compute units is greater than or equal to the required amount.
    /// 4. It has a positive collateral balance.
    /// 5. It is not disabled.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `task_small_id` - The SmallId of the task for which a node is being sampled.
    /// * `price_cap` - The maximum price per compute unit that a node can charge to be considered eligible.
    /// * `num_compute_units` - The minimum number of compute units a node must offer to be eligible.
    /// * `rng` - A mutable reference to a RandomGenerator for node selection.
    ///
    /// # Returns
    /// The SmallId of the randomly selected eligible node.
    ///
    /// # Aborts
    /// * `ENoNodesSubscribedToTask` - If there are no nodes subscribed to the given task.
    /// * `ENoNodesEligibleForTask` - If there are no eligible nodes for the given task and requirements.
    ///
    /// # Behavior
    /// 1. Retrieves the task and its subscribed nodes.
    /// 2. Iterates through all subscribed nodes, collecting those that meet the eligibility criteria.
    /// 3. Randomly selects one node from the pool of eligible nodes.
    ///
    /// # Important Notes
    /// - This function ensures that the selected node is both capable (in terms of compute units) 
    ///   and economically viable (in terms of price) for the given task.
    /// - The random selection provides a fair distribution of work among eligible nodes.
    /// - If no nodes are eligible, the function will abort, indicating that the task cannot be assigned
    ///   with the given constraints.
    public(package) fun sample_node_for_stack(
        self: &mut AtomaDb,
        task_small_id: SmallId,
        price_cap: u64,
        num_compute_units: u64,
        rng: &mut sui::random::RandomGenerator,
    ): SmallId {
        let task = self.tasks.borrow_mut(task_small_id);
        let subscribed_nodes = &task.subscribed_nodes;
        let nodes_count = table_vec::length(subscribed_nodes);
        if (nodes_count == 0) {
            // no nodes subscribed to this task, should not happen
            abort ENoNodesSubscribedToTask
        };

        // First, collect all eligible nodes (i.e., whose price per compute unit is less than the price cap).
        let mut eligible_nodes = vector::empty();
        let mut i = 0;
        while (i < nodes_count) {
            let node_price_data = table_vec::borrow(subscribed_nodes, i);
            let node_id = node_price_data.node_id;
            let node_price = node_price_data.price_per_compute_unit;
            let node_max_num_compute_units = node_price_data.max_num_compute_units;
            if (node_price <= price_cap 
                && node_max_num_compute_units >= num_compute_units 
                && self.nodes.contains(node_id)) 
            {
                let node = self.nodes.borrow(node_id);
                if (balance::value(&node.collateral) > 0 && option::is_none(&node.was_disabled_in_epoch)) {
                    vector::push_back(&mut eligible_nodes, node_id);
                }
            };
            i = i + 1;
        };

        // Second, randomly select one of the eligible nodes.
        let eligible_nodes_count = vector::length(&eligible_nodes);
        assert!(eligible_nodes_count > 0, ENoNodesEligibleForTask);
        let node_index = rng.generate_u64() % eligible_nodes_count;
        *vector::borrow(&eligible_nodes, node_index)
    }

    /// Samples attestation nodes for a given task and price cap.
    ///
    /// This function selects a set of nodes to attest to the results of a task execution.
    /// It filters nodes based on their price, compute capacity, collateral, and active status,
    /// then randomly selects a subset of these nodes to serve as attestation nodes.
    ///
    /// # Arguments
    /// * `self` - A reference to the AtomaDb object.
    /// * `task_small_id` - The SmallId of the task for which attestation nodes are being sampled.
    /// * `price_cap` - The maximum price per compute unit that a node can charge to be considered eligible.
    /// * `num_compute_units` - The minimum number of compute units a node must offer to be eligible.
    /// * `rng` - A mutable reference to a RandomGenerator for node selection.
    ///
    /// # Returns
    /// A vector of SmallId representing the selected attestation nodes.
    ///
    /// # Behavior
    /// 1. Retrieves the task and its subscribed nodes.
    /// 2. Filters nodes based on price cap, compute capacity, collateral, and active status.
    /// 3. If there are fewer eligible nodes than the required attestation count, returns all eligible nodes.
    /// 4. Otherwise, randomly selects the required number of attestation nodes from the eligible set.
    ///
    /// # Notes
    /// - The number of attestation nodes is determined by `get_cross_validation_extra_nodes_count()`.
    /// - Nodes are considered eligible if:
    ///   a. Their price per compute unit is less than or equal to the price cap.
    ///   b. They offer at least the required number of compute units.
    ///   c. They have positive collateral.
    ///   d. They are not disabled.
    /// - If there are not enough eligible nodes, the function returns all eligible nodes.
    ///   This ensures that stack settlement can proceed even with fewer attestation nodes than ideal.
    ///
    /// # Important
    /// This function does not guarantee the return of the exact number of nodes specified by 
    /// `get_cross_validation_extra_nodes_count()` if there are fewer eligible nodes than required.
    public(package) fun sample_attestation_nodes(
        self: &AtomaDb,
        task_small_id: SmallId,
        price_cap: u64,
        num_compute_units: u64,
        rng: &mut sui::random::RandomGenerator,
    ): vector<SmallId> {
        let task = self.tasks.borrow(task_small_id);
        let subscribed_nodes = &task.subscribed_nodes;
        let nodes_count = table_vec::length(subscribed_nodes);

        let attestation_nodes_count = self.get_cross_validation_extra_nodes_count();

        // Collect all eligible nodes (i.e., whose price per compute unit is less than the price cap).
        let mut eligible_nodes = vector::empty();
        let mut i = 0;
        while (i < nodes_count) {
            let node_price_data = table_vec::borrow(subscribed_nodes, i);
            let node_id = node_price_data.node_id;
            let node_price = node_price_data.price_per_compute_unit;
            let node_max_num_compute_units = node_price_data.max_num_compute_units; 
            if (node_price <= price_cap 
                && node_max_num_compute_units >= num_compute_units 
                && self.nodes.contains(node_id)) 
            {
                let node = self.nodes.borrow(node_id);  
                if (balance::value(&node.collateral) > 0 && option::is_none(&node.was_disabled_in_epoch)) {
                    vector::push_back(&mut eligible_nodes, node_id);
                }
            };
            i = i + 1;
        };

        if (vector::length(&eligible_nodes) < attestation_nodes_count) {
            // NOTE: we return the eligible nodes as is, since there are not enough
            // of them to sample InitialCrossValidationExtraNodesCount nodes.
            // If this is the case, we just return all the eligible nodes, instead
            // of aborting/throwing an error. Otherwise, the stack could not be claimed.
            return eligible_nodes
        };

        // Randomly select attestation nodes from the eligible nodes
        let mut selected_nodes = vector::empty();
        let eligible_nodes_count = vector::length(&eligible_nodes);
        
        while (vector::length(&selected_nodes) < attestation_nodes_count) {
            let random_index = rng.generate_u64() % eligible_nodes_count;
            let selected_node = *vector::borrow(&eligible_nodes, random_index);
            
            // Add the selected node to our result and remove it from the eligible nodes
            vector::push_back(&mut selected_nodes, selected_node);
        };

        selected_nodes
    }

    // =========================================================================
    //                          Admin functions
    // =========================================================================

    public entry fun create_manager_badge_entry(
        pub: &Publisher, ctx: &mut TxContext,
    ) {
        let badge = create_manager_badge(pub, ctx);
        transfer::transfer(badge, ctx.sender());
    }

    public fun create_manager_badge(
        pub: &Publisher, ctx: &mut TxContext,
    ): AtomaManagerBadge {
        assert!(package::from_module<ATOMA>(pub), ENotAuthorized);
        AtomaManagerBadge { id: object::new(ctx) }
    }

    /// Removes a deprecated task from the task table.
    /// It only allows to remove deprecated tasks that 
    /// were deprecated at least 2 epochs from the current task.
    public entry fun remove_deprecated_task_by_admin(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        task_small_id: u64,
        ctx: &mut TxContext,
    ) {
        let task_small_id = SmallId { inner: task_small_id };
        // Check if the task exists
        assert!(object_table::contains(&self.tasks, task_small_id), ETaskNotFound);

        let task = object_table::borrow(&self.tasks, task_small_id);
        
        // Check if the task is deprecated
        assert!(task.is_deprecated, ETaskNotDeprecated);
        
        // Check if the deprecated_at_epoch exists and if 4 epochs have passed
        assert!(option::is_some(&task.deprecated_at_epoch), ETaskNotDeprecated);
        let deprecated_epoch = *option::borrow(&task.deprecated_at_epoch);
        assert!(ctx.epoch() >= deprecated_epoch + 2, ENotEnoughEpochsPassed);

        // If all checks pass, remove the task from the object table
        // and drop the task object altogether
        let task = object_table::remove(&mut self.tasks, task_small_id);
        let Task {
            id: task_id,
            role: _,
            model_name: _,
            is_deprecated: _,
            valid_until_epoch: _,
            deprecated_at_epoch: _,
            optimizations: _,
            security_level: _,
            task_metrics: _,
            subscribed_nodes,
        } = task;

        task_id.delete();
        subscribed_nodes.drop();
    }

    /// As per the gate module:
    /// - Text2TextModality = 0
    /// - Text2ImageModality = 1
    public entry fun add_model_entry(
        self: &mut AtomaDb,
        badge: &AtomaManagerBadge,
        model_name: ascii::String,
        modality: u64,
        ctx: &mut TxContext,
    ) {
        let model = create_model(badge, model_name, modality, ctx);
        add_model(self, badge, model);
    }

    public fun add_model(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model: ModelEntry,
    ) {
        self.models.add(model.name, model);
    }

    /// For modality identifiers, see the gate module.
    public fun create_model(
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        modality: u64,
        ctx: &mut TxContext,
    ): ModelEntry {
        ModelEntry {
            id: object::new(ctx),
            name: model_name,
            modality,
            is_disabled: false,
            echelons: vector::empty()
        }
    }

    /// The fee is charged per character.
    public entry fun add_model_echelon_entry(
        self: &mut AtomaDb,
        badge: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
        input_fee_per_token: u64,
        output_fee_per_token: u64,
        relative_performance: u64,
        ctx: &mut TxContext,
    ) {
        let model = self.models.borrow_mut(model_name);
        add_model_echelon(
            badge,
            model,
            echelon,
            input_fee_per_token,
            output_fee_per_token,
            relative_performance,
            ctx,
        )
    }

    /// The fee is charged per character.
    public fun add_model_echelon(
        _: &AtomaManagerBadge,
        model: &mut ModelEntry,
        echelon: u64,
        input_fee_per_token: u64,
        output_fee_per_token: u64,
        relative_performance: u64,
        ctx: &mut TxContext,
    ) {
        assert!(input_fee_per_token > 0, EProtocolFeeCannotBeZero);
        assert!(output_fee_per_token > 0, EProtocolFeeCannotBeZero);
        assert!(relative_performance > 0, ERelativePerformanceCannotBeZero);
        let echelon_id = EchelonId { id: echelon };
        assert!(
            !contains_echelon(&model.echelons, echelon_id),
            EEchelonAlreadyExistsForModel,
        );
        vector::push_back(&mut model.echelons, ModelEchelon {
            id: echelon_id,
            input_fee_per_token,
            output_fee_per_token,
            relative_performance,
            settlement_timeout_ms: InitialSettlementTimeoutMs,
            oracles: vec_set::empty(),
            nodes: table_vec::empty(ctx),
        });
    }

    /// If this fails due to tx computation limit, you might need to remove
    /// bunch of model echelons one by one and then remove the model.
    public entry fun remove_model(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
    ) {
        let ModelEntry {
            id: model_id,
            name: _,
            modality: _,
            is_disabled: _,
            mut echelons,
        } = object_table::remove(&mut self.models, model_name);
        model_id.delete();

        let index = 0;
        let len = vector::length(&echelons);
        while (index < len) {
            let ModelEchelon {
                id: _,
                input_fee_per_token: _,
                output_fee_per_token: _,
                relative_performance: _,
                settlement_timeout_ms: _,
                oracles: _,
                nodes,
            } = vector::pop_back(&mut echelons);
            nodes.drop();
        };

        echelons.destroy_empty();
    }

    public entry fun remove_model_echelon(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
    ) {
        let model = object_table::borrow_mut(&mut self.models, model_name);
        let echelon_id = EchelonId { id: echelon };
        let ModelEchelon {
            id: _,
            input_fee_per_token: _,
            output_fee_per_token: _,
            relative_performance: _,
            settlement_timeout_ms: _,
            oracles: _,
            nodes,
        } = remove_echelon(&mut model.echelons, echelon_id);
        nodes.drop();
    }

    public entry fun disable_model(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
    ) {
        let model = self.models.borrow_mut(model_name);
        model.is_disabled = true;
    }

    public entry fun enable_model(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
    ) {
        let model = self.models.borrow_mut(model_name);
        model.is_disabled = false;
    }

    public entry fun disable_registration(
        self: &mut AtomaDb, _: &AtomaManagerBadge,
    ) { self.is_registration_disabled = true; }

    public entry fun enable_registration(
        self: &mut AtomaDb, _: &AtomaManagerBadge,
    ) { self.is_registration_disabled = false; }

    public entry fun set_required_registration_toma_collateral(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_required_collateral: u64,
    ) {
        self.registration_collateral_in_protocol_token = new_required_collateral;
    }

    public entry fun set_permille_to_slash_node_on_timeout(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_permille: u64,
    ) {
        assert!(new_permille <= 1000, ETotalPermilleMustBeLessThan1000);
        self.permille_to_slash_node_on_timeout = new_permille;
    }

    public entry fun set_permille_for_oracle_on_dispute(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_permille: u64,
    ) {
        assert!(
            new_permille + self.permille_for_honest_nodes_on_dispute <= 1000,
            ETotalPermilleMustBeLessThan1000,
        );
        self.permille_for_oracle_on_dispute = new_permille;
    }

    public entry fun set_permille_for_honest_nodes_on_dispute(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_permille: u64,
    ) {
        assert!(
            new_permille + self.permille_for_oracle_on_dispute <= 1000,
            ETotalPermilleMustBeLessThan1000,
        );
        self.permille_for_honest_nodes_on_dispute = new_permille;
    }

    /// The fee is charged per character.
    public entry fun set_model_echelon_fee(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
        new_input_fee_per_token: u64,
        new_output_fee_per_token: u64,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        echelon.input_fee_per_token = new_input_fee_per_token;
        echelon.output_fee_per_token = new_output_fee_per_token;
    }

    public entry fun add_model_echelon_oracle_node(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
        node_small_id: u64,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        let node_id = SmallId { inner: node_small_id };
        echelon.oracles.insert(node_id);
    }

    public entry fun remove_model_echelon_oracle_node(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
        node_small_id: u64,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        echelon.oracles.remove(&SmallId { inner: node_small_id });
    }

    public entry fun set_model_echelon_settlement_timeout_ms(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        model_name: ascii::String,
        echelon: u64,
        new_timeout_ms: u64,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        echelon.settlement_timeout_ms = new_timeout_ms;
    }

    public entry fun set_cross_validation_probability_permille(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_probability_permille: u64,
    ) {
        self.cross_validation_probability_permille = new_probability_permille;
    }

    public entry fun set_cross_validation_extra_nodes_count(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_extra_nodes_count: u64,
    ) {
        self.cross_validation_extra_nodes_count = new_extra_nodes_count;
    }

    public entry fun set_sampling_consensus_charge_permille(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_charge_permille: u64,
    ) {
        self.sampling_consensus_charge_permille = new_charge_permille;
    }

    public entry fun set_cross_validation_extra_nodes_charge_permille(
        self: &mut AtomaDb,
        _: &AtomaManagerBadge,
        new_charge_permille: u64,
    ) {
        self.cross_validation_extra_nodes_charge_permille = new_charge_permille;
    }

    // =========================================================================
    //                          Helpers
    // =========================================================================

    /// Helper function to find the index of a node's small_id in a TableVec
    fun find_node_index(
        subscribed_nodes: &TableVec<NodePriceData>,
        node_small_id: SmallId,
    ): Option<u64> {
        let len = table_vec::length(subscribed_nodes);
        let mut i = 0;
        while (i < len) {
            let node_id = table_vec::borrow(subscribed_nodes, i).node_id;
            if (node_id.inner == node_small_id.inner) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    fun get_echelon_mut(
        echelons: &mut vector<ModelEchelon>, id: EchelonId
    ): &mut ModelEchelon {
        let mut i = 0;
        let n = echelons.length();
        while (i < n) {
            let echelon = echelons.borrow_mut(i);
            if (echelon.id == id) {
                return echelon
            };
            i = i + 1;
        };

        abort EEchelonNotFound
    }

    fun get_echelon(
        echelons: &vector<ModelEchelon>, id: EchelonId
    ): &ModelEchelon {
        let mut i = 0;
        let n = echelons.length();
        while (i < n) {
            let echelon = echelons.borrow(i);
            if (echelon.id == id) {
                return echelon
            };
            i = i + 1;
        };

        abort EEchelonNotFound
    }

    fun contains_echelon(
        echelons: &vector<ModelEchelon>, id: EchelonId
    ): bool {
        let mut i = 0;
        let n = echelons.length();
        while (i < n) {
            let echelon = echelons.borrow(i);
            if (echelon.id == id) {
                return true
            };
            i = i + 1;
        };

        false
    }

    fun remove_echelon(
        echelons: &mut vector<ModelEchelon>, id: EchelonId
    ): ModelEchelon {
        let mut i = 0;
        let n = echelons.length();
        while (i < n) {
            let echelon = echelons.borrow(i);
            if (echelon.id == id) {
                return echelons.swap_remove(i)
            };
            i = i + 1;
        };

        abort EEchelonNotFound
    }

    /// From the given model's echelon, pick a random node.
    /// If the picked node has been slashed, remove it from the echelon and
    /// repeat until a valid node is found.
    ///
    /// In case all nodes have been slashed returns none.
    fun sample_node(
        nodes: &Table<SmallId, NodeEntry>,
        echelon_nodes: &mut TableVec<SmallId>,
        rng: &mut sui::random::RandomGenerator,
    ): Option<SmallId> {
        loop {
            let nodes_count = echelon_nodes.length();
            if (nodes_count == 0) {
                // Pathological scenario where all nodes have been slashed.
                // When user samples node, they perform clean up for us.
                // In a healthy ecosystem with enough nodes per echelon, this
                // should not happen.
                std::debug::print(&b"All echelon nodes have been slashed");
                break option::none()
            };

            let node_index = rng.generate_u64() % nodes_count;
            let node_id = *echelon_nodes.borrow(node_index);
            let has_node = nodes.contains(node_id);
            if (has_node) {
                let node = nodes.borrow(node_id);
                if (node.collateral.value() > 0
                    && node.was_disabled_in_epoch.is_none()) {
                    break option::some(node_id)
                };
            };

            // node has been slashed so remove it from the echelon
            echelon_nodes.swap_remove(node_index);
        }
    }

    /// Attempts to sample `how_many_nodes_to_sample` unique nodes from the
    /// given echelon.
    ///
    /// # Important
    /// In a pathological scenario where there are few unslashed nodes
    /// in the echelon, this function might return less nodes than requested.
    /// It's also possible there are no unslashed nodes at all, returning
    /// an empty vector.
    fun sample_unique_nodes(
        nodes: &Table<SmallId, NodeEntry>,
        echelon_nodes: &mut TableVec<SmallId>,
        how_many_nodes_to_sample: u64,
        rng: &mut sui::random::RandomGenerator,
    ): vector<SmallId> {
        assert!(how_many_nodes_to_sample > 0, ECannotSampleZeroNodes);

        let mut sampled_nodes = vector::empty();

        let total_echelon_nodes = echelon_nodes.length();
        // how many nodes do we sample from in each chunk
        let base_nodes_per_chunk = total_echelon_nodes / how_many_nodes_to_sample;
        // first this many chunks will sample from one extra node
        let total_chunks_with_extra_node_count = total_echelon_nodes % how_many_nodes_to_sample;

        // when 0 then we no longer sample from extra node
        let mut extra_node_chunks_remaining = total_chunks_with_extra_node_count;
        // We keep track of the index of the first node in the chunk.
        // This also tells us whether we iterated all the chunks or not yet
        let mut from_node_index = 0;
        while (from_node_index < total_echelon_nodes) {
            // sample in interval <from_node_index; from_node_index + nodes_to_pick_from)
            let nodes_to_pick_from = base_nodes_per_chunk
            + if (extra_node_chunks_remaining > 0) {
                extra_node_chunks_remaining = extra_node_chunks_remaining - 1;
                // add 1 because of the residual from modulo when dividing
                // total_echelon_nodes by how_many_nodes_to_sample
                1
            } else {
                0
            };

            let node_index = from_node_index
                + rng.generate_u64() % nodes_to_pick_from;

            // We want to sample from the end of the echelon for two reasons:
            // - Primarily, since we remove nodes from the echelon, we want to
            //   use swap remove and not invalidate the indices.
            // - The first `total_chunks_with_extra_node_count` chunks have one
            //   extra node, decreasing the chance of sampling of each node.
            //   Ever so slightly, it's better NOT to unsubscribe and to
            //   subscribe early.
            // Therefore we inverse the index such that 0 becomes the last
            // index, 1 the second to last and so on.
            // The rest of the algorithm is simpler if we start from the
            // beginning, so we do this transformation here.
            let inverse_node_index = total_echelon_nodes - 1 - node_index;
            let mut node_id = get_node_id_if_unslashed_or_swap_remove(
                nodes, echelon_nodes, inverse_node_index,
            );
            if (node_id.is_some()) {
                // this node is fine to use, happy path
                vector::push_back(&mut sampled_nodes, node_id.extract());
            } else {
                // this node has been slashed, we finish our chunk iterations
                // and deal with the situation later
            };

            from_node_index = from_node_index + nodes_to_pick_from;
        };

        if (sampled_nodes.length() == how_many_nodes_to_sample) {
            // happy path! the chunk iterations did not hit any slashed nodes
            sampled_nodes
        } else {
            // We sampled some slashed nodes and so we need to fill in the
            // missing nodes.

            // We remember how many times have we iterated and we retry
            // either until user requested number of nodes is sampled or
            // we hit a max number of iterations.
            // This means everything is ok in the non-pathological scenario with
            // many unslashed nodes in the echelon and does not loop forever
            // (hence exhausting the budget) in the pathological scenario.
            let mut sampled_nodes = vector::empty();
            let mut iteration = 0;
            let max_iterations = how_many_nodes_to_sample * 4;
            while (sampled_nodes.length() < how_many_nodes_to_sample
                || iteration <= max_iterations) {
                let mut node_id = sample_node(nodes, echelon_nodes, rng);

                if (node_id.is_none()) {
                    // return what we have
                    return sampled_nodes
                };

                let node_id = node_id.extract();
                if (!sampled_nodes.contains(&node_id)) {
                    sampled_nodes.push_back(node_id);
                };

                iteration = iteration + 1;
            };

            sampled_nodes
        }
    }

    fun get_node_id_if_unslashed_or_swap_remove(
        nodes: &Table<SmallId, NodeEntry>,
        echelon_nodes: &mut TableVec<SmallId>,
        node_index: u64,
    ): Option<SmallId> {
        let node_id = *echelon_nodes.borrow(node_index);
        let has_node = nodes.contains(node_id);
        if (has_node) {
            let node = nodes.borrow(node_id);
            if (node.collateral.value() > 0
                && node.was_disabled_in_epoch.is_none()) {
                return option::some(node_id)
            }
        };

        // node has been slashed so remove it from the echelon
        echelon_nodes.swap_remove(node_index);

        option::none()
    }

    /// Transfers funds from the AtomaDb's fee treasury to a specified recipient.
    ///
    /// This function is used to transfer a specified amount of funds from the AtomaDb's
    /// fee treasury to a given recipient address. It only performs the transfer if the
    /// amount is greater than zero.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `amount` - The amount of funds to transfer, in the smallest unit of the protocol token.
    /// * `recipient` - The address of the recipient who will receive the funds.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Effects
    /// - If the amount is greater than zero:
    ///   - Splits the specified amount from the fee treasury.
    ///   - Creates a new Coin object with the split amount.
    ///   - Transfers the newly created Coin to the recipient address.
    /// - If the amount is zero or negative, no transfer occurs.
    ///
    /// # Note
    /// This function uses the `coin::from_balance` and `transfer::public_transfer` functions
    /// to create and transfer the funds, respectively.
    fun transfer_funds(self: &mut AtomaDb, amount: u64, recipient: address, ctx: &mut TxContext) {
        if (amount > 0) {
            let wallet = coin::from_balance(self.fee_treasury.split(amount), ctx);
            transfer::public_transfer(wallet, recipient);
        }
    }

    #[test_only]
    /// So that we don't have to manually destroy table in the tests.
    public struct NodeEntryBin has key {
        id: UID,
        entries: Table<SmallId, NodeEntry>,
    }

    #[test]
    fun it_samples_unique_random_nodes() {
        let mut ctx = sui::tx_context::dummy();
        let mut rng = sui::random::new_generator_for_testing();

        let mut nodes = sui::table::new(&mut ctx);
        let mut echelon_nodes = sui::table_vec::empty(&mut ctx);

        while (nodes.length() < 10) {
            let node_id = SmallId { inner: nodes.length() + 1 };
            nodes.add(node_id, NodeEntry {
                collateral: sui::balance::create_for_testing(100),
                was_disabled_in_epoch: option::none(),
                last_fee_epoch: 0,
                last_fee_epoch_amount: 0,
                available_fee_amount: 0,
            });
            echelon_nodes.push_back(node_id);
        };

        let sampled_nodes =
            sample_unique_nodes(&nodes, &mut echelon_nodes, 2, &mut rng);
        assert!(sampled_nodes.length() == 2);

        // get rid of created resources
        sui::transfer::share_object(NodeEntryBin {
            id: object::new(&mut ctx),
            entries: nodes,
        });
        sui::table_vec::drop(echelon_nodes);
    }
}
