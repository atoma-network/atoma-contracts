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
    }

    public struct TaskRegisteredEvent has copy, drop {
        task_small_id: SmallId,
    }

    public struct TaskDeprecationEvent has copy, drop {
        task_small_id: SmallId,
        /// The epoch in which the task was deprecated.
        epoch: u64,
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
        /// The (optional) address of the user who created the task
        owner: Option<address>,
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
        security_level: Option<u16>,
        /// White list of addresses that can request execution of the task
        whitelisted_requesters: Option<VecSet<address>>,
        /// Input efficiency metrics for the task (e.g. throughput, latency, cost, energy).
        /// Note: we might want to support multiple combined input efficiency metrics in the future.
        input_efficiency: Option<EfficiencyMetrics>,
        /// Output efficiency metrics for the task (e.g. throughput, latency, cost, energy)
        /// Note: we might want to support multiple combined output efficiency metrics in the future.
        output_efficiency: Option<EfficiencyMetrics>,
        /// Subscribed nodes
        subscribed_nodes: TableVec<SmallId>,
    }

    /// Systems's efficiency metrics
    public struct EfficiencyMetrics has store, copy, drop {
        /// The unit of compute for the efficiency metric
        compute_unit: u16,
        /// The value of the efficiency metric
        /// E.g. a `Task` might specify a minimum throughput of processing 100 tokens per second.
        /// In this case the value is 100.
        value: u64,
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
        /// Holds information about each node.
        nodes: Table<SmallId, NodeEntry>,
        /// Each model is represented here and stores which nodes support it.
        models: ObjectTable<ascii::String, ModelEntry>,
        /// Holds information about the registered tasks
        tasks: ObjectTable<SmallId, Task>,
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
            fee_treasury: balance::zero(),
            communal_treasury: balance::zero(),
            // IMPORTANT: we start from 1 because 0 is reserved
            next_node_small_id: SmallId { inner: 1 },
            next_task_small_id: SmallId { inner: 1 },
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

    /// Creates a new task in the Atoma network and returns a TaskBadge.
    ///
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaDb object.
    /// * `model_name` - An optional ASCII string representing the model name.
    /// * `role` - A u16 representing the task role.
    /// * `modality` - A u16 representing the task modality.
    /// * `valid_until_epoch` - An optional u64 representing the epoch until which the task is valid.
    /// * `optimizations` - An optional vector of u16 representing optimization types.
    /// * `security_level` - An optional u16 representing the security level.
    /// * `whitelisted_requesters` - An optional vector of addresses representing whitelisted requesters.
    /// * `input_efficiency_metric` - An optional vector of EfficiencyMetric representing input efficiency metrics.
    /// * `output_efficiency_metric` - An optional vector of EfficiencyMetric representing output efficiency metrics.
    /// * `performance_unit` - An optional u16 representing the performance unit.
    /// * `set_owner` - A boolean indicating whether to set the task owner.
    /// * `ctx` - A mutable reference to the transaction context.
    ///
    /// # Returns
    /// A TaskBadge object representing the created task.
    public fun create_task(
        self: &mut AtomaDb,
        role: u16,
        model_name: Option<ascii::String>,
        modality: u64,
        valid_until_epoch: Option<u64>,
        optimizations: vector<u16>,
        security_level: Option<u16>,
        input_efficiency_metric: Option<EfficiencyMetrics>,
        output_efficiency_metric: Option<EfficiencyMetrics>,
        whitelisted_requesters: Option<VecSet<address>>,
        set_owner: bool,
        ctx: &mut TxContext,
    ): TaskBadge {
        let owner = if (set_owner) {
            option::some(ctx.sender())
        } else {
            option::none()
        };
        let small_id = self.next_task_small_id;
        self.next_task_small_id.inner = self.next_task_small_id.inner + 1;

        let task = Task {
            id: object::new(ctx),
            owner: owner,
            role: TaskRole { inner: role },
            model_name,
            modality,
            is_deprecated: false,
            valid_until_epoch,
            deprecated_at_epoch: option::none(),
            optimizations,
            security_level,
            whitelisted_requesters: whitelisted_requesters,
            input_efficiency: input_efficiency_metric,
            output_efficiency: output_efficiency_metric,
            subscribed_nodes: table_vec::empty(ctx),
        };
        object_table::add(&mut self.tasks, small_id, task);
        
        sui::event::emit(TaskRegisteredEvent {
            task_small_id: small_id,
        });

        TaskBadge {
            id: object::new(ctx),
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
    public fun deprecate_task(
        self: &mut AtomaDb,
        task_badge: &mut TaskBadge,
        task_small_id: u64,
        ctx: &mut TxContext,
    ) {
        let task_small_id = SmallId { inner: task_small_id };
        assert!(self.tasks.contains(task_small_id), ETaskNotFound);

        let task = self.tasks.borrow_mut(task_badge.small_id);
        task.is_deprecated = true;
        task.deprecated_at_epoch = option::some(tx_context::epoch(ctx));

        sui::event::emit(TaskDeprecationEvent {
            task_small_id: task_badge.small_id,
            epoch: tx_context::epoch(ctx),
        });
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
        table_vec::push_back(&mut task.subscribed_nodes, node_badge.small_id);
        // Associate the task_small_id with the node badge
        dynamic_field::add(&mut node_badge.id, task_small_id, true);

        sui::event::emit(NodeSubscribedToTaskEvent {
            node_small_id: node_badge.small_id,
            task_small_id,
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

        let remove_id = task.subscribed_nodes.swap_remove(node_index);
        assert!(remove_id == node_badge.small_id, ENodeIndexMismatch);
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

        let remove_id = task.subscribed_nodes.swap_remove(node_index);
        assert!(remove_id == node_badge.small_id, ENodeIndexMismatch);
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

    // Tasks 

    public fun get_task(self: &AtomaDb, task_small_id: SmallId): &Task {
        self.tasks.borrow(task_small_id)
    }

    public fun get_task_owner(self: &AtomaDb, task_small_id: SmallId): Option<address> {
        self.tasks.borrow(task_small_id).owner
    }

    public fun get_task_role(self: &AtomaDb, task_small_id: SmallId): TaskRole {
        self.tasks.borrow(task_small_id).role
    }

    public fun get_task_model_name(self: &AtomaDb, task_small_id: SmallId): Option<ascii::String> {
        self.tasks.borrow(task_small_id).model_name
    }

    public fun get_task_modality(self: &AtomaDb, task_small_id: SmallId): u64 {
        self.tasks.borrow(task_small_id).modality
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

    public fun get_task_security_level(self: &AtomaDb, task_small_id: SmallId): Option<u16> {
        self.tasks.borrow(task_small_id).security_level
    }

    public fun get_task_whitelisted_requesters(self: &AtomaDb, task_small_id: SmallId): Option<VecSet<address>> {
        self.tasks.borrow(task_small_id).whitelisted_requesters
    }

    public fun get_task_input_efficiency(self: &AtomaDb, task_small_id: SmallId): Option<EfficiencyMetrics> {
        self.tasks.borrow(task_small_id).input_efficiency
    }  

    public fun get_task_output_efficiency(self: &AtomaDb, task_small_id: SmallId): Option<EfficiencyMetrics> {
        self.tasks.borrow(task_small_id).output_efficiency
    }

    public fun get_task_subscribed_nodes(self: &AtomaDb, task_small_id: SmallId): &TableVec<SmallId> {
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
    public entry fun remove_deprecated_task(
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
            owner: _,
            role: _,
            model_name: _,
            modality: _,
            is_deprecated: _,
            valid_until_epoch: _,
            deprecated_at_epoch: _,
            optimizations: _,
            security_level: _,
            whitelisted_requesters: _,
            input_efficiency: _,
            output_efficiency: _,
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

    // =========================================================================
    //                          Helpers
    // =========================================================================

    /// Helper function to find the index of a node's small_id in a TableVec
    fun find_node_index(
        subscribed_nodes: &TableVec<SmallId>,
        node_small_id: SmallId,
    ): Option<u64> {
        let len = table_vec::length(subscribed_nodes);
        let mut i = 0;
        while (i < len) {
            let node_id = table_vec::borrow(subscribed_nodes, i);
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
