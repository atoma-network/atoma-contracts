module node_manager::node_manager {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use toma::toma::TOMA;

    /// How much collateral is required at the time of contract publication.
    const INITIAL_TOMA_COLLATERAL: u64 = 1000;

    const ENodeRegDisabled: u64 = 0;

    /// Shared object.
    ///
    /// Determines the rules for how new nodes are registered.
    struct RegistrationConfig has key {
        id: UID,
        /// If set to true, no new nodes can be registered.
        is_disabled: bool,
        /// How many TOMA tokens (ignoring decimal places) are required to be
        /// collateralized by a node in order to be registered.
        ///
        /// This setting can change as each node's collateralized TOMA balance
        /// is stored in the node's account data.
        toma_collateral: u64,
    }

    /// Owned object, transferred to the contract publisher.
    ///
    /// Represents authority over the contract.
    struct AtomaOwner has key, store {
        id: UID,
    }

    /// Owned object, transferred to each node.
    ///
    /// Proof of registration for a node.
    struct NodeBadge has key, store {
        id: UID,
        collateral: Balance<TOMA>,
    }

    fun init(ctx: &mut TxContext) {
        let reg_config = RegistrationConfig {
            id: object::new(ctx),
            is_disabled: false,
            toma_collateral: INITIAL_TOMA_COLLATERAL,
        };
        transfer::share_object(reg_config);

        let owner = AtomaOwner {
            id: object::new(ctx),
        };
        transfer::transfer(owner, tx_context::sender(ctx));
    }

    /// Takes collateral from the sender's wallet and transfers them the node
    /// badge.
    public entry fun register_node_entry(
        reg_conf: &mut RegistrationConfig,
        wallet: &mut Coin<TOMA>,
        public_key: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let badge =
            register_node(reg_conf, coin::balance_mut(wallet), public_key, ctx);
        transfer::transfer(badge, tx_context::sender(ctx));
    }

    /// Splits the collateral from the sender's wallet and registers a new node.
    /// Returns the node badge.
    /// The node badge is intended to be owned by the node as a proof of
    /// registration.
    /// It can be used later to add or remove available models, delete account,
    /// etc.
    public fun register_node(
        reg_conf: &mut RegistrationConfig,
        wallet: &mut Balance<TOMA>,
        public_key: vector<u8>,
        ctx: &mut TxContext,
    ): NodeBadge {
        assert!(!reg_conf.is_disabled, ENodeRegDisabled);
        let collateral = balance::split(wallet, reg_conf.toma_collateral);

        // TODO: create a new node with public key in a table
        // TODO: provide HW specs

        NodeBadge {
            id: object::new(ctx),
            collateral,
        }
    }
}
