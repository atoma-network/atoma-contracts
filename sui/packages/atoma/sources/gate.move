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
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted.
    struct TextPromptEvent has copy, drop {
        params: TextPromptParams,
        nodes: vector<SmallId>,
    }

    /// 1. Get the model echelons from the database.
    /// 2. Randomly pick one of the echelons.
    /// 3. Sample the required number of nodes from the echelon.
    /// 4. Emit TextPromptEvent.
    public fun submit_text_prompt(
        atoma: &mut AtomaDb,
        params: TextPromptParams,
        nodes_to_sample: u64,
        max_fee_per_sample: u64,
        _:& PromptBadge,
        ctx: &mut TxContext,
    ) {
        // 1.
        let echelons = db::get_model_echelons_if_enabled(atoma, params.model);

        // 2.
        let echelon = select_eligible_echelon_at_random(
            echelons,
            nodes_to_sample,
            max_fee_per_sample,
            ctx,
        );

        // 3.
        let nodes = db::get_model_echelon_nodes(echelon);
        let nodes_count = table_vec::length(nodes);
        let selected_nodes = vector::empty();
        let iteration = 0;
        while (iteration < nodes_to_sample) {
            // TODO: keep track of selected indexes to avoid duplicates
            let node_index = random_u64(ctx) % nodes_count;
            let node_id = table_vec::borrow(nodes, node_index);
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
        performance: u64,
    }

    /// 1. Filter out only appropriate echelons that are below max fee and
    ///   have enough nodes.
    /// 2. Randomly pick one of the echelons.
    ///
    /// # Algorithm
    /// TODO: needs testing and proofreading
    /// A) total performance is a sum of all eligible echelons'
    /// performances
    /// B) goal is a random number in interval <1; total_performance>
    /// C) we iterate over eligible echelons and subtract their performance
    ///    from a counter that starts at total_performance
    /// D) the first echelon that makes the counter go below goal is selected
    fun select_eligible_echelon_at_random(
        echelons: &vector<ModelEchelon>,
        nodes_to_sample: u64,
        max_fee_per_sample: u64,
        ctx: &mut TxContext,
    ): &ModelEchelon {
        //
        // 1.
        //

        let total_performance = 0;
        let eligible_echelons = vector::empty();
        let echelon_count = vector::length(echelons);
        let index = 0;
        while (index < echelon_count) {
            let echelon = vector::borrow(echelons, index);

            let fee = db::get_model_echelon_fee(echelon);
            if (fee > max_fee_per_sample) {
                continue
            };

            let nodes = db::get_model_echelon_nodes(echelon);
            let node_count = table_vec::length(nodes);
            if (node_count < nodes_to_sample) {
                continue
            };

            let performance = db::get_model_echelon_performance(echelon);
            total_performance = total_performance + performance; // A
            vector::push_back(&mut eligible_echelons, EchelonIdAndPerformance {
                index,
                performance,
            });
        };
        assert!(vector::length(&eligible_echelons) > 0, ENoEligibleEchelons);

        //
        // 2.
        //

        let goal = 1 + random_u64(ctx) % total_performance; // B

        let remaining_performance = total_performance;
        while (true) {
            // index never out of bounds bcs on last iteration
            // remaining_performance == 0 while goal > 0
            let EchelonIdAndPerformance {
                index, performance
            } = vector::pop_back(&mut eligible_echelons);
            remaining_performance = remaining_performance - performance; // C

            if (goal > remaining_performance) {
                return vector::borrow(echelons, index) // D
            };
        };

        abort ENoEligibleEchelons
    }

    /// TODO: random number generator is currently on testnet only, and we
    ///       use the mainnet branch for development.
    ///       Once random is released as stable, we can replace this.
    /// <https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/packages/sui-framework/sources/random.move#L187>
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
}
