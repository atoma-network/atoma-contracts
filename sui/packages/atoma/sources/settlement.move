module atoma::settlement {
    //! TODO: check the merkle tree hashes to prove that each node did the work

    use atoma::db::{SmallId, NodeBadge, AtomaDb};
    use sui::dynamic_object_field;

    const ENotAwaitingNodeEvaluation: u64 = 0;

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
        /// List of nodes that are currently evaluating the prompt and have not
        /// as of yet completed the evaluation.
        awaiting: vector<SmallId>,
        /// Maps nodes that completed the evaluation to the hash of the result.
        /// This vector is sorted, ie. the first element is the first node that
        /// completed the evaluation first.
        completed: vector<MapNodeToHash>,
        /// Some extra metadata about the settlement.
        stats: OperationalStats,
    }

    public struct MapNodeToHash has store, drop {
        node_id: SmallId,
        hash: vector<u8>,
    }

    /// Holds data that's relevant for successful resolution of the prompt.
    public struct OperationalStats has store, drop {
        /// If the settlement takes more than this, the settlement can be cut
        /// short.
        /// See the `try_to_settle` endpoint.
        timeout_ms: u64,
        /// Will be relevant for timeouting.
        started_in_epoch: u64,
        /// Will be relevant for timeouting.
        started_at_epoch_timestamp_ms: u64,
        /// A happy path flag.
        /// Set to true when this object is created, and will be set to false
        /// if any hash doesn't match the first submitted hash.
        all_hashes_match: bool,
    }

    /// If a node is part of the awaiting list, it can submit the evaluation.
    /// The evaluation is accepted regardless of the hash value.
    ///
    /// Once all/enough nodes submit or the timeout is reached, the
    /// `try_to_settle` endpoint can be called.
    public entry fun submit_evaluation(
        atoma: &mut AtomaDb,
        badge: &NodeBadge,
        ticket_id: ID,
        hash: vector<u8>,
    ) {
        let ticket = get_settlement_ticket_mut(atoma, ticket_id);
        let node_id = badge.get_node_id();
        let (contains, index) = ticket.awaiting.index_of(&node_id);
        assert!(contains, ENotAwaitingNodeEvaluation);
        ticket.awaiting.remove(index);

        if (!ticket.completed.is_empty()) {
            let first_hash = ticket.completed.borrow(0).hash;
            if (hash != first_hash) {
                ticket.stats.all_hashes_match = false;
            };
        };

        ticket.completed.push_back(MapNodeToHash {
            node_id: node_id,
            hash: hash,
        });
    }

    /// 1. Happy path is when all hashes match and nothing is being awaited
    /// 2. If timeout is reached or all nodes have submitted, we need to decide
    ///    whether a critical mass of nodes agree on the solution to slash the
    ///     rest, or TODO
    /// 3. Nothing to do, we need to wait
    public entry fun try_to_settle(
        atoma: &mut AtomaDb,
        ticket_id: ID,
        ctx: &TxContext,
    ) {
        // We remove it so that Sui Move doesn't scream at us for not being able
        // to use mut ref to atoma.
        // If settlement can be done, the ticket will be destroyed.
        // If not, it will be again added to the db.
        let ticket = remove_settlement_ticket(atoma, ticket_id);

        //
        // 1.
        //
        if (ticket.stats.all_hashes_match && ticket.awaiting.is_empty()) {
            let SettlementTicket {
                id,
                awaiting: _,
                completed,
                stats: _,
            } = ticket;
            id.delete();

            // TODO: reward the nodes
        }
        //
        // 2.
        //
        else if (ticket.awaiting.is_empty() || ticket.stats.did_timeout(ctx)) {
            // TODO: find critical mass of nodes that agree on the solution

            // TODO: if there isn't, ask for more nodes to evaluate?

            // TODO: if there critical mass, reward them, slash the rest
            let SettlementTicket {
                id,
                awaiting: _,
                completed,
                stats: _,
            } = ticket;
            id.delete();
        }
        //
        // 3.
        //
        else {
            // timeout not reached, not all nodes have submitted, nothing to do
            return_settlement_ticket(atoma, ticket);

            // TBD: possibly, we could predict whether more nodes are needed by
            //      finding the most submitted solution and if it's less than
            //      critical mass minus the number of awaiting nodes, already
            //      extend the awaiting list
        }
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
    fun did_timeout(self: &OperationalStats, ctx: &TxContext): bool {
        let current_epoch = ctx.epoch();

        // 1.
        if (current_epoch == self.started_in_epoch) {
            ctx.epoch_timestamp_ms() - self.started_at_epoch_timestamp_ms > self.timeout_ms
        }
        // 2.
        else if (current_epoch == self.started_in_epoch + 1) {
            ctx.epoch_timestamp_ms() > self.timeout_ms
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
        let uid = atoma.get_uid_mut();
        dynamic_object_field::borrow_mut(uid, ticket)
    }

    fun remove_settlement_ticket(
        atoma: &mut AtomaDb,
        ticket: ID,
    ): SettlementTicket {
        let uid = atoma.get_uid_mut();
        dynamic_object_field::remove(uid, ticket)
    }

    fun return_settlement_ticket(
        atoma: &mut AtomaDb,
        ticket: SettlementTicket,
    ) {
        let uid = atoma.get_uid_mut();
        dynamic_object_field::add(uid, object::id(&ticket), ticket)
    }
}
