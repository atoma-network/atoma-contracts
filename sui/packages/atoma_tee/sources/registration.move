module atoma_tee::registration {
    //! Key rotation and registration logic of TEE nodes on the Atoma network.

    use atoma_tee::atoma_tee::ATOMA_TEE;
    use sui::balance::Balance;
    use sui::coin::Coin;
    use sui::object::{Self, ID};
    use sui::table::Table;
    use sui::transfer::Self;
    use sui::package::{Self, Publisher};
    use toma::toma::TOMA;
    use atoma_tee::quote_verifier::verify_quote;

    /// Error code for unauthorized access
    const ENotAuthorized: u64 = 0;
    /// Error code for when a node is not yet registered
    const ENodeNotRegistered: u64 = 1;

    /// Event emitted when a new key rotation occurs in the TEE network
    /// This helps track when security keys are updated across epochs
    public struct NewKeyRotationEvent has copy, drop { 
        /// The epoch number when the key rotation occurred
        epoch: u64, 
    }

    /// Event emitted when a new node is successfully registered in the contract,
    /// after a new key rotation event is emitted.
    /// This event contains all the essential information about the registered node
    /// including its identification, epoch, and verification data
    public struct NodeRegistrationEvent has copy, drop { 
        /// The epoch number when the node registration occurred
        epoch: u64,
        /// The unique identifier of the node's badge
        badge_id: ID,
        /// A compact identifier assigned to the node for efficient referencing
        node_small_id: SmallId,
        /// The TEE public key of the registered node used for verification
        node_public_key: vector<u8>,
        /// Remote attestation data proving the node's TEE environment authenticity
        remote_attestation_bytes: vector<u8>,
    }

    /// Owned object, transferred to each node.
    ///
    /// Proof of registration for a node.
    public struct NodeBadge has key, store {
        id: UID,
        small_id: SmallId,
    }

    /// Represents a registered node's entry in the contract.
    /// This struct stores essential information about a node including its
    /// validation status, cryptographic credentials, and staked collateral.
    public struct NodeEntry has store {
        /// The last epoch number in which this node was considered valid
        last_valid_epoch: u64,
        /// The node's public key used for cryptographic verification
        registered_tee_public_key: vector<u8>,
        /// The remote attestation bytes of the node's TEE environment
        remote_attestation_bytes: vector<u8>,
        /// The amount of TOMA tokens staked as collateral by this node
        collateral: Balance<TOMA>,
        /// Whether the submitted remote attestation for the current epoch 
        /// of the node has been successfully verified by the contract
        is_verified: bool,
    }

    /// The main database structure for the contract.
    /// This struct maintains the current epoch and a registry of all valid nodes
    /// in the network.
    public struct AtomaTeeDb has key {
        /// The unique identifier of the AtomaTeeDb object.
        id: UID,
        /// The current epoch number of the network.
        /// This value is incremented during key rotation events.
        current_epoch: u64,
        /// A mapping of small node IDs to their corresponding node entries.
        /// Contains all currently valid and registered nodes in the network.
        valid_registered_nodes: Table<SmallId, NodeEntry>,
        /// The next small ID to assign to a new node.
        next_node_small_id: SmallId,
        /// A mapping of small node IDs to their corresponding node entries.
        /// Contains all currently registered nodes in the network.
        nodes: Table<SmallId, NodeEntry>,
        /// The minimum amount of collateral required to register a node.
        registration_collateral_in_protocol_token: Balance<TOMA>,
    }

    /// A compact identifier type used to efficiently reference nodes in the system.
    /// This wrapper around a u64 provides a type-safe way to handle node identifiers
    /// while maintaining minimal storage overhead.
    public struct SmallId has store, copy, drop {
        /// The underlying u64 value that represents the node identifier
        inner: u64,
    }

    /// Owned object.
    ///
    /// Represents authority over the package.
    public struct AtomaTeeManagerBadge has key, store {
        id: UID,
    }

    // =========================================================================
    //                          Admin functions
    // =========================================================================

    /// Creates and transfers an AtomaTeeManagerBadge to the sender of the transaction.
    /// This badge grants administrative privileges for managing the Atoma TEE network.
    /// 
    /// # Arguments
    /// * `pub` - The Publisher object that verifies the caller's authority
    /// * `ctx` - The transaction context containing sender information
    /// 
    /// # Permissions
    /// * Only the package publisher can create the manager badge
    /// 
    /// # Aborts
    /// * If the caller is not authorized (not the package publisher)
    public entry fun create_manager_badge_entry(
        pub: &Publisher, ctx: &mut TxContext,
    ) {
        let badge = create_manager_badge(pub, ctx);
        transfer::transfer(badge, ctx.sender());
    }

    /// Creates an AtomaTeeManagerBadge that grants administrative privileges for the Atoma TEE network.
    /// This badge is a crucial security component that controls access to administrative functions.
    /// 
    /// # Arguments
    /// * `pub` - The Publisher object that proves ownership of the package
    /// * `ctx` - The transaction context for creating new objects
    /// 
    /// # Returns
    /// * `AtomaTeeManagerBadge` - A new manager badge object with administrative privileges
    /// 
    /// # Permissions
    /// * Only the original package publisher can create this badge
    /// 
    /// # Aborts
    /// * With `ENotAuthorized` if the caller is not the package publisher
    public fun create_manager_badge(
        pub: &Publisher, ctx: &mut TxContext,
    ): AtomaTeeManagerBadge {
        assert!(package::from_module<ATOMA_TEE>(pub), ENotAuthorized);
        AtomaTeeManagerBadge { id: object::new(ctx) }
    }

    /// Returns the current epoch number from the AtomaTeeDb.
    /// The epoch represents the current time period or block range in the Atoma TEE network,
    /// which is used to coordinate network-wide state transitions and key rotations.
    /// 
    /// # Arguments
    /// * `self` - A reference to the AtomaTeeDb containing the network state
    /// 
    /// # Returns
    /// * `u64` - The current epoch number wrapped in the Epoch type
    public fun get_current_epoch(self: &AtomaTeeDb): u64 {
        self.current_epoch
    }

    /// Updates the current epoch number in the AtomaTeeDb by incrementing it by one.
    /// Epochs are fundamental time periods in the Atoma network that help coordinate
    /// network-wide state transitions, key rotations, and node validations.
    /// 
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaTeeDb containing the network state
    /// * `_` - The AtomaTeeManagerBadge proving administrative authority
    /// * `ctx` - The transaction context
    /// 
    /// # Permissions
    /// * Requires the AtomaTeeManagerBadge, restricting access to network administrators
    /// 
    /// # Effects
    /// * Increments the current epoch number by 1
    /// * Updates the network state to reflect the new epoch, by emitting a `NewKeyRotationEvent`
    public entry fun update_current_epoch(
        self: &mut AtomaTeeDb,
        _: &AtomaTeeManagerBadge,
        _: &mut TxContext,
    ) {
        self.current_epoch = self.current_epoch + 1;
        //
        sui::event::emit(NewKeyRotationEvent {
            epoch: self.current_epoch,
        });
    }

    /// Takes collateral from the sender's wallet and transfers them the node
    /// badge.
    public entry fun register_node_entry(
        self: &mut AtomaTeeDb,
        wallet: &mut Coin<TOMA>,
        public_key: vector<u8>,
        remote_attestation_bytes: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let badge = register_node(
            self,
            wallet.balance_mut(),
            public_key,
            remote_attestation_bytes,
            ctx,
        );
        transfer::transfer(badge, ctx.sender());
    }

    /// Registers a new node in the Atoma TEE network by processing collateral, assigning
    /// a unique identifier, and storing the node's credentials.
    /// 
    /// # Arguments
    /// * `self` - A mutable reference to the AtomaTeeDb containing the network state
    /// * `wallet` - A mutable reference to the Balance<TOMA> containing the collateral tokens
    /// * `public_key` - The TEE public key of the node being registered
    /// * `remote_attestation_bytes` - Remote attestation data proving the node's TEE environment
    /// * `ctx` - The transaction context
    /// 
    /// # Returns
    /// * `NodeBadge` - A badge proving node registration, containing the assigned small ID
    /// 
    /// # Effects
    /// * Takes collateral from the provided wallet balance
    /// * Assigns a unique small ID to the node
    /// * Creates and stores a new NodeEntry in the nodes table
    /// * Emits a NodeRegistrationEvent with registration details
    /// 
    /// # Aborts
    /// * If the wallet balance is insufficient for the required collateral
    public fun register_node(
        self: &mut AtomaTeeDb,
        wallet: &mut Balance<TOMA>,
        public_key: vector<u8>,
        remote_attestation_bytes: vector<u8>,
        ctx: &mut TxContext,
    ): NodeBadge {
        let collateral =
            wallet.split(self.registration_collateral_in_protocol_token.value());

        let small_id = self.next_node_small_id;
        self.next_node_small_id.inner = self.next_node_small_id.inner + 1;

        let node_entry = NodeEntry {
            collateral,
            last_valid_epoch: ctx.epoch(),
            registered_tee_public_key: public_key,
            remote_attestation_bytes,
            is_verified: false,
        };
        self.nodes.add(small_id, node_entry);

        let badge_id = object::new(ctx);
        sui::event::emit(NodeRegistrationEvent {
            epoch: self.current_epoch,
            badge_id: object::uid_to_inner(&badge_id),
            node_small_id: small_id,
            node_public_key: public_key,
            remote_attestation_bytes,
        });
        NodeBadge {
            id: badge_id,
            small_id,
        }
    }

    public entry fun submit_node_key_rotation_attestation(
        self: &mut AtomaTeeDb,
        node_badge: &mut NodeBadge,
        new_public_key: vector<u8>,
        remote_attestation_bytes: vector<u8>,
    ) {
        assert!(self.valid_registered_nodes.contains(node_badge.small_id), ENodeNotRegistered);
        let node_entry = self.valid_registered_nodes.borrow_mut(node_badge.small_id);
        // verify_quote(
        //     new_public_key,
        //     remote_attestation_bytes,
        // );

    }
}
