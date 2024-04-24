module atoma::gate {
    use atoma::db::{AtomaManagerBadge, SmallId, ModelEchelon, AtomaDb};
    use atoma::utils::random_u256;
    use std::ascii;
    use std::string;

    const ENoEligibleEchelons: u64 = 0;

    /// Stored or owned object.
    ///
    /// Anyone holding on this object can submit raw prompts.
    public struct PromptBadge has key, store {
        id: UID,
    }

    #[allow(unused_field)]
    /// Serves as an input to the `submit_text_prompt` function.
    /// Is also included with the emitted `TextPromptEvent`.
    public struct TextPromptParams has store, copy, drop {
        model: ascii::String,
        prompt: string::String,
        max_tokens: u64,
        /// Represents a floating point number between 0 and 1, big endian.
        temperature: u32,
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted.
    public struct TextPromptEvent has copy, drop {
        /// The ID of the settlement object.
        ticket_id: ID,
        /// The parameters of the prompt that nodes must evaluate.
        params: TextPromptParams,
        /// This might not be the final list of nodes that will be used to
        /// evaluate the prompt.
        /// If nodes don't agree on the output or not enough nodes provide
        /// the output in time, extra nodes will be sampled.
        nodes: vector<SmallId>,
    }

    /// TODO: Temporary function that showcases the contract.
    public entry fun submit_example_text_prompt(
        atoma: &mut AtomaDb,
        model: ascii::String,
        prompt: string::String,
        nodes_to_sample: u64,
        ctx: &mut TxContext,
    ) {
        let params = TextPromptParams {
            model,
            prompt,
            max_tokens: 100,
            temperature: 0,
        };
        let max_fee_per_token = 18_446_744_073_709_551_615;
        let badge = PromptBadge { id: object::new(ctx) };
        submit_text_prompt(
            atoma,
            params,
            nodes_to_sample,
            max_fee_per_token,
            &badge,
            ctx,
        );
        destroy_prompt_badge(badge);
    }

    /// The fee is per input token.
    ///
    /// 1. Get the model echelons from the database.
    /// 2. Randomly pick one of the echelons.
    /// 3. Sample the required number of nodes from the echelon.
    /// 4. Create a new settlement ticket in the database.
    /// 5. Emit TextPromptEvent.
    public fun submit_text_prompt(
        atoma: &mut AtomaDb,
        params: TextPromptParams,
        nodes_to_sample: u64,
        max_fee_per_token: u64,
        _:& PromptBadge,
        ctx: &mut TxContext,
    ) {
        // 1.
        let echelons = atoma.get_model_echelons_if_enabled(params.model);

        // 2.
        let echelon_index = select_eligible_echelon_at_random(
            echelons,
            nodes_to_sample,
            max_fee_per_token,
            ctx,
        );
        let echelon = echelons.borrow(echelon_index);
        let echelon_id = echelon.get_model_echelon_id();
        let echelon_settlement_timeout_ms =
            echelon.get_model_echelon_settlement_timeout_ms();

        // 3.
        let mut selected_nodes = vector::empty();
        let mut iteration = 0;
        while (iteration < nodes_to_sample) {
            // TODO: https://github.com/atoma-network/atoma-contracts/issues/13
            let node_id = atoma
                .sample_node_by_echelon_index(params.model, echelon_index, ctx)
                .extract();

            if (selected_nodes.contains(&node_id)) {
                // try again with a different node without incrementing the
                // iteration counter
                //
                // we won't get stuck because we're guaranteed to have enough
                // nodes in the echelon
                // TODO: this no longer holds true because of slashed nodes
                continue
            };

            selected_nodes.push_back(node_id);
            iteration = iteration + 1;
        };

        // 4.
        let ticket_id = atoma::settlement::new_ticket(
            atoma,
            params.model,
            echelon_id,
            selected_nodes,
            echelon_settlement_timeout_ms,
            ctx
        );

        // 5.
        sui::event::emit(TextPromptEvent {
            params,
            ticket_id,
            nodes: selected_nodes,
        });
    }

    public fun create_prompt_badge(
        _: &AtomaManagerBadge,
        ctx: &mut TxContext,
    ): PromptBadge {
        let id = object::new(ctx);
        PromptBadge { id }
    }

    public fun destroy_prompt_badge(badge: PromptBadge) {
        let PromptBadge { id } = badge;
        id.delete();
    }


    // =========================================================================
    //                              Helpers
    // =========================================================================

    public struct EchelonIdAndPerformance has drop {
        /// Index within the echelons vector.
        index: u64,
        performance: u256,
    }

    /// 1. Filter out only appropriate echelons that are below max fee and
    ///   have enough nodes.
    /// 2. Randomly pick one of the echelons.
    ///
    /// We return an index into the `echelons` vector.
    ///
    /// # Algorithm
    /// TODO: https://github.com/atoma-network/atoma-contracts/issues/3
    ///
    /// A) total performance is a sum of all eligible echelons'
    /// performances
    /// B) goal is a random number in interval <1; total_performance>
    /// C) we iterate over eligible echelons and subtract their performance
    ///    from a counter that starts at total_performance
    /// D) the first echelon that makes the counter go below goal is selected
    ///
    /// For example, imagine three echelons:
    /// - `A` has 10 nodes and RP of 1.
    /// - `B` has 1 node and RP of 1.
    /// - `C` has 5 nodes and RP of 7.
    ///
    /// The total is: 10 * 1 + 1 * 1 + 5 * 7 = 46
    /// We generate a random number `R` in range of 1 to 46.
    /// Let's start with `B` which should get probability of 1/46.
    /// If the order of the array is `ABC`,
    /// then we must roll exactly 11 to hit B. 1/46 chance.
    /// If the order is `BAC` we must roll exactly 1 to hit B. 1/46
    /// If the order is `CBA` we must roll exactly 46 to hit B. 1/46
    ///
    /// Repeat the same thought process with the other echelons.
    /// That's how I validated in my mind that the order does not matter,
    /// the probability will be satisfied.
    fun select_eligible_echelon_at_random(
        echelons: &vector<ModelEchelon>,
        nodes_to_sample: u64,
        max_fee_per_token: u64,
        ctx: &mut TxContext,
    ): u64 {
        //
        // 1.
        //

        let mut total_performance: u256 = 0;
        let mut eligible_echelons = vector::empty();
        let echelon_count = echelons.length();
        let mut index = 0;
        while (index < echelon_count) {
            let echelon = echelons.borrow(index);

            let fee = echelon.get_model_echelon_fee();
            if (fee > max_fee_per_token) {
                index = index + 1;
                continue
            };

            let nodes = echelon.get_model_echelon_nodes();
            let node_count = nodes.length();
            if (node_count < nodes_to_sample) {
                index = index + 1;
                continue
            };

            let performance =
                (echelon.get_model_echelon_performance() as u256)
                *
                (node_count as u256);
            total_performance = total_performance + performance; // A
            eligible_echelons.push_back(EchelonIdAndPerformance {
                index,
                performance,
            });

            index = index + 1;
        };
        assert!(eligible_echelons.length() > 0, ENoEligibleEchelons);

        //
        // 2.
        //

        let goal = 1 + random_u256(ctx) % total_performance; // B

        let mut remaining_performance = total_performance;
        loop {
            // index never out of bounds bcs on last iteration
            // remaining_performance == 0 while goal > 0
            let EchelonIdAndPerformance {
                index, performance
            } = eligible_echelons.pop_back();
            remaining_performance = remaining_performance - performance; // C

            if (goal > remaining_performance) {
                return index // D
            };
        }
    }
}
