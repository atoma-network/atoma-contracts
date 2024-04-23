module atoma::settlement {
    use sui::object::UID;
    use std::vector;
    use atoma::db::{Self, AtomaManagerBadge, SmallId, NodeBadge, AtomaDb};

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

    public entry fun submit_evaluation(
        ticket: &mut SettlementTicket,
        badge: &NodeBadge,
        hash: vector<u8>,
    ) {
        let node_id = db::get_node_id(badge);
        let (contains, index) = vector::index_of(&ticket.awaiting, &node_id);
        assert!(contains, ENotAwaitingNodeEvaluation);
        vector::remove(&mut ticket.awaiting, index);

        if (ticket.completed.length() != 0) {
            let first_hash = vector::borrow(&ticket.completed, 0).hash;
            if (hash != first_hash) {
                ticket.stats.all_hashes_match = false;
            };
        };

        vector::push_back(&mut ticket.completed, MapNodeToHash {
            node_id: node_id,
            hash: hash,
        });
    }

    public entry fun try_to_settle() {
        //
    }
}
