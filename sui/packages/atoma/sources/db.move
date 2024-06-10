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
    const InitialCrossValidationProbabilityPermille: u64 = 500;
    /// How many extra nodes to sample when cross validating.
    const InitialCrossValidationExtraNodesCount: u64 = 10;

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

    /// Since referring to node is ubiquitous and potentially large collections
    /// are at stake, we assign a u64 ID to each node instead of using Sui
    /// address which is 32 bytes.
    public struct SmallId has store, copy, drop {
        /// # Important
        /// We start from 1 because 0 is reserved an empty node, which might
        /// become valuable to represent in future.
        inner: u64,
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
        /// Holds information about each node.
        nodes: Table<SmallId, NodeEntry>,
        /// Each model is represented here and stores which nodes support it.
        models: ObjectTable<ascii::String, ModelEntry>,
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
            fee_treasury: balance::zero(),
            communal_treasury: balance::zero(),
            // IMPORTANT: we start from 1 because 0 is reserved
            next_node_small_id: SmallId { inner: 1 },
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
        transfer::share_object(atoma_db);

        // Create a manager badge for the package owner for convenience.
        // More can be created later.
        let atoma_manager_badge = AtomaManagerBadge {
            id: object::new(ctx),
        };
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

    /// Splits the collateral from the sender's wallet and registers a new node.
    /// Returns a node badge.
    /// The node badge is intended to be owned by the node as a proof of
    /// registration.
    /// It can be used later to add or remove available models, delete account,
    /// etc.
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

    /// You must wait 2 epochs after `permanently_disable_node` before you can
    /// destroy the node and collect the collateral.
    /// This prevents nodes that disable themselves just before a new epoch
    /// starts and then destroy themselves immediately once it starts,
    /// potentially causing problems with open prompts without any repercussions.
    ///
    /// Also, 2 epochs guarantee that all the fees have been settled and are
    /// available for withdrawal, so the node is not cut short.
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
        } = self.nodes.remove(node_badge.small_id);

        let was_disabled_in_epoch = was_disabled_in_epoch.extract();
        assert!(was_disabled_in_epoch + 2 <= ctx.epoch(), ENodeMustWaitBeforeDestroy);

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
            let amount_to_slash = sui::math::divide_and_round_up(
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
