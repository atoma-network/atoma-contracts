module atoma::settlement {
    use atoma::db::{SmallId, NodeBadge, AtomaDb};

    const ENotAwaitingNodeEvaluation: u64 = 0;

    /// Shared object.
    ///
    /// Ticket that's created when user submits a new prompt.
    /// It will be used to track the status of the prompt.
    ///
    /// We use vectors for nodes info under the assumption that there won't be
    /// many nodes.
    /// In general, we want to minimize the number of nodes that are involved in
    /// the evaluation of a prompt, because of the cost of the evaluation and
    /// diminishing returns of validation value added.
    public struct SettlementTicket has key {
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
        ticket: &mut SettlementTicket,
        badge: &NodeBadge,
        hash: vector<u8>,
    ) {
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

    public entry fun try_to_settle(
        atoma: &mut AtomaDb,
    ) {
        //
    }
}
