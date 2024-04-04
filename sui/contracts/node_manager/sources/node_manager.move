module node_manager::node_manager {
    use std::ascii;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object_table::{Self, ObjectTable};
    use sui::object::{Self, UID, ID};
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use toma::toma::TOMA;

    /// How much collateral is required at the time of contract publication.
    const InitialCollateralRequiredForRegistration: u64 = 1_000;

    const ENodeRegDisabled: u64 = 0;
    const EModelDisabled: u64 = 1;
    const EModelEnvironmentSpecNotSupported: u64 = 2;

    struct NodeRegisteredEvent has copy, drop {
        /// ID of the NodeBadge object
        badge_id: ID,
        node_small_id: SmallId,
    }

    struct NodeSubscribedToModel has copy, drop {
        node_small_id: SmallId,
        model_name: ascii::String,
    }

    /// Owned object, transferred to the contract publisher.
    ///
    /// Represents authority over the contract.
    struct AtomaOwnerBadge has key, store {
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
    /// Database of the contract.
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
        /// Which nodes support this model.
        /// We group nodes by HW and SW specs, because different environments
        /// might end up having different outputs for the same model due to
        /// e.g. floating point arithmetics.
        /// Using a vector allows for a random access using an index.
        ///
        /// EnvironmentSpec must be enabled by the contract owner for each
        /// model.
        /// This allows the contract owner to enable appropriate environments
        /// for each model, e.g. large models might not even support low spec
        /// environments.
        nodes_per_hw_spec: Table<EnvironmentSpec, TableVec<SmallId>>,
    }

    /// An opaque identifier for an environment.
    /// We group environments off-chain.
    /// Nodes must know at the time of registration which environment they
    /// belong to.
    /// If they chose the wrong environment, they might end up getting slashed
    /// for serving incorrect results.
    struct EnvironmentSpec has store, copy, drop {
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

        let owner = AtomaOwnerBadge {
            id: object::new(ctx),
        };
        transfer::transfer(owner, tx_context::sender(ctx));
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
    /// support the environment spec.
    /// For information about the environment spec, see `EnvironmentSpec`
    /// type.
    public entry fun add_node_to_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        environment_spec: u64,
        node_badge: &NodeBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        assert!(!model.is_disabled, EModelDisabled);

        let environment_spec = EnvironmentSpec { id: environment_spec };
        assert!(
            table::contains(&model.nodes_per_hw_spec, environment_spec),
            EModelEnvironmentSpecNotSupported,
        );

        let nodes =
            table::borrow_mut(&mut model.nodes_per_hw_spec, environment_spec);
        table_vec::push_back(nodes, node_badge.small_id);

        // TODO: prevent duplicates

        event::emit(NodeSubscribedToModel {
            node_small_id: node_badge.small_id,
            model_name,
        });
    }

    // =========================================================================
    //                          Admin functions
    // =========================================================================

    public entry fun add_model_entry(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        badge: &AtomaOwnerBadge,
        ctx: &mut TxContext,
    ) {
        let model = create_model(model_name, badge, ctx);
        add_model(atoma, model, badge);
    }

    public fun add_model(
        atoma: &mut AtomaDb,
        model: MLModelEntry,
        _: &AtomaOwnerBadge,
    ) {
        object_table::add(&mut atoma.models, model.name, model);
    }

    public fun create_model(
        model_name: ascii::String,
        _: &AtomaOwnerBadge,
        ctx: &mut TxContext,
    ): MLModelEntry {
        MLModelEntry {
            id: object::new(ctx),
            name: model_name,
            is_disabled: false,
            nodes_per_hw_spec: table::new(ctx),
        }
    }

    public entry fun add_model_environment_spec_entry(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        environment_spec: u64,
        badge: &AtomaOwnerBadge,
        ctx: &mut TxContext,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        add_model_environment_spec(model, environment_spec, badge, ctx)
    }

    public fun add_model_environment_spec(
        model: &mut MLModelEntry,
        environment_spec: u64,
        _: &AtomaOwnerBadge,
        ctx: &mut TxContext,
    ) {
        let environment_spec = EnvironmentSpec { id: environment_spec };
        if (!table::contains(&model.nodes_per_hw_spec, environment_spec)) {
            table::add(
                &mut model.nodes_per_hw_spec,
                environment_spec,
                table_vec::empty(ctx)
            );
        }
    }

    /// Unfortunately, all keys from the table need to be dropped manually
    /// because Sui's collection drops does not compose.
    /// But since both EnvironmentSpec and SmallId are droppable types, the
    /// logic to drop them is implementable ad-hoc.
    public fun remove_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaOwnerBadge,
    ): Table<EnvironmentSpec, TableVec<SmallId>> {
        let MLModelEntry {
            id: model_id,
            name: _,
            is_disabled: _,
            nodes_per_hw_spec,
        } = object_table::remove(&mut atoma.models, model_name);
        object::delete(model_id);

        nodes_per_hw_spec
    }

    public entry fun remove_model_environment_spec(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        environment_spec: u64,
        _: &AtomaOwnerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        let environment_spec = EnvironmentSpec { id: environment_spec };
        let v = table::remove(&mut model.nodes_per_hw_spec, environment_spec);
        table_vec::drop(v);
    }

    public entry fun disable_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaOwnerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        model.is_disabled = true;
    }

    public entry fun enable_model(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        _: &AtomaOwnerBadge,
    ) {
        let model = object_table::borrow_mut(&mut atoma.models, model_name);
        model.is_disabled = false;
    }

    public entry fun disable_registration(
        atoma: &mut AtomaDb,
        _: &AtomaOwnerBadge,
    ) {
        atoma.is_registration_disabled = true;
    }

    public entry fun enable_registration(
        atoma: &mut AtomaDb,
        _: &AtomaOwnerBadge,
    ) {
        atoma.is_registration_disabled = false;
    }

    public entry fun set_required_registration_toma_collateral(
        atoma: &mut AtomaDb,
        new_required_collateral: u64,
        _: &AtomaOwnerBadge,
    ) {
        atoma.registration_collateral_in_protocol_token = new_required_collateral;
    }
}
