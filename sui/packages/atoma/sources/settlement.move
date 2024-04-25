module atoma::settlement {
    use atoma::db::{EchelonId, SmallId, NodeBadge, AtomaDb};
    use std::ascii;
    use sui::balance;
    use sui::dynamic_object_field;

    const ENotAwaitingCommitment: u64 = 0;
    const EAlreadyCommitted: u64 = 1;
    const ENotReadyToSettle: u64 = 2;
    const EBlake2b256HashMustBe32Bytes: u64 = 3;
    const EIncorrectMerkleLeavesBufferLength: u64 = 4;

    /// Nodes did not agree on the settlement.
    public struct DisputeEvent has copy, drop {
        ticket_id: ID,
        /// If None then the dispute is ready to be resolved, otherwise it's
        /// Some then the oracle needs to wait for the timeout to pass.
        timeout: Option<TimeoutInfo>,
    }

    /// Some nodes did not provide their commitment in time.
    /// These new nodes have been sampled on their behalf.
    public struct NewlySampledNodesEvent has copy, drop {
        ticket_id: ID,
        new_nodes: vector<MapNodeToChunk>,
    }
    /// Informs newly sampled node about the chunk that it should
    /// submit commitment for.
    public struct MapNodeToChunk has store, copy, drop {
        node_id: SmallId,
        order: u64,
    }

    /// Dynamic object field of atoma db.
    ///
    /// Ticket that's created when user submits a new prompt.
    /// It will be used to track the status of the prompt.
    ///
    /// We use vectors for nodes info under the assumption that there won't be
    /// many nodes.
    /// In general, we want to minimize the number of nodes that are involved in
    /// the evaluation of a prompt, because of the cost of the evaluation and
    /// diminishing returns of validation value added.
    public struct SettlementTicket has key, store {
        id: UID,
        /// The name of the model that the prompt is for.
        model_name: ascii::String,
        /// The selected model echelon for the prompt.
        echelon_id: EchelonId,
        /// List of nodes that must submit commitment.
        /// The order is important.
        /// It must match the order in the prompt event emitted by the gate
        /// module.
        /// That's because the order determines the order of chunks when
        /// calculating the merkle tree.
        /// The merkle root is a hash of all the hashes of the chunks by each
        /// node in the order they are in this vector.
        all: vector<SmallId>,
        /// This vector is sorted, ie. the first element is the first node that
        /// submitted the commitment first.
        completed: vector<SmallId>,
        /// The root of the merkle tree that contains the prompt data.
        /// It's empty when the ticket is created.
        /// The first node that submits commitment will fill in this root.
        ///
        /// Each node must submit their root and the part of hash of chunk.
        /// If the final hash does not match the root, or if any node does not
        /// agree with the root, the settlement is being disputed.
        merkle_root: vector<u8>,
        /// The root must match the hash of the leaves of the merkle tree.
        /// Each leaf is a 32 byte Blake2b-256 hash of the chunk.
        /// The order is the same as the order of the nodes in the `all` vector.
        /// E.g. node `all[2]` submits their hash of the chunk and it will be
        /// stored in the index 2 * 32 = 64..96 of this vector.
        ///
        /// If nodes submit their leaves out of order, we just pad the vector
        /// with zeros.
        /// Those will be overwritten when each node submits the hash of the chunk.
        merkle_leaves: vector<u8>,
        /// The fee that was collected from the user.
        /// It will be distributed to the nodes that participated in the
        /// evaluation.
        collected_fee_in_protocol_token: u64,
        /// If any node does not agree with the first hash, the settlement is
        /// being disputed.
        ///
        /// An oracle must step in and resolve the dispute.
        is_being_disputed: bool,
        /// There's only limited time to settle the prompt.
        timeout: TimeoutInfo,
    }

    public struct TimeoutInfo has store, copy, drop {
        /// If the settlement takes more than this, the settlement can be cut
        /// short.
        /// See the `try_to_settle` endpoint.
        timeout_ms: u64,
        /// Will be relevant for timeouting.
        started_in_epoch: u64,
        /// Will be relevant for timeouting.
        started_at_epoch_timestamp_ms: u64,
    }

    public entry fun submit_commitment(
        atoma: &mut AtomaDb,
        badge: &NodeBadge,
        ticket_id: ID,
        merkle_root: vector<u8>,
        chunk_hash: vector<u8>,
    ) {
        assert!(merkle_root.length() == 32, EBlake2b256HashMustBe32Bytes);
        assert!(chunk_hash.length() == 32, EBlake2b256HashMustBe32Bytes);

        let ticket = get_settlement_ticket_mut(atoma, ticket_id);
        let node_id = badge.get_node_id();

        // check that the node is not in the completed list
        assert!(!ticket.completed.contains(&node_id), EAlreadyCommitted);

        // check that the node is in the all list
        let (contains, node_order) = ticket.all.index_of(&node_id);
        assert!(contains, ENotAwaitingCommitment);

        // if merkle root is not empty, check that it matches
        // otherwise set it
        if (ticket.merkle_root.is_empty()) {
            ticket.merkle_root = merkle_root;
        } else if (ticket.merkle_root != merkle_root) {
            ticket.is_being_disputed = true;
            sui::event::emit(DisputeEvent {
                ticket_id,
                timeout: option::some(ticket.timeout),
            });
        };

        let starts_at = node_order * 32;
        let ends_at = starts_at + 31;
        // pad the leaves if needed
        while (ends_at > ticket.merkle_leaves.length()) {
            ticket.merkle_leaves.push_back(0);
        };
        // copy the hash to its place
        let mut i = 0;
        while (i < 32) {
            *ticket.merkle_leaves.borrow_mut(starts_at + i) = chunk_hash[i];
            i = i + 1;
        };

        ticket.completed.push_back(node_id);
    }

    /// 1. All nodes have submitted their commitment, check if the expected
    ///    merkle root matches the hash of the leaves.
    ///    If it does, the ticket is settled.
    ///    If it doesn't, the ticket is being disputed.
    /// 2. The timeout to settle has passed but not all nodes have submitted
    ///    their commitment.
    ///    In this case, we slash the nodes that have not submitted their
    ///    commitment and sample other nodes that must do so in their stead.
    public entry fun try_to_settle(
        atoma: &mut AtomaDb,
        ticket_id: ID,
        ctx: &mut TxContext,
    ) {
        // We remove it so that Sui Move doesn't scream at us for not being able
        // to use mut ref to atoma.
        // If settlement can be done, the ticket will be destroyed.
        // If not, it will be again added to the db.
        let mut ticket = remove_settlement_ticket(atoma, ticket_id);

        //
        // 1.
        //
        if (ticket.completed.length() == ticket.all.length()) {
            let computed_mroot = sui::hash::blake2b256(&ticket.merkle_leaves);
            if (computed_mroot == ticket.merkle_root) {
                // happy path

                let SettlementTicket {
                    id,
                    mut completed,
                    collected_fee_in_protocol_token,

                    model_name: _,
                    echelon_id: _,
                    all: _,
                    merkle_root: _,
                    merkle_leaves: _,
                    is_being_disputed: _,
                    timeout: _,
                } = ticket;
                id.delete();

                let reward_per_node =
                    collected_fee_in_protocol_token / completed.length();

                while (!completed.is_empty()) {
                    let node_id = completed.pop_back();
                    atoma.attribute_fee_to_node(node_id, reward_per_node, ctx);
                }
            } else {
                ticket.is_being_disputed = true;
                return_settlement_ticket(atoma, ticket);
                sui::event::emit(DisputeEvent {
                    ticket_id,
                    timeout: option::none(),
                });
            }
        }
        //
        // 2.
        //
        else if (ticket.did_timeout(ctx)) {
            let mut new_nodes = vector::empty();
            let mut i = 0;
            let len = ticket.all.length();
            while (i < len) {
                let node_id = ticket.all[i];

                if (!ticket.completed.contains(&node_id)) {
                    let confiscated = atoma.slash_node_on_timeout(node_id);
                    atoma.deposit_to_communal_treasury(confiscated);

                    // sample another node to replace the slashed one
                    let mut perhaps_new_node_id = atoma
                        .sample_node_by_echelon_id(
                            ticket.model_name,
                            ticket.echelon_id,
                            ctx,
                        );

                    // if there are no more nodes to sample in this echelon
                    // we start a dispute instead
                    if (perhaps_new_node_id.is_none()) {
                        ticket.is_being_disputed = true;
                        return_settlement_ticket(atoma, ticket);
                        sui::event::emit(DisputeEvent {
                            ticket_id,
                            timeout: option::none(),
                        });
                        return
                    };

                    let new_node_id = perhaps_new_node_id.extract();

                    new_nodes.push_back(MapNodeToChunk {
                        node_id: new_node_id,
                        order: i,
                    });
                    *ticket.all.borrow_mut(i) = new_node_id;
                };

                i = i + 1;
            };

            ticket.timeout.started_in_epoch = ctx.epoch();
            ticket.timeout.started_at_epoch_timestamp_ms = ctx.epoch_timestamp_ms();
            return_settlement_ticket(atoma, ticket);

            sui::event::emit(NewlySampledNodesEvent {
                ticket_id,
                new_nodes,
            });
        }
        else {
            abort ENotReadyToSettle
        }
    }

    /// An oracle node can resolve a disputed ticket.
    ///
    /// The oracle must provide the merkle root and the leaves.
    /// If the merkle tree does not agree with the one that's in the ticket,
    /// the first node that submitted the commitment is slashed.
    /// Then we go 32 bytes by 32 bytes and check if the leaves agree with
    /// the oracle.
    /// Upon disagreement, the node collateral is all slashed.
    ///
    /// The confiscated collateral is in parts:
    /// - given to the oracle node
    /// - given to the honest nodes
    /// - deposited to the treasury
    public entry fun settle_dispute(
        atoma: &mut AtomaDb,
        node_badge: &NodeBadge,
        ticket_id: ID,
        oracle_merkle_root: vector<u8>,
        oracle_merkle_leaves: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let oracle_node_id = node_badge.get_node_id();

        let ticket = remove_settlement_ticket(atoma, ticket_id);
        assert!(ticket.is_being_disputed, ENotReadyToSettle);
        assert!(ticket.did_timeout(ctx), ENotReadyToSettle);

        let merkle_leaves_buffer_len = ticket.merkle_leaves.length();
        assert!(
            merkle_leaves_buffer_len == oracle_merkle_leaves.length(),
            EIncorrectMerkleLeavesBufferLength,
        );

        // TODO: check that the node is an oracle

        let mut confiscated_total = balance::zero();
        let mut slashed_nodes = vector::empty();

        let mut i = if (ticket.merkle_root != oracle_merkle_root) {
            let node_id = ticket.completed[0];
            confiscated_total.join(atoma.slash_node_on_dispute(node_id));
            slashed_nodes.push_back(node_id);

            // first node is slashed, no need to check its leaves
            1
        } else {
            // first node provided the correct merkle root, check its leaves
            0
        };

        while (i < merkle_leaves_buffer_len) {
            let bytes_agree = oracle_merkle_leaves[i] == ticket.merkle_leaves[i];
            if (!bytes_agree) {
                let node_index = i / 32;
                let node_id = ticket.all[node_index];
                confiscated_total.join(atoma.slash_node_on_dispute(node_id));
                // the first node won't be added twice bcs we skip it if slashed
                slashed_nodes.push_back(node_id);

                // skip to the next node
                i = (node_index + 1) * 32;
            } else {
                // check the next byte
                i = i + 1;
            }
        };

        let oracle_reward = sui::math::divide_and_round_up(
            confiscated_total.value() * atoma.get_permille_for_oracle_on_dispute(),
        // ----------------------------------------------------------------------
                                1000
        );
        atoma.deposit_fee_to_node(
            oracle_node_id,
            confiscated_total.split(oracle_reward),
            ctx,
        );

        // round down so that in any case it adds up to max the total
        let honest_nodes_extra_fee =
            confiscated_total.value() * atoma.get_permille_for_honest_nodes_on_dispute() /
        // ---------------------------------------------------------------------------
                                1000
        ;
        atoma.deposit_to_fee_treasury(confiscated_total.split(honest_nodes_extra_fee));

        // and the rest goes to the community
        atoma.deposit_to_communal_treasury(confiscated_total);

        let SettlementTicket {
            id,
            mut completed,
            collected_fee_in_protocol_token,

            model_name: _,
            echelon_id: _,
            all: _,
            merkle_root: _,
            merkle_leaves: _,
            is_being_disputed: _,
            timeout: _,
        } = ticket;
        id.delete();

        let total_fee = collected_fee_in_protocol_token + honest_nodes_extra_fee;
        let honest_nodes_len = completed.length() - slashed_nodes.length();

        if (honest_nodes_len == 0) {
            // all nodes messed up, give everything to the oracle
            atoma.attribute_fee_to_node(oracle_node_id, total_fee, ctx);
        } else {
            let reward_per_node = total_fee / honest_nodes_len;

            while (!completed.is_empty()) {
                let node_id = completed.pop_back();
                if (!slashed_nodes.contains(&node_id)) {
                    atoma.attribute_fee_to_node(node_id, reward_per_node, ctx);
                }
            }
        };
    }

    public(package) fun new_ticket(
        atoma: &mut AtomaDb,
        model_name: ascii::String,
        echelon_id: EchelonId,
        nodes: vector<SmallId>,
        collected_fee_in_protocol_token: u64,
        timeout_ms: u64,
        ctx: &mut TxContext,
    ): ID {
        let ticket = SettlementTicket {
            id: object::new(ctx),
            model_name,
            echelon_id,
            all: nodes,
            completed: vector::empty(),
            merkle_root: vector::empty(),
            merkle_leaves: vector::empty(),
            is_being_disputed: false,
            collected_fee_in_protocol_token,
            timeout: TimeoutInfo {
                timeout_ms,
                started_in_epoch: ctx.epoch(),
                started_at_epoch_timestamp_ms: ctx.epoch_timestamp_ms(),
            },
        };
        let id = object::id(&ticket);

        return_settlement_ticket(atoma, ticket);

        id
    }

    /// # How the timeout works?
    ///
    /// When creating a ticket, we store Sui epoch id and MS since epoch started.
    /// When checking for timeout, we check it against the current epoch and
    /// current MS since it started.
    /// 1. If the epoch is the same (hot path because epoch takes 24 hours),
    ////   check the diff between current ms and the stored one.
    /// 2. If the current epoch is +1 of the stored ones, the epoch just got
    ///    bumped.
    ///    We don't know exactly how long since the epoch changed unfortunately,
    ///    but because timeouts are short we give the nodes some extra time by
    ///    checking that MS since epoch started is less than the timeout MS.
    ///    This means that those prompts submitted at the border of an epoch bump
    ///    are more graceful with timeouts by having timeouts at most twice as
    ///    long.
    /// 3. The scenario where epoch is more than +1 should not happen bcs of
    ///    the aforementioned 24h epoch period being less than the timeout, but
    ///    for the sake of completeness, we can just return true.
    fun did_timeout(self: &SettlementTicket, ctx: &TxContext): bool {
        let current_epoch = ctx.epoch();
        let TimeoutInfo {
            timeout_ms,
            started_in_epoch,
            started_at_epoch_timestamp_ms,
        } = self.timeout;

        // 1.
        if (current_epoch == started_in_epoch) {
            ctx.epoch_timestamp_ms() - started_at_epoch_timestamp_ms > timeout_ms
        }
        // 2.
        else if (current_epoch == started_in_epoch + 1) {
            ctx.epoch_timestamp_ms() > timeout_ms
        }
        // 3.
        else {
            true
        }
    }

    fun get_settlement_ticket_mut(
        atoma: &mut AtomaDb,
        ticket: ID,
    ): &mut SettlementTicket {
        let uid = atoma.get_tickets_uid_mut();
        dynamic_object_field::borrow_mut(uid, ticket)
    }

    fun remove_settlement_ticket(
        atoma: &mut AtomaDb,
        ticket: ID,
    ): SettlementTicket {
        let uid = atoma.get_tickets_uid_mut();
        dynamic_object_field::remove(uid, ticket)
    }

    fun return_settlement_ticket(
        atoma: &mut AtomaDb,
        ticket: SettlementTicket,
    ) {
        let uid = atoma.get_tickets_uid_mut();
        dynamic_object_field::add(uid, object::id(&ticket), ticket)
    }
}
