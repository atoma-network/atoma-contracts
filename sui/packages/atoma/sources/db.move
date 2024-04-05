module atoma::db {
    //! Terminology:
    //! - Node: a machine that can serve prompts.
    //! - Model: a machine learning model that can be served by nodes.
    //! - Echelon: a set of hardware and software specifications of a node.
    //!   We group specs off-chain into a single identifier.

    use atoma::atoma::ATOMA;
    use std::ascii;
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object_table::{Self, ObjectTable};
    use sui::object::{Self, UID, ID};
    use sui::package::{Self, Publisher};
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use toma::toma::TOMA;

    /// How much collateral is required at the time of package publication.
    const InitialCollateralRequiredForRegistration: u64 = 1_000;

    const ENodeRegDisabled: u64 = 0;
    const EModelDisabled: u64 = 1;
    const ENotAuthorized: u64 = 2;

    struct NodeRegisteredEvent has copy, drop {
        /// ID of the NodeBadge object
        badge_id: ID,
        node_small_id: SmallId,
    }

    struct NodeSubscribedToModelEvent has copy, drop {
        node_small_id: SmallId,
        model_name: ascii::String,
    }

    /// Owned object.
    ///
    /// Represents authority over the package.
    struct AtomaManagerBadge has key, store {
        id: UID,
    }

    /// Owned object, transferred to each node.
    ///
    /// Proof of registration for a node.
    struct NodeBadge has key, store {
        id: UID,
        small_id: SmallId,
    }

    /// Since referring to node is ubiquitous and potentially large collections
    /// are at stake, we assign a u64 ID to each node instead of using Sui
    /// address which is 32 bytes.
    struct SmallId has store, copy, drop {
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
    struct AtomaDb has key {
        id: UID,
        /// We keep track of total registered nodes so that we can generate
        /// SmallId for newly registered nodes as these IDs are sequential.
        next_node_small_id: SmallId,
        /// Holds information about each node.
        nodes: Table<SmallId, NodeEntry>,
        /// Each model is represented here and stores which nodes support it.
        models: ObjectTable<ascii::String, MLModelEntry>,

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
    struct NodeEntry has store {
        collateral: Balance<TOMA>,
        /// TODO: figure out how this is going to be used
        public_key: vector<u8>,
    }

    /// Object field of AtomaDb.
    struct MLModelEntry has key, store {
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
        /// All operations are O(n) but we anyway mostly just need to iterate
        /// the whole thing to find all echelons that fit within a price range.
        echelons: VecMap<EchelonId, MLModelEchelon>,
    }

    /// Stored in MLModelEntry.
    struct MLModelEchelon has store {
        /// How much per request is charged by nodes in this group.
        fee_in_protocol_token: u64,
        /// The higher this number, the more likely this echelon is to be
        /// selected to serve a prompt.
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
    struct EchelonId has store, copy, drop {
        id: u64
    }

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
    }

    /// Takes collateral from the sender's wallet and transfers them the node
    /// badge.
    public entry fun register_node_entry(
        atoma: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        public_key: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let badge =
            register_node(atoma, coin::balance_mut(wallet), public_key, ctx);
        transfer::transfer(badge, tx_context::sender(ctx));
    }

    /// Splits the collateral from the sender's wallet and registers a new node.
    /// Returns a node badge.
    /// The node badge is intended to be owned by the node as a proof of
    /// registration.
    /// It can be used later to add or remove available models, delete account,
    /// etc.
    public fun register_node(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        public_key: vector<u8>,
        ctx: &mut TxContext,
    ): NodeBadge {
        assert!(!atoma.is_registration_disabled, ENodeRegDisabled);

        let collateral =
            balance::split(wallet, atoma.registration_collateral_in_protocol_token);

        let small_id = atoma.next_node_small_id;
        atoma.next_node_small_id.inner = atoma.next_node_small_id.inner + 1;

        let node_entry = NodeEntry {
            collateral,
            public_key,
        };

        table::add(&mut atoma.nodes, small_id, node_entry);

        let badge_id =  object::new(ctx);

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
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        node_badge: &NodeBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        assert!(!model.is_disabled, EModelDisabled);

        let echelon_id = EchelonId { id: echelon };
        let echelon = vec_map::get_mut(&mut model.echelons, &echelon_id);

        table_vec::push_back(&mut echelon.nodes, node_badge.small_id);

        // TODO: prevent duplicates

        event::emit(NodeSubscribedToModelEvent {
            node_small_id: node_badge.small_id,
            model_name,
        });
    }

    // =========================================================================
    //                          Admin functions
    // =========================================================================

    public entry fun create_manager_badge_entry(
        pub: &Publisher, ctx: &mut TxContext,
    ) {
        let badge = create_manager_badge(pub, ctx);
        transfer::transfer(badge, tx_context::sender(ctx));
    }

    public fun create_manager_badge(
        pub: &Publisher, ctx: &mut TxContext,
    ): AtomaManagerBadge {
        assert!(package::from_module<ATOMA>(pub), ENotAuthorized);
        AtomaManagerBadge {
            id: object::new(ctx),
        }
    }

    public entry fun add_model_entry(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        badge: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        let model = create_model(model_name, badge, ctx);
        add_model(atoma, model, badge);
    }

    public fun add_model(
        atoma: &mut AtomaDb,
        model: MLModelEntry,
        _: &AtomaManagerBadge,
    ) {
        object_table::add(&mut atoma.models, model.name, model);
    }

    public fun create_model(
        model_name: ascii::String,
        _: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ): MLModelEntry {
        MLModelEntry {
            id: object::new(ctx),
            name: model_name,
            is_disabled: false,
            echelons: vec_map::empty()
        }
    }

    public entry fun add_model_echelon_entry(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        fee_in_protocol_token: u64,
        relative_performance: u64,
        badge: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        add_model_echelon(
            model, echelon, fee_in_protocol_token, relative_performance, badge, ctx
        )
    }

    public fun add_model_echelon(
        model: &mut MLModelEntry,
        echelon: u64,
        fee_in_protocol_token: u64,
        relative_performance: u64,
        _: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ) {
        let echelon = EchelonId { id: echelon };
        vec_map::insert(&mut model.echelons, echelon, MLModelEchelon {
            fee_in_protocol_token,
            relative_performance,
            nodes: table_vec::empty(ctx),
        });
    }

    /// If this fails due to tx computation limit, you might need to remove
    /// bunch of model echelons one by one and then remove the model.
    public entry fun remove_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
    ) {
        let MLModelEntry {
            id: model_id,
            name: _,
            is_disabled: _,
            echelons,
        } = object_table::remove(&mut atoma.models, model_name);
        object::delete(model_id);

        let (_, echelons) = vec_map::into_keys_values(echelons);

        let index = 0;
        let len = vector::length(&echelons);
        while (index < len) {
            let MLModelEchelon {
                fee_in_protocol_token: _,
                relative_performance: _,
                nodes,
            } = vector::pop_back(&mut echelons);
            table_vec::drop(nodes);
        };

        vector::destroy_empty(echelons);
    }

    public entry fun remove_model_echelon(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        echelon: u64,
        _: &AtomaManagerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        let echelon_id = EchelonId { id: echelon };
        let (_, MLModelEchelon {
            fee_in_protocol_token: _,
            relative_performance: _,
            nodes,
        }) = vec_map::remove(&mut model.echelons, &echelon_id);
        table_vec::drop(nodes);
    }

    public entry fun disable_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        model.is_disabled = true;
    }

    public entry fun enable_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaManagerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        model.is_disabled = false;
    }

    public entry fun disable_registration(
        atoma: &mut AtomaDb,
        _: &AtomaManagerBadge,
    ) {
        atoma.is_registration_disabled = true;
    }

    public entry fun enable_registration(
        atoma: &mut AtomaDb,
        _: &AtomaManagerBadge,
    ) {
        atoma.is_registration_disabled = false;
    }

    public entry fun set_required_registration_toma_collateral(
        atoma: &mut AtomaDb,
        new_required_collateral: u64,
        _: &AtomaManagerBadge,
    ) {
        atoma.registration_collateral_in_protocol_token = new_required_collateral;
    }
}
