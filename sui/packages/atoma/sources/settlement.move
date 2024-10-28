module atoma::settlement {
    use atoma::db::{EchelonId, NodeSmallId, NodeBadge, AtomaDb};
    use std::ascii;
    use sui::balance;
    use sui::dynamic_object_field;

    /// We resample timed out nodes at most this many times before we dispute.
    /// This number needs to be quite low otherwise the user might wait too long
    /// for the prompt to be settled.
    const MaxTicketTimeouts: u64 = 3;

    /// To be able to identify the errors faster in the logs, we start the
    /// counter from a number that's leet for "error_000".
    const EBase: u64 = 312012_200;
    const ENotAwaitingCommitment: u64 = EBase + 0;
    const EAlreadyCommitted: u64 = EBase + 1;
    const ENotReadyToSettle: u64 = EBase + 2;
    const EBlake2b256HashMustBe32Bytes: u64 = EBase + 3;
    const EIncorrectMerkleLeavesBufferLength: u64 = EBase + 4;
    const ENotAnOracle: u64 = EBase + 5;
    const ETicketMustHaveNodes: u64 = EBase + 6;
    /// There can only be one node sampled at first for cross validation to work.
    const ECrossValidationSupportedForOneNodeOnly: u64 = EBase + 7;

    /// Node is the first to submit a commitment for a given ticket
    public struct FirstSubmissionEvent has copy, drop {
        ticket_id: ID,
        node_id: NodeSmallId,
    }

    /// Nodes did not agree on the settlement.
    public struct DisputeEvent has copy, drop {
        ticket_id: ID,
        /// If None then the dispute is ready to be resolved.
        /// If Some then the oracle needs to wait for the timeout because other
        /// nodes might still submit their commitment.
        /// If the oracle would attempt to resolve the dispute before the
        /// timeout, it would be unfair to the nodes that are still in the
        /// process of submitting their commitment.
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
        node_id: NodeSmallId,
        order: u64,
    }

    /// When a prompt is settled, this event is emitted.
    public struct SettledEvent has copy, drop {
        ticket_id: ID,
        /// If there was a dispute, this is the oracle that resolved it.
        oracle_node_id: Option<NodeSmallId>,
    }

    /// Retry settlement when there are at least this many nodes in the echelon.
    public struct RetrySettlementEvent has copy, drop {
        ticket_id: ID,
        how_many_nodes_in_echelon: u64,
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
    ///
    /// # Randomness safety
    /// It's important that no other onchain package can tell whether a ticket
    /// with a given ID is settled or not.
    /// Otherwise asserter could, during cross validation, fail unless cross
    /// validation is not triggered.
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
        ///
        /// # Randomness safety
        /// It's important that this vector cannot be read outside of this
        /// package so that txs cannot be aborted unless specific nodes were
        /// sampled.
        all: vector<NodeSmallId>,
        /// This vector is sorted, ie. the first element is the first node that
        /// submitted the commitment first.
        completed: vector<NodeSmallId>,
        /// The root of the merkle tree that contains the prompt data.
        /// It's empty when the ticket is created.
        /// The first node that submits commitment will fill in this root.
        ///
        /// Each node must submits the root and its sampled position in an n-ary
        /// tree.
        /// N is given by the number of nodes that must submit commitment.
        /// Its sampled position, called a chunk is, `H(output, node_position)`.
        /// The root is calculated as a hash of all the chunks:
        /// `H(H(output, 1), H(output, 2), …, H(output, n))`
        /// where `n` is the number of sampled nodes, ie. `all.len()`.
        ///
        /// If the final hash does not match the root, or if any node does not
        /// agree with the root, the settlement is being disputed.
        merkle_root: vector<u8>,
        /// The root must match the hash of the leaves of the merkle tree.
        /// Each leaf is a 32 byte Blake2b-256 hash of the output plus nodes
        /// positional index.
        /// The order is the same as the order of the nodes in the `all` vector.
        /// E.g. node `all[2]` submits their hash of the output appended with
        /// number "2" and it will be
        /// stored in the index 2 * 32 = 64..96 of this vector.
        ///
        /// If nodes submit their leaves out of order, we just pad the vector
        /// with zeros.
        /// Those will be overwritten when each node submits the hash of the chunk.
        merkle_leaves: vector<u8>,
        /// The fee per input token at the time of the prompt submission.
        input_fee_per_token: u64,
        /// The fee per output token at the time of the prompt submission.
        output_fee_per_token: u64,
        /// The fee that was collected from the user on prompt submission.
        /// It is higher than what should actually be paid to the nodes because
        /// we overestimate the number of tokens.
        /// The nodes with their commitment will provide the number of tokens
        /// that should be paid to them, the rest being refunded to the user.
        ///
        /// It will be distributed to the nodes that participated in the
        /// evaluation.
        collected_fee_in_protocol_token: u64,
        /// The address of the account that created the prompt.
        /// Any refund will be sent to this address.
        payer: address,
        /// The first node populates this field.
        /// If any other node disagrees with the number of tokens, the ticket
        /// is disputed.
        input_tokens_count: Option<u64>,
        /// The first node populates this field.
        /// If any other node disagrees with the number of tokens, the ticket
        /// is disputed.
        output_tokens_count: Option<u64>,
        /// If any node does not agree with the first hash, the settlement is
        /// being disputed.
        ///
        /// An oracle must step in and resolve the dispute.
        is_being_disputed: bool,
        /// If the reason for the dispute is that the number of input and/or
        /// output tokens does not agree between the first node and some other,
        /// we store the ID of the node that disagrees.
        ///
        /// During the dispute resolution, the oracle will check if the number
        /// of tokens is correct.
        /// If it is, the node that disagreed will be slashed.
        /// If it is not, the node that submitted the commitment first will be
        /// slashed.
        ///
        /// # Important
        /// Can only be some if `is_being_disputed` is true.
        token_counts_disputed_by: Option<NodeSmallId>,
        /// There's only limited time to settle the prompt.
        timeout: TimeoutInfo,
        /// Can only be some if there is exactly one node sampled so far.
        /// Possibly invokes cross validation when the node submit their
        /// commitment.
        cross_validation: Option<CrossValidation>
    }

    /// A settlement ticket can have some cross validation chance.
    /// This means that with the given probability we will invite once
    /// the provided number of extra nodes to validate the prompt.
    ///
    /// The goal of this feature is to sample just one node and with some
    /// probability sample more, which makes cheating by the sampled node
    /// uneconomic.
    ///
    /// If cross validation is required, the original `all` and `completed`
    /// vectors are expanded, the `merkle_root` and the `merkle_leaves` keep
    /// the value submitted by the node one.
    /// That's because the node is instructed to submit the commitment AS IF
    /// there were already `how_many_extra_nodes + 1` nodes.
    ///
    /// If cross validation is NOT required, then we don't check any hashes
    /// as there's no point because all data has been submitted by one node.
    /// We just accept the result at face value.
    public struct CrossValidation has store, copy, drop {
        /// We randomly generate a number between 0 and 1000 and if the number
        /// is lower than this, we sample extra nodes.
        probability_permille: u64,
        /// This many extra nodes get sampled.
        how_many_extra_nodes: u64,
    }

    public struct TimeoutInfo has store, copy, drop {
        /// How many times has the settlement timed out.
        /// Once this reaches a threshold `MaxTicketTimeouts`, the ticket
        /// will be disputed.
        timed_out_count: u64,
        /// If the settlement takes more than this, the settlement can be cut
        /// short.
        /// See the `try_to_settle` endpoint.
        timeout_ms: u64,
        /// Will be relevant for timeouting.
        started_in_epoch: u64,
        /// Will be relevant for timeouting.
        started_at_epoch_timestamp_ms: u64,
    }

    #[allow(lint(public_random))]
    /// Find the ticket ID in the emitted prompt event.
    /// Based on the node's order in the list of nodes that must submit
    /// commitment, the node will know which chunk to submit.
    /// A chunk is `H(output, node_position)`.
    ///
    /// We use Blake2b-256 for hashing the chunks.
    ///
    /// # Input and output tokens notes
    /// - for text2text, the input tokens contain both preprompt and prompt
    /// - for text2image, output tokens count should equal to the number
    ///   of generated images
    ///
    /// # Randomness safety
    /// See `try_to_settle` for more info.
    public entry fun submit_commitment(
        atoma: &mut AtomaDb,
        badge: &NodeBadge,
        ticket_id: ID,
        input_tokens_count: u64,
        output_tokens_count: u64,
        merkle_root: vector<u8>,
        chunk_hash: vector<u8>,
        random: &sui::random::Random,
        ctx: &mut TxContext,
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

        if (ticket.completed.is_empty()) {
            // if node is submitting a commitment for the first time,
            // emit an event informing it should manage output

            ticket.input_tokens_count = option::some(input_tokens_count);
            ticket.output_tokens_count = option::some(output_tokens_count);
            sui::event::emit(FirstSubmissionEvent {
                ticket_id,
                node_id,
            })
        } else if (!ticket.is_being_disputed) {
            let input_tokens_count_match =
                ticket.input_tokens_count.borrow() == input_tokens_count;
            let output_tokens_count_match =
                ticket.output_tokens_count.borrow() == output_tokens_count;

            if (!input_tokens_count_match || !output_tokens_count_match) {
                // this node does not agree with the first node, let oracle
                // resolve the dispute

                ticket.token_counts_disputed_by = option::some(node_id);
                ticket.is_being_disputed = true;
                sui::event::emit(DisputeEvent {
                    ticket_id,
                    timeout: option::some(ticket.timeout),
                });
            }
        };

        // if merkle root is not empty, check that it matches
        // otherwise set it
        if (ticket.merkle_root.is_empty()) {
            ticket.merkle_root = merkle_root;
        } else if (!ticket.is_being_disputed
            && ticket.merkle_root != merkle_root) {
            ticket.is_being_disputed = true;
            sui::event::emit(DisputeEvent {
                ticket_id,
                timeout: option::some(ticket.timeout),
            });
        };

        let starts_at = node_order * 32;
        let ends_at = starts_at + 31;
        // pad the leaves if needed
        while (ends_at >= ticket.merkle_leaves.length()) {
            ticket.merkle_leaves.push_back(0);
        };
        // copy the hash to its place
        let mut i = 0;
        while (i < 32) {
            *ticket.merkle_leaves.borrow_mut(starts_at + i) = chunk_hash[i];
            i = i + 1;
        };

        ticket.completed.push_back(node_id);

        // if we are ready to settle, do it
        try_to_settle(atoma, ticket_id, random, ctx);
    }

    #[allow(lint(public_random))]
    /// Permission-less endpoint.
    ///
    /// It won't panic if the ticket is not ready to settle, rather a no-op.
    /// This allows for these patterns:
    /// - We try to settle on commitment submission.
    /// - Each node along with submitting the commitment tries to settle.
    /// - Some arbitrary party calls this at the appropriate time.
    ///
    /// # Branches
    /// 1. All nodes have submitted their commitment.
    ///    a) If probabilistic cross validation is enabled and the node provided
    ///       it's commitment, we either accept it or sample more nodes, randomly.
    ///    b) If the expected merkle root matches the hash of the leaves, then
    ///       the ticket is settled.
    ///    c) If it doesn't, the ticket is being disputed.
    /// 2. The timeout to settle has passed but not all nodes have submitted
    ///    their commitment.
    ///    a) Maximum timeout attempts reached, the ticket is being disputed.
    ///    b) We slash the nodes that have not submitted their
    ///       commitment and sample other nodes that must do so in their stead.
    ///       If the ticket is already being disputed, skip this step.
    ///
    /// # Randomness safety
    /// There are two ways we use randomness: (1) sampling nodes and (2) rolling
    /// if cross validation should be done.
    ///
    /// The first one is ok because the submitter of this tx does not know until
    /// the tx is over which nodes are sampled.
    ///
    /// The second one is ok because there are no getters for the ticket that
    /// are publicly accessible.
    /// Additionally, if `try_to_settle` is called on non existing ticket, it
    /// fails the tx.
    /// Therefore, an asserter cannot know if the ticket is settled or not,
    /// because if it's settled and they try to settle it again, the tx will
    /// fail.
    /// And if the cross validation is triggered there is no way to cheat.
    public entry fun try_to_settle(
        atoma: &mut AtomaDb,
        ticket_id: ID,
        random: &sui::random::Random,
        ctx: &mut TxContext,
    ) {
        let mut rng = random.new_generator(ctx);

        // We remove it so that Sui Move doesn't scream at us for not being able
        // to use mut ref to atoma.
        // If settlement can be done, the ticket will be destroyed.
        // If not, it will be again added to the db.
        let mut ticket = remove_settlement_ticket(atoma, ticket_id);
        let sampled_nodes_count = ticket.all.length();

        //
        // 1.
        //
        if (!ticket.is_being_disputed
            && ticket.completed.length() == sampled_nodes_count) {
            // a)
            if (ticket.cross_validation.is_some()) {
                let CrossValidation {
                    probability_permille,
                    how_many_extra_nodes,
                } = ticket.cross_validation.extract();

                // with the given chance sample more nodes
                let should_sample_more =
                    probability_permille < rng.generate_u64() % 1000;

                if (should_sample_more) {
                    sample_extra_nodes_for_cross_validation(
                        atoma, ticket, how_many_extra_nodes, &mut rng, ctx,
                    );
                } else {
                    // this time we don't sample more nodes
                    ticket_ok_so_distribute_fees(atoma, ticket, ctx);
                }
            }
            // b)
            else if (ticket.merkle_root ==
                sui::hash::blake2b256(&ticket.merkle_leaves) // computed root
            ) {
                // happy path
                ticket_ok_so_distribute_fees(atoma, ticket, ctx);
            }
            // c)
            else {
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
        else if (ticket.did_timeout(ctx) && !ticket.is_being_disputed) {
            // a)
            if (ticket.max_timeout_attempts_reached()) {
                ticket.is_being_disputed = true;
                return_settlement_ticket(atoma, ticket);
                sui::event::emit(DisputeEvent {
                    ticket_id,
                    timeout: option::none(),
                });
            }
            // b
            else {
                let new_nodes =
                    replace_timed_out_nodes(&mut ticket, atoma, &mut rng);

                if (new_nodes.is_empty()) {
                    // if there are no more nodes to sample in this echelon
                    // we start a dispute instead
                    ticket.is_being_disputed = true;
                    return_settlement_ticket(atoma, ticket);
                    sui::event::emit(DisputeEvent {
                        ticket_id,
                        timeout: option::none(),
                    });
                } else {
                    ticket.timeout.started_in_epoch = ctx.epoch();
                    ticket.timeout.started_at_epoch_timestamp_ms =
                        ctx.epoch_timestamp_ms();
                    return_settlement_ticket(atoma, ticket);

                    sui::event::emit(NewlySampledNodesEvent {
                        ticket_id,
                        new_nodes,
                    });
                }
            }

        }
        else {
            // nothing to do, but exit with a success code anyway
            return_settlement_ticket(atoma, ticket);
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
        oracle_input_tokens_count: u64,
        oracle_output_tokens_count: u64,
        oracle_merkle_root: vector<u8>,
        oracle_merkle_leaves: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let oracle_node_id = node_badge.get_node_id();

        let ticket = remove_settlement_ticket(atoma, ticket_id);
        // we do DISPUTED && TIMEOUT because:
        // - disputed alone is not enough, we want to give the appropriate time
        // to all the nodes to submit their commitment, otherwise they'd be
        // unjustly slashed.
        // - timeout alone is not enough because we might want to pick another
        // node to submit the commitment instead
        assert!(ticket.is_being_disputed, ENotReadyToSettle);
        assert!(ticket.did_timeout(ctx), ENotReadyToSettle);

        let merkle_leaves_buffer_len = ticket.merkle_leaves.length();
        assert!(
            merkle_leaves_buffer_len == oracle_merkle_leaves.length(),
            EIncorrectMerkleLeavesBufferLength,
        );

        assert!(
            atoma.is_oracle(
                ticket.model_name,
                ticket.echelon_id,
                oracle_node_id,
            ),
            ENotAnOracle,
        );

        let SettlementTicket {
            id,
            mut completed,
            all,
            collected_fee_in_protocol_token: collected_fee,
            merkle_root: ticket_merkle_root,
            merkle_leaves: ticket_merkle_leaves,
            payer,
            input_fee_per_token,
            mut input_tokens_count,
            output_fee_per_token,
            mut output_tokens_count,
            mut token_counts_disputed_by,

            model_name: _,
            echelon_id: _,
            is_being_disputed: _,
            timeout: _,
            cross_validation: _,
        } = ticket;
        id.delete();

        let mut confiscated_total = balance::zero();
        let mut slashed_nodes = vector::empty();

        let merkle_root_match = ticket_merkle_root == oracle_merkle_root;
        let token_counts_match =
            input_tokens_count.extract() == oracle_input_tokens_count
            && output_tokens_count.extract() == oracle_output_tokens_count;

        // if the first node did not provide the correct merkle root or
        // token counts, slash it
        let mut i = if (!merkle_root_match || !token_counts_match) {
            let node_id = completed[0];
            confiscated_total.join(atoma.slash_node_on_dispute(node_id));
            slashed_nodes.push_back(node_id);

            // first node is slashed, no need to check its leaves
            32
        } else {
            // first node provided the correct merkle root, check its leaves
            0
        };

        while (i < merkle_leaves_buffer_len) {
            let bytes_agree = oracle_merkle_leaves[i] == ticket_merkle_leaves[i];
            if (!bytes_agree) {
                let node_index = i / 32;
                let node_id = all[node_index];
                let confiscated_from_node = if (!completed.contains(&node_id)) {
                    // the node did not submit the commitment in time
                    atoma.slash_node_on_timeout(node_id)
                } else {
                    // the node submitted wrong commitment
                    atoma.slash_node_on_dispute(node_id)
                };
                confiscated_total.join(confiscated_from_node);

                // the first node won't be added twice bcs we skip it if slashed
                slashed_nodes.push_back(node_id);
                // skip to the next node
                i = (node_index + 1) * 32;
            } else {
                // check the next byte
                i = i + 1;
            }
        };

        if (token_counts_disputed_by.is_some()) {
            let node_id = token_counts_disputed_by.extract();

            if (token_counts_match && !slashed_nodes.contains(&node_id)) {
                // the node was wrong about the token counts, we slash it if not
                // already slashed
                let confiscated_from_node = atoma.slash_node_on_dispute(node_id);
                confiscated_total.join(confiscated_from_node);
                slashed_nodes.push_back(node_id);
            } else {
                // A) the node was right about the token counts and
                // the FIRST node has already been slashed above
                //
                // OR
                //
                // B) the node was wrong but already slashed above
            };
        };

        let oracle_reward = std::u64::divide_and_round_up(
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

        // we can extract because the first node submits the counts
        // and there is always at least one node
        let exact_fee = all.length() *
            (
                input_fee_per_token * input_tokens_count.extract()
                + output_fee_per_token * output_tokens_count.extract()
            );

        let total_fee = honest_nodes_extra_fee + if (exact_fee >= collected_fee) {
            // unlikely that it would be higher because we overestimate

            collected_fee
        } else {
            let refund_amount = collected_fee - exact_fee;
            atoma.refund_to_user(payer, refund_amount, ctx);

            exact_fee
        };

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

        sui::event::emit(SettledEvent {
            ticket_id,
            oracle_node_id: option::some(oracle_node_id),
        });
    }

    // =========================================================================
    //                              Package private functions
    // =========================================================================

    public(package) fun new_ticket(
        model_name: ascii::String,
        echelon_id: EchelonId,
        nodes: vector<NodeSmallId>,
        input_fee_per_token: u64,
        output_fee_per_token: u64,
        collected_fee_in_protocol_token: u64,
        timeout_ms: u64,
        ctx: &mut TxContext,
    ): SettlementTicket {
        assert!(!nodes.is_empty(), ETicketMustHaveNodes);
        SettlementTicket {
            id: object::new(ctx),
            model_name,
            echelon_id,
            all: nodes,
            completed: vector::empty(),
            merkle_root: vector::empty(),
            merkle_leaves: vector::empty(),
            is_being_disputed: false,
            input_fee_per_token,
            output_fee_per_token,
            collected_fee_in_protocol_token,
            // provided by the first node
            input_tokens_count: option::none(),
            // provided by the first node
            output_tokens_count: option::none(),
            // only set when any node does not agree with the first node
            token_counts_disputed_by: option::none(),
            payer: ctx.sender(),
            timeout: TimeoutInfo {
                timed_out_count: 0,
                timeout_ms,
                started_in_epoch: ctx.epoch(),
                started_at_epoch_timestamp_ms: ctx.epoch_timestamp_ms(),
            },
            cross_validation: option::none(),
        }
    }

    public(package) fun request_cross_validation(
        self: &mut SettlementTicket,
        probability_permille: u64,
        how_many_extra_nodes: u64,
    ) {
        assert!(self.all.length() == 1, ECrossValidationSupportedForOneNodeOnly);

        let cross_validation = CrossValidation {
            probability_permille,
            how_many_extra_nodes,
        };
        self.cross_validation = option::some(cross_validation);
    }

    public(package) fun ticket_uid(self: &mut SettlementTicket): &mut UID {
        &mut self.id
    }

    public(package) fun return_settlement_ticket(
        atoma: &mut AtomaDb,
        ticket: SettlementTicket,
    ) {
        let uid = atoma.get_tickets_uid_mut();
        dynamic_object_field::add(uid, object::id(&ticket), ticket)
    }

    // =========================================================================
    //                          Helpers
    // =========================================================================

    /// Ticket's happy path.
    /// If everything is in order (caller checked) then this method destroys
    /// the ticket and gives the participating nodes their reward.
    fun ticket_ok_so_distribute_fees(
        atoma: &mut AtomaDb, ticket: SettlementTicket, ctx: &mut TxContext,
    ) {
        let SettlementTicket {
            id,
            mut completed,
            collected_fee_in_protocol_token: collected_fee,
            payer,
            input_fee_per_token,
            mut input_tokens_count,
            output_fee_per_token,
            mut output_tokens_count,

            token_counts_disputed_by: _, // is for sure none
            model_name: _,
            echelon_id: _,
            all: _,
            merkle_root: _,
            merkle_leaves: _,
            is_being_disputed: _,
            timeout: _,
            cross_validation: _,
        } = ticket;
        let ticket_id = object::uid_to_inner(&id);
        id.delete();

        // we can extract because the first node submits the counts
        // and there is always at least one node
        let exact_fee = completed.length() *
            (
                input_fee_per_token * input_tokens_count.extract()
                + output_fee_per_token * output_tokens_count.extract()
            );

        let reward_per_node = if (exact_fee >= collected_fee) {
            // unlikely that it would be higher because we overestimate

            collected_fee / completed.length()
        } else {
            let refund_amount = collected_fee - exact_fee;
            atoma.refund_to_user(payer, refund_amount, ctx);

            exact_fee / completed.length()
        };

        while (!completed.is_empty()) {
            let node_id = completed.pop_back();
            atoma.attribute_fee_to_node(node_id, reward_per_node, ctx);
        };

        sui::event::emit(SettledEvent {
            ticket_id,
            oracle_node_id: option::none(),
        });
    }

    /// There's a chance that probabilistic validation triggers more node
    /// sampling which is what happens in this method.
    /// We sample bunch of new nodes and emit an event about it.
    /// At this stage of the settlement, there's a submitted merkle root and
    /// the first chunk hash.
    ///
    /// If we cannot sample more nodes right now, we store this info on the
    /// ticket and next time `try_to_settle` is called, we will retry until
    /// there are some nodes.
    fun sample_extra_nodes_for_cross_validation(
        atoma: &mut AtomaDb,
        mut ticket: SettlementTicket,
        how_many_extra_nodes: u64,
        rng: &mut sui::random::RandomGenerator,
        ctx: &TxContext,
    ) {
        let ticket_id = object::id(&ticket);

        ticket.timeout.started_in_epoch = ctx.epoch();
        ticket.timeout.started_at_epoch_timestamp_ms =
            ctx.epoch_timestamp_ms();

        let mut new_nodes = atoma.sample_unique_nodes_by_echelon_id(
            ticket.model_name,
            ticket.echelon_id,
            // we sample one extra in case the asserter node is sampled
            how_many_extra_nodes + 1,
            rng,
        );

        let (has_asserter, asserter_index) = new_nodes.index_of(&ticket.all[0]);
        if (has_asserter) {
            new_nodes.swap_remove(asserter_index);
        } else if (new_nodes.length() == how_many_extra_nodes + 1) {
            // we added plus one above but asserter was not in the list, so we
            // remove one node
            new_nodes.pop_back();
        };

        if (how_many_extra_nodes > new_nodes.length()) {
            // not enough nodes to sample right now, let's
            // wait until more nodes join the echelon
            ticket.cross_validation = option::some(CrossValidation {
                // we want to retry
                probability_permille: 1000,
                how_many_extra_nodes,
            });

            sui::event::emit(RetrySettlementEvent {
                ticket_id,
                how_many_nodes_in_echelon: how_many_extra_nodes,
            });
        } else {
            let mut new_nodes_map = vector::empty();
            let mut i = 0;
            while (!new_nodes.is_empty()) {
                let new_node_id = new_nodes.pop_back();
                new_nodes_map.push_back(MapNodeToChunk {
                    node_id: new_node_id,
                    // offset by 1 because there's already the asserter
                    order: i + 1,
                });
                i = i + 1;
            };

            sui::event::emit(NewlySampledNodesEvent {
                ticket_id,
                new_nodes: new_nodes_map,
            });
        };

        return_settlement_ticket(atoma, ticket);
    }

    /// We can replace timed out nodes at most `MaxTicketTimeouts` times, after
    /// that the ticket goes to dispute.
    fun max_timeout_attempts_reached(self: &SettlementTicket): bool {
        self.timeout.timed_out_count >= MaxTicketTimeouts
    }

    /// # How the timeout works?
    ///
    /// When creating a ticket, we store Sui epoch id and MS since epoch started.
    /// When checking for timeout, we check it against the current epoch and
    /// current MS since it started.
    /// 1. If the timeout threshold has been reached, the ticket is timed out.
    /// 2. If the epoch is the same (hot path because epoch takes 24 hours),
    ////   check the diff between current ms and the stored one.
    /// 3. If the current epoch is +1 of the stored ones, the epoch just got
    ///    bumped.
    ///    We don't know exactly how long since the epoch changed unfortunately,
    ///    but because timeouts are short we give the nodes some extra time by
    ///    checking that MS since epoch started is less than the timeout MS.
    ///    This means that those prompts submitted at the border of an epoch bump
    ///    are more graceful with timeouts by having timeouts at most twice as
    ///    long.
    /// 4. The scenario where epoch is more than +1 should not happen bcs of
    ///    the aforementioned 24h epoch period being less than the timeout, but
    ///    for the sake of completeness, we can just return true.
    fun did_timeout(self: &SettlementTicket, ctx: &TxContext): bool {
        let current_epoch = ctx.epoch();
        let TimeoutInfo {
            timed_out_count: _,
            timeout_ms,
            started_in_epoch,
            started_at_epoch_timestamp_ms,
        } = self.timeout;

        // 1.
        if (self.max_timeout_attempts_reached()) {
            true
        }
        // 2.
        else if (current_epoch == started_in_epoch) {
            ctx.epoch_timestamp_ms() - started_at_epoch_timestamp_ms > timeout_ms
        }
        // 3.
        else if (current_epoch == started_in_epoch + 1) {
            ctx.epoch_timestamp_ms() > timeout_ms
        }
        // 4.
        else {
            true
        }
    }

    fun replace_timed_out_nodes(
        ticket: &mut SettlementTicket,
        atoma: &mut AtomaDb,
        rng: &mut sui::random::RandomGenerator,
    ): vector<MapNodeToChunk> {
        let mut new_nodes = vector::empty();
        let mut i = 0;
        while (i < ticket.all.length()) {
            let node_id = ticket.all[i];

            if (!ticket.completed.contains(&node_id)) {
                let confiscated = atoma.slash_node_on_timeout(node_id);
                atoma.deposit_to_communal_treasury(confiscated);

                // sample another node to replace the slashed one
                let mut perhaps_new_node_id = atoma
                    .sample_node_by_echelon_id(
                        ticket.model_name,
                        ticket.echelon_id,
                        rng,
                    );
                // TBD: should we try to sample again if node already in the list?

                if (perhaps_new_node_id.is_none()) {
                    // no more nodes, return an empty vector which will start
                    // a dispute
                    break
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

        new_nodes
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
}
