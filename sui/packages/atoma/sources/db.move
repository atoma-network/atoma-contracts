module atoma::db {
    //! At the heart of the Atoma network protocol is on-chain database.
    //! It keeps track of nodes and models.
    //!
    //! # Terminology
    //! - Node: a machine that can serve prompts.
    //! - Model: a machine learning model that can be served by nodes.
    //! - Echelon: a set of hardware and software specifications of a node.
    //!   We group specs off-chain into a single identifier.

    use atoma::atoma::ATOMA;
    use std::ascii;
    use sui::balance::Balance;
    use sui::coin::Coin;
    use sui::event;
    use sui::object_table::{Self, ObjectTable};
    use sui::package::{Self, Publisher};
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};
    use toma::toma::TOMA;

    /// How much collateral is required at the time of package publication.
    const InitialCollateralRequiredForRegistration: u64 = 1_000;
    /// Maximum time nodes can take to settle a prompt before we attempt to
    /// settle without them.
    /// This is the initial value and can change.
    const InitialSettlementTimeoutMs: u64 = 60_000;

    const ENodeRegDisabled: u64 = 0;
    const EModelDisabled: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EProtocolFeeCannotBeZero: u64 = 3;
    const ERelativePerformanceCannotBeZero: u64 = 4;
    const EEchelonNotFound: u64 = 5;
    const EEchelonAlreadyExistsForModel: u64 = 6;

    public struct NodeRegisteredEvent has copy, drop {
        /// ID of the NodeBadge object
        badge_id: ID,
        node_small_id: SmallId,
    }

    public struct NodeSubscribedToModelEvent has copy, drop {
        node_small_id: SmallId,
        model_name: ascii::String,
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
        /// We keep track of total registered nodes so that we can generate
        /// SmallId for newly registered nodes as these IDs are sequential.
        next_node_small_id: SmallId,
        /// Holds information about each node.
        nodes: Table<SmallId, NodeEntry>,
        /// Each model is represented here and stores which nodes support it.
        models: ObjectTable<ascii::String, ModelEntry>,

        // Configuration

        /// If set to true, no new nodes can be registered.
        is_registration_disabled: bool,
        /// How many protocol tokens (ignoring decimal places) are required to
        /// be collateralized by a node in order to be registered.
        ///
        /// This setting can change as each node's collateralized balance
        /// is stored in the node's account data.
        registration_collateral_in_protocol_token: u64,
    }

    /// Field of AtomaDb.
    public struct NodeEntry has store {
        collateral: Balance<TOMA>,
    }

    /// Object field of AtomaDb.
    public struct ModelEntry has key, store {
        id: UID,
        /// UTF8 model identifier.
        name: ascii::String,
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
        /// How much per request is charged by nodes in this group.
        fee_in_protocol_token: u64,
        /// The higher this number, the more likely this echelon is to be
        /// selected to serve a prompt.
        /// Read it as "relative performance compared to other echelons".
        relative_performance: u64,
        /// Which nodes support this model.
        /// We group nodes by HW and SW specs, because different echelons
        /// might end up having different outputs for the same model due to
        /// e.g. floating point arithmetics.
        /// Using a vector allows for a random access using an index.
        nodes: TableVec<SmallId>
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
            nodes: table::new(ctx),
            models: object_table::new(ctx),
            // IMPORTANT: we start from 1 because 0 is reserved
            next_node_small_id: SmallId { inner: 1 },
            is_registration_disabled: false,
            registration_collateral_in_protocol_token:
                InitialCollateralRequiredForRegistration,
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

        let node_entry = NodeEntry { collateral };
        self.nodes.add(small_id, node_entry);

        let badge_id = object::new(ctx);
        event::emit(NodeRegisteredEvent {
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
        model_name: ascii::String,
        echelon: u64,
        node_badge: &NodeBadge,
    ) {
        let model = self.models.borrow_mut(model_name);
        assert!(!model.is_disabled, EModelDisabled);

        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);

        // TODO: https://github.com/atoma-network/atoma-contracts/issues/2
        table_vec::push_back(&mut echelon.nodes, node_badge.small_id);

        event::emit(NodeSubscribedToModelEvent {
            node_small_id: node_badge.small_id,
            model_name,
        });
    }

    public fun get_model_echelons_if_enabled(
        self: &AtomaDb, model_name: ascii::String,
    ): &vector<ModelEchelon> {
        let model = self.models.borrow(model_name);
        assert!(!model.is_disabled, EModelDisabled);
        &model.echelons
    }

    public fun get_model_echelon_id(echelon: &ModelEchelon): EchelonId {
        echelon.id
    }

    public fun get_model_echelon_fee(echelon: &ModelEchelon): u64 {
        echelon.fee_in_protocol_token
    }

    public fun get_model_echelon_nodes(echelon: &ModelEchelon): &TableVec<SmallId> {
        &echelon.nodes
    }

    public fun get_model_echelon_performance(echelon: &ModelEchelon): u64 {
        echelon.relative_performance
    }

    public fun get_model_echelon_settlement_timeout_ms(echelon: &ModelEchelon): u64 {
        echelon.settlement_timeout_ms
    }

    public fun get_node_id(node: &NodeBadge): SmallId {
        node.small_id
    }

    /// Other modules can take advantage of dynamic fields attached to the UID.
    public(package) fun get_uid_mut(self: &mut AtomaDb): &mut UID {
        &mut self.id
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

    public entry fun add_model_entry(
        self: &mut AtomaDb,
        model_name: ascii::String,
        badge: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        let model = create_model(model_name, badge, ctx);
        add_model(self, model, badge);
    }

    public fun add_model(
        self: &mut AtomaDb,
        model: ModelEntry,
        _: &AtomaManagerBadge,
    ) {
        self.models.add(model.name, model);
    }

    public fun create_model(
        model_name: ascii::String,
        _: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ): ModelEntry {
        ModelEntry {
            id: object::new(ctx),
            name: model_name,
            is_disabled: false,
            echelons: vector::empty()
        }
    }

    public entry fun add_model_echelon_entry(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        fee_in_protocol_token: u64,
        relative_performance: u64,
        badge: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        let model = self.models.borrow_mut(model_name);
        add_model_echelon(
            model, echelon, fee_in_protocol_token, relative_performance, badge, ctx
        )
    }

    public fun add_model_echelon(
        model: &mut ModelEntry,
        echelon: u64,
        fee_in_protocol_token: u64,
        relative_performance: u64,
        _: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        assert!(fee_in_protocol_token > 0, EProtocolFeeCannotBeZero);
        assert!(relative_performance > 0, ERelativePerformanceCannotBeZero);
        let echelon_id = EchelonId { id: echelon };
        assert!(
            !contains_echelon(&model.echelons, echelon_id),
            EEchelonAlreadyExistsForModel,
        );
        vector::push_back(&mut model.echelons, ModelEchelon {
            id: echelon_id,
            fee_in_protocol_token,
            relative_performance,
            settlement_timeout_ms: InitialSettlementTimeoutMs,
            nodes: table_vec::empty(ctx),
        });
    }

    /// If this fails due to tx computation limit, you might need to remove
    /// bunch of model echelons one by one and then remove the model.
    public entry fun remove_model(
        self: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
    ) {
        let ModelEntry {
            id: model_id,
            name: _,
            is_disabled: _,
            mut echelons,
        } = object_table::remove(&mut self.models, model_name);
        model_id.delete();

        let index = 0;
        let len = vector::length(&echelons);
        while (index < len) {
            let ModelEchelon {
                id: _,
                fee_in_protocol_token: _,
                relative_performance: _,
                settlement_timeout_ms: _,
                nodes,
            } = vector::pop_back(&mut echelons);
            nodes.drop();
        };

        echelons.destroy_empty();
    }

    public entry fun remove_model_echelon(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        _: &AtomaManagerBadge,
    ) {
        let model = object_table::borrow_mut(&mut self.models, model_name);
        let echelon_id = EchelonId { id: echelon };
        let ModelEchelon {
            id: _,
            fee_in_protocol_token: _,
            relative_performance: _,
            settlement_timeout_ms: _,
            nodes,
        } = remove_echelon(&mut model.echelons, echelon_id);
        nodes.drop();
    }

    public entry fun disable_model(
        self: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
    ) {
        let model = self.models.borrow_mut(model_name);
        model.is_disabled = true;
    }

    public entry fun enable_model(
        self: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
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
        new_required_collateral: u64,
        _: &AtomaManagerBadge,
    ) {
        self.registration_collateral_in_protocol_token = new_required_collateral;
    }

    public entry fun set_model_echelon_fee(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        new_fee_in_protocol_token: u64,
        _: &AtomaManagerBadge,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        echelon.fee_in_protocol_token = new_fee_in_protocol_token;
    }

    public entry fun set_model_echelon_settlement_timeout_ms(
        self: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        new_timeout_ms: u64,
        _: &AtomaManagerBadge,
    ) {
        let model = self.models.borrow_mut(model_name);
        let echelon_id = EchelonId { id: echelon };
        let echelon = get_echelon_mut(&mut model.echelons, echelon_id);
        echelon.settlement_timeout_ms = new_timeout_ms;
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
                return echelons.remove(i)
            };
            i = i + 1;
        };

        abort EEchelonNotFound
    }
}
