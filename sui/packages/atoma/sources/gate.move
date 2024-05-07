module atoma::gate {
    use atoma::db::{SmallId, ModelEchelon, AtomaDb};
    use atoma::settlement::SettlementTicket;
    use atoma::utils::random_u256;
    use std::ascii;
    use std::string;
    use sui::balance::Balance;
    use sui::dynamic_field;
    use toma::toma::TOMA;

    const DefaultNodesToSample: u64 = 10;
    const MaxNodesToSample: u64 = 256;

    const ENoEligibleEchelons: u64 = 0;
    const ETooManyNodesToSample: u64 = 1;

    #[allow(unused_field)]
    /// Serves as an input to the `submit_text2text_prompt` function.
    /// Is also included with the emitted `Text2TextPromptEvent`.
    ///
    /// Float numbers are converted into u32 with
    /// `u32::from_le_bytes(xxx_f32.to_le_bytes())`
    public struct Text2TextPromptParams has store, copy, drop {
        max_tokens: u64,
        model: ascii::String,
        prompt: string::String,
        random_seed: u64,
        repeat_last_n: u64,
        /// Represents a floating point number, little endian.
        repeat_penalty: u32,
        /// Represents a floating point number, little endian.
        temperature: u32,
        top_k: u64,
        /// Represents a floating point number, little endian.
        top_p: u32,
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted to produce text.
    public struct Text2TextPromptEvent has copy, drop {
        /// The ID of the settlement object.
        ticket_id: ID,
        /// The parameters of the prompt that nodes must evaluate.
        params: Text2TextPromptParams,
        /// This might not be the final list of nodes that will be used to
        /// evaluate the prompt.
        /// If nodes don't agree on the output or not enough nodes provide
        /// the output in time, extra nodes will be sampled.
        nodes: vector<SmallId>,
    }

    #[allow(unused_field)]
    /// Serves as an input to the `submit_text2image_prompt` function.
    /// Is also included with the emitted `Text2TePromptEvent`.
    ///
    /// Float numbers are converted into u32 with
    /// `u32::from_le_bytes(xxx_f32.to_le_bytes())`
    public struct Text2ImagePromptParams has store, copy, drop {
        /// Represents a floating point number, little endian.
        guidance_scale: u32,
        height: u64,
        model: ascii::String,
        n_steps: u64,
        num_samples: u64,
        prompt: string::String,
        random_seed: u64,
        width: u64,
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted to produce image.
    public struct Text2ImagePromptEvent has copy, drop {
        /// The ID of the settlement object.
        ticket_id: ID,
        /// The parameters of the prompt that nodes must evaluate.
        params: Text2ImagePromptParams,
        /// This might not be the final list of nodes that will be used to
        /// evaluate the prompt.
        /// If nodes don't agree on the output or not enough nodes provide
        /// the output in time, extra nodes will be sampled.
        nodes: vector<SmallId>,
    }

    /// The fee is per input token.
    ///
    /// Returns ticket ID which is an identifier of the settlement object.
    public fun submit_text2text_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        params: Text2TextPromptParams,
        max_fee_per_token: u64,
        nodes_to_sample: Option<u64>,
        ctx: &mut TxContext,
    ): ID {
        // these are approximations that will get refunded partly
        let input_characters = params.prompt.length();
        let output_tokens = params.max_tokens;

        let (mut ticket, selected_nodes) = submit_prompt(
            atoma,
            wallet,
            params.model,
            max_fee_per_token,
            input_characters,
            max_fee_per_token,
            output_tokens,
            nodes_to_sample,
            ctx,
        );
        // adds a dynfield to the ticket so that off chain can read the params
        // with a query (alternative is to query for the first event mentioning
        // the ticket id)
        dynamic_field::add(ticket.ticket_uid(), ascii::string(b"params"), params);

        let ticket_id = object::id(&ticket);
        atoma::settlement::return_settlement_ticket(atoma, ticket);

        sui::event::emit(Text2TextPromptEvent {
            params,
            ticket_id,
            nodes: selected_nodes,
        });

        ticket_id
    }

    /// The fee is per input token.
    ///
    /// Returns ticket ID which is an identifier of the settlement object.
    public fun submit_text2image_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        params: Text2ImagePromptParams,
        max_fee_per_input_token: u64,
        max_fee_per_output_token: u64,
        nodes_to_sample: Option<u64>,
        ctx: &mut TxContext,
    ): ID {
        // this is approximation that will get refunded partly
        let input_characters = params.prompt.length();
        // this we know exactly
        let output_pixels = params.width * params.height;

        let (mut ticket, selected_nodes) = submit_prompt(
            atoma,
            wallet,
            params.model,
            max_fee_per_input_token,
            input_characters,
            max_fee_per_output_token,
            output_pixels,
            nodes_to_sample,
            ctx,
        );
        // adds a dynfield to the ticket so that off chain can read the params
        // with a query (alternative is to query for the first event mentioning
        // the ticket id)
        dynamic_field::add(ticket.ticket_uid(), ascii::string(b"params"), params);

        let ticket_id = object::id(&ticket);
        atoma::settlement::return_settlement_ticket(atoma, ticket);

        sui::event::emit(Text2ImagePromptEvent {
            params,
            ticket_id,
            nodes: selected_nodes,
        });

        ticket_id
    }

    /// Arguments to `Text2TextPromptParams` in alphabetical order.
    public fun create_text2text_prompt_params(
        max_tokens: u64,
        model: ascii::String,
        prompt: string::String,
        random_seed: u64,
        repeat_last_n: u64,
        repeat_penalty: u32,
        temperature: u32,
        top_k: u64,
        top_p: u32,
    ): Text2TextPromptParams {
        Text2TextPromptParams {
            max_tokens,
            model,
            prompt,
            random_seed,
            repeat_last_n,
            repeat_penalty,
            temperature,
            top_k,
            top_p,
        }
    }

    /// Arguments to `Text2ImagePromptParams` in alphabetical order.
    public fun create_text2image_prompt_params(
        guidance_scale: u32,
        height: u64,
        model: ascii::String,
        n_steps: u64,
        num_samples: u64,
        prompt: string::String,
        random_seed: u64,
        width: u64,
    ): Text2ImagePromptParams {
        Text2ImagePromptParams {
            guidance_scale,
            height,
            model,
            n_steps,
            num_samples,
            prompt,
            random_seed,
            width,
        }
    }

    // =========================================================================
    //                              Helpers
    // =========================================================================

    /// The fee is per input and output tokens.
    /// The provided estimation of the number of tokens is used to calculate
    /// the charged amount.
    /// However, the real fee is calculated when the nodes submit the results.
    /// The difference is refunded to the user.
    ///
    /// 1. Get the model echelons from the database.
    /// 2. Randomly pick one of the echelons.
    /// 3. Sample the required number of nodes from the echelon.
    /// 4. Collect the total fee that's going to be split among the nodes.
    /// 5. Create a new settlement ticket in the database.
    fun submit_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        model: ascii::String,
        max_fee_per_input_token: u64,
        approx_input_tokens_count: u64,
        max_fee_per_output_token: u64,
        approx_output_tokens_count: u64,
        nodes_to_sample: Option<u64>,
        ctx: &mut TxContext,
    ): (SettlementTicket, vector<SmallId>) {
        // 1.
        let echelons = atoma.get_model_echelons_if_enabled(model);

        // 2.
        let nodes_to_sample =
            nodes_to_sample.get_with_default(DefaultNodesToSample);
        assert!(nodes_to_sample <= MaxNodesToSample, ETooManyNodesToSample);
        let echelon_index = select_eligible_echelon_at_random(
            echelons,
            nodes_to_sample,
            max_fee_per_input_token,
            max_fee_per_output_token,
            ctx,
        );
        let echelon = echelons.borrow(echelon_index);
        let echelon_id = echelon.get_model_echelon_id();
        let echelon_settlement_timeout_ms =
            echelon.get_model_echelon_settlement_timeout_ms();
        let (input_fee, output_fee) = echelon.get_model_echelon_fees();

        // 3.
        let mut sampled_nodes = vector::empty();
        let mut iteration = 0;
        while (iteration < nodes_to_sample) {
            let node_id = atoma
                .sample_node_by_echelon_index(model, echelon_index, ctx)
                // unwraps if no unslashed nodes
                // TBD: should we try another echelon?
                // TODO: https://github.com/atoma-network/atoma-contracts/issues/13
                .extract();

            iteration = iteration + 1;
            if (!sampled_nodes.contains(&node_id)) {
                // we can end up with less nodes than requested, but no
                // duplicates
                //
                // TODO: https://github.com/atoma-network/atoma-contracts/issues/13
                sampled_nodes.push_back(node_id);
            };
        };

        // 4.
        // we must fit into u64 bcs that's the limit of Balance
        let collected_fee = input_fee * approx_input_tokens_count
            + output_fee * approx_output_tokens_count;
        atoma.deposit_to_fee_treasury(wallet.split(collected_fee));

        // 5.
        let ticket = atoma::settlement::new_ticket(
            model,
            echelon_id,
            sampled_nodes,
            input_fee,
            output_fee,
            collected_fee,
            echelon_settlement_timeout_ms,
            ctx,
        );

        (ticket, sampled_nodes)
    }

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
        max_fee_per_input_token: u64,
        max_fee_per_output_token: u64,
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

            let (input_fee, output_fee) = echelon.get_model_echelon_fees();
            if (input_fee > max_fee_per_input_token
                || output_fee > max_fee_per_output_token) {
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
