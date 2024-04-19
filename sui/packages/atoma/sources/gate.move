module atoma::gate {
    use atoma::db::{Self, AtomaManagerBadge, SmallId, ModelEchelon, AtomaDb};
    use std::ascii;
    use std::string;
    use sui::event;
    use std::vector;
    use sui::object::{Self, UID};
    use sui::table_vec;
    use sui::tx_context::{Self, TxContext};

    const ENoEligibleEchelons: u64 = 0;

    /// Stored or owned object.
    ///
    /// Anyone holding on this object can submit raw prompts.
    struct PromptBadge has key, store {
        id: UID,
    }

    #[allow(unused_field)]
    /// Serves as an input to the `submit_text_prompt` function.
    /// Is also included with the emitted `TextPromptEvent`.
    struct TextPromptParams has store, copy, drop {
        model: ascii::String,
        prompt: string::String,
        max_tokens: u64,
        /// Represents a floating point number between 0 and 1, big endian.
        temperature: u32,
        random_seed: u128,
        repeat_last_n: u32,
        /// Represents a floating point number between 1 and infty, big endian.
        repeat_penalty: u32,
        /// Represents a floating point number between 0 and 1, big endian.
        top_p: Option<u32>,
        top_k: Option<u32>
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted.
    struct TextPromptEvent has copy, drop {
        params: TextPromptParams,
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
        let max_total_fee = 18_446_744_073_709_551_615;
        let badge = PromptBadge { id: object::new(ctx) };
        submit_text_prompt(
            atoma,
            params,
            nodes_to_sample,
            max_total_fee,
            &badge,
            ctx,
        );
        destroy_prompt_badge(badge);
    }

    /// 1. Get the model echelons from the database.
    /// 2. Randomly pick one of the echelons.
    /// 3. Sample the required number of nodes from the echelon.
    /// 4. Emit TextPromptEvent.
    public fun submit_text_prompt(
        atoma: &mut AtomaDb,
        params: TextPromptParams,
        nodes_to_sample: u64,
        max_total_fee: u64,
        _:& PromptBadge,
        ctx: &mut TxContext,
    ) {
        // 1.
        let echelons = db::get_model_echelons_if_enabled(atoma, params.model);

        // 2.
        let echelon = select_eligible_echelon_at_random(
            echelons,
            nodes_to_sample,
            max_total_fee,
            // ideally we'd pass the context, but move is dumb and thinks that
            // because we return a reference, we could still be using the
            // context, which we need to access mutably later on
            random_u256(ctx),
        );

        // 3.
        let nodes = db::get_model_echelon_nodes(echelon);
        let nodes_count = table_vec::length(nodes);
        let selected_nodes = vector::empty();
        let iteration = 0;
        while (iteration < nodes_to_sample) {
            let node_index = random_u64(ctx) % nodes_count;
            let node_id = table_vec::borrow(nodes, node_index);

            if (vector::contains(&selected_nodes, node_id)) {
                // try again with a different node without incrementing the
                // iteration counter
                //
                // we won't get stuck because we're guaranteed to have enough
                // nodes in the echelon
                continue
            };

            vector::push_back(&mut selected_nodes, *node_id);
            iteration = iteration + 1;
        };

        // 4.
        event::emit(TextPromptEvent {
            params,
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
        object::delete(id);
    }


    // =========================================================================
    //                              Helpers
    // =========================================================================

    struct EchelonIdAndPerformance has drop {
        /// Index within the echelons vector.
        index: u64,
        performance: u256,
    }

    /// 1. Filter out only appropriate echelons that are below max fee and
    ///   have enough nodes.
    /// 2. Randomly pick one of the echelons.
    ///
    /// # Algorithm
    /// TODO: https://github.com/atoma-network/atoma-contracts/issues/3
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
        max_total_fee: u64,
        random_u256: u256,
    ): &ModelEchelon {
        //
        // 1.
        //

        let total_performance: u256 = 0;
        let eligible_echelons = vector::empty();
        let echelon_count = vector::length(echelons);
        let index = 0;
        while (index < echelon_count) {
            let echelon = vector::borrow(echelons, index);

            let fee = db::get_model_echelon_fee(echelon);
            if (fee > max_total_fee) {
                index = index + 1;
                continue
            };

            let nodes = db::get_model_echelon_nodes(echelon);
            let node_count = table_vec::length(nodes);
            if (node_count < nodes_to_sample) {
                index = index + 1;
                continue
            };

            let performance =
                (db::get_model_echelon_performance(echelon) as u256)
                *
                (node_count as u256);
            total_performance = total_performance + performance; // A
            vector::push_back(&mut eligible_echelons, EchelonIdAndPerformance {
                index,
                performance,
            });

            index = index + 1;
        };
        assert!(vector::length(&eligible_echelons) > 0, ENoEligibleEchelons);

        //
        // 2.
        //

        let goal = 1 + random_u256 % total_performance; // B

        let remaining_performance = total_performance;
        loop {
            // index never out of bounds bcs on last iteration
            // remaining_performance == 0 while goal > 0
            let EchelonIdAndPerformance {
                index, performance
            } = vector::pop_back(&mut eligible_echelons);
            remaining_performance = remaining_performance - performance; // C

            if (goal > remaining_performance) {
                return vector::borrow(echelons, index) // D
            };
        }
    }

    /// TODO: https://github.com/atoma-network/atoma-contracts/issues/4
    fun random_u64(ctx: &mut TxContext): u64 {
        let buffer = sui::address::to_bytes(
            tx_context::fresh_object_address(ctx)
        );

        let num_of_bytes = 8;
        let result: u64 = 0;
        let i = 0;
        while (i < num_of_bytes) {
            let byte = vector::pop_back(&mut buffer);
            result = (result << 8) + (byte as u64);
            i = i + 1;
        };
        result
    }

    /// TODO: https://github.com/atoma-network/atoma-contracts/issues/4
    fun random_u256(ctx: &mut TxContext): u256 {
        let buffer = sui::address::to_bytes(
            tx_context::fresh_object_address(ctx)
        );

        let num_of_bytes = 32;
        let result: u256 = 0;
        let i = 0;
        while (i < num_of_bytes) {
            let byte = vector::pop_back(&mut buffer);
            result = (result << 8) + (byte as u256);
            i = i + 1;
        };
        result
    }

    #[test]
    fun test_random_u64() {
        let ctx = tx_context::new_from_hint(
            @0x1,
            9908,
            10,
            10,
            0
        );
        random_u64(&mut ctx);
    }

    #[test]
    fun test_random_u256() {
        let ctx = tx_context::new_from_hint(
            @0x1,
            9908,
            10,
            10,
            0
        );
        random_u256(&mut ctx);
    }
}
