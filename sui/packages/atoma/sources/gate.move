module atoma::gate {
    use atoma::db::{SmallId, ModelEchelon, AtomaDb};
    use atoma::settlement::SettlementTicket;
    use std::ascii;
    use std::string;
    use sui::balance::Balance;
    use sui::dynamic_field;
    use toma::toma::TOMA;

    const MaxNodesToSample: u64 = 256;

    /// To be able to identify the errors faster in the logs, we start the
    /// counter from a number that's leet for "error_000".
    const EBase: u64 = 312012_100;
    const ENoEligibleEchelons: u64 = EBase + 0;
    const ETooManyNodesToSample: u64 = EBase + 1;
    const EModalityMismatch: u64 = EBase + 2;

    /// Models that take text as input and return text as output.
    /// Be careful about changing this as clients rely on this value.
    const Text2TextModality: u64 = 0;
    /// Models that take text as input and return an image as output.
    /// Be careful about changing this as clients rely on this value.
    const Text2ImageModality: u64 = 1;

    #[allow(unused_field)]
    /// Serves as an input to the `submit_text2text_prompt` function.
    /// Is also included with the emitted `Text2TextPromptEvent`.
    ///
    /// Float numbers are converted into u32 with
    /// `u32::from_le_bytes(xxx_f32.to_le_bytes())`
    public struct Text2TextPromptParams has store, copy, drop {
        max_tokens: u64,
        model: ascii::String,
        pre_prompt_tokens: vector<u32>,
        prepend_output_with_input: bool,
        prompt: string::String,
        random_seed: u64,
        repeat_last_n: u64,
        /// Represents a floating point number, little endian.
        repeat_penalty: u32,
        should_stream_output: bool,
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
        /// Determines into how many chunks do the nodes split the output when
        /// they generate proof hashes.
        /// Might not equal the number of sampled nodes, see `nodes` property.
        chunks_count: u64,
        /// This might not be the final list of nodes that will be used to
        /// evaluate the prompt.
        /// If nodes don't agree on the output or not enough nodes provide
        /// the output in time, extra nodes will be sampled.
        ///
        /// Also, this vector does not determine how many chunks to split the
        /// output into, only the order of nodes.
        ///
        /// We also have a probabilistic cross validation mechanism during which
        /// there will only be one node sampled, but the prompt will still be
        /// split into several chunks.
        /// See the settlement module for more info.
        nodes: vector<SmallId>,
        /// This is the output destination where the output will be stored. The output is serialized with a MessagePack.
        output_destination: vector<u8>,
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
        img2img: Option<string::String>,
        /// Represents a floating point number, little endian
        img2img_strength: u32,
        model: ascii::String,
        n_steps: u64,
        /// How many images to generate.
        /// The user pays for each image.
        num_samples: u64,
        output_destination: vector<u8>,
        prompt: string::String,
        random_seed: u64,
        uncond_prompt: string::String,
        width: u64,
    }

    #[allow(unused_field)]
    /// This event is emitted when the text prompt is submitted to produce image.
    public struct Text2ImagePromptEvent has copy, drop {
        /// The ID of the settlement object.
        ticket_id: ID,
        /// The parameters of the prompt that nodes must evaluate.
        params: Text2ImagePromptParams,
        /// Determines into how many chunks do the nodes split the output when
        /// they generate proof hashes.
        /// Might not equal the number of sampled nodes, see `nodes` property.
        chunks_count: u64,
        /// This might not be the final list of nodes that will be used to
        /// evaluate the prompt.
        /// If nodes don't agree on the output or not enough nodes provide
        /// the output in time, extra nodes will be sampled.
        ///
        /// Also, this vector does not determine how many chunks to split the
        /// output into, only the order of nodes.
        ///
        /// We also have a probabilistic cross validation mechanism during which
        /// there will only be one node sampled, but the prompt will still be
        /// split into several chunks.
        /// See the settlement module for more info.
        nodes: vector<SmallId>,
        /// This is the output destination where the output will be stored. The output is serialized with a MessagePack.
        output_destination: vector<u8>,
    }

    #[allow(lint(public_random))]
    /// The fee is per input token.
    ///
    /// Returns ticket ID which is an identifier of the settlement object.
    ///
    /// # Randomness safety
    /// - prompt is submitted by user
    /// - random is used to sample nodes
    /// - user cannot get the list of selected nodes in the same transaction
    public fun submit_text2text_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        params: Text2TextPromptParams,
        max_fee_per_token: u64,
        nodes_to_sample: Option<u64>,
        output_destination: vector<u8>,
        random: &sui::random::Random,
        ctx: &mut TxContext,
    ): ID {
        let mut rng = random.new_generator(ctx);

        // These are approximations that will get refunded partly.
        // While for the preprompt, we know the exact number of tokens, the
        // input is a string and we don't know the exact number of tokens.
        // Therefore this is an overestimation.
        // See the settlement logic for reimbursement.
        let input_tokens_approximation =
            params.pre_prompt_tokens.length() + params.prompt.length();
        let output_tokens = params.max_tokens;

        let (mut ticket, chunks_count, selected_nodes) = submit_prompt(
            atoma,
            wallet,
            params.model,
            Text2TextModality,
            max_fee_per_token,
            input_tokens_approximation,
            max_fee_per_token,
            output_tokens,
            nodes_to_sample,
            &mut rng,
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
            chunks_count,
            nodes: selected_nodes,
            output_destination
        });

        ticket_id
    }

    #[allow(lint(public_random))]
    /// The fee per input token is the prompt fee.
    /// The fee per output token is how much does one image cost.
    ///
    /// Returns ticket ID which is an identifier of the settlement object.
    ///
    /// # Randomness safety
    /// - prompt is submitted by user
    /// - random is used to sample nodes
    /// - user cannot get the list of selected nodes in the same transaction
    public fun submit_text2image_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        params: Text2ImagePromptParams,
        max_fee_per_input_token: u64,
        max_fee_per_output_token: u64,
        nodes_to_sample: Option<u64>,
        output_destination: vector<u8>,
        random: &sui::random::Random,
        ctx: &mut TxContext,
    ): ID {
        let mut rng = random.new_generator(ctx);

        // this is approximation that will get refunded partly
        let input_characters = params.prompt.length();
        // this we know exactly
        let images = params.num_samples;

        let (mut ticket, chunks_count, selected_nodes) = submit_prompt(
            atoma,
            wallet,
            params.model,
            Text2ImageModality,
            max_fee_per_input_token,
            input_characters,
            max_fee_per_output_token,
            images,
            nodes_to_sample,
            &mut rng,
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
            chunks_count,
            nodes: selected_nodes,
            output_destination
        });

        ticket_id
    }

    /// Arguments to `Text2TextPromptParams` in alphabetical order.
    public fun create_text2text_prompt_params(
        max_tokens: u64,
        model: ascii::String,
        pre_prompt_tokens: vector<u32>,
        prepend_output_with_input: bool,
        prompt: string::String,
        random_seed: u64,
        repeat_last_n: u64,
        repeat_penalty: u32,
        should_stream_output: bool,
        temperature: u32,
        top_k: u64,
        top_p: u32,
    ): Text2TextPromptParams {
        Text2TextPromptParams {
            max_tokens,
            model,
            pre_prompt_tokens,
            prepend_output_with_input,
            prompt,
            random_seed,
            repeat_last_n,
            repeat_penalty,
            should_stream_output,
            temperature,
            top_k,
            top_p,
        }
    }

    /// Arguments to `Text2ImagePromptParams` in alphabetical order.
    public fun create_text2image_prompt_params(
        guidance_scale: u32,
        height: u64,
        img2img_strength: u32,
        img2img: Option<string::String>,
        model: ascii::String,
        n_steps: u64,
        num_samples: u64,
        output_destination: vector<u8>,
        prompt: string::String,
        random_seed: u64,
        uncond_prompt: string::String,
        width: u64,
    ): Text2ImagePromptParams {
        Text2ImagePromptParams {
            guidance_scale,
            height,
            img2img_strength,
            img2img,
            model,
            n_steps,
            num_samples,
            output_destination,
            prompt,
            random_seed,
            uncond_prompt,
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
    ///
    /// Returns
    /// - the ticket that can be attached to the atoma db
    /// - into how many chunks should be the output split for commitment
    /// - what were the sampled nodes (so far)
    fun submit_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Balance<TOMA>,
        model: ascii::String,
        model_modality: u64,
        max_fee_per_input_token: u64,
        approx_input_tokens_count: u64,
        max_fee_per_output_token: u64,
        approx_output_tokens_count: u64,
        requested_nodes_to_sample: Option<u64>,
        rng: &mut sui::random::RandomGenerator,
        ctx: &mut TxContext,
    ): (SettlementTicket, u64, vector<SmallId>) {
        let expected_model_modality = atoma.get_model_modality(model);
        assert!(expected_model_modality == model_modality, EModalityMismatch);

        // 1.
        let echelons = atoma.get_model_echelons_if_enabled(model);

        // 2.
        // if None we do probabilistic cross validation (see settlement)
        let has_cross_validation = requested_nodes_to_sample.is_none();
        let nodes_to_sample = requested_nodes_to_sample.get_with_default(1);
        assert!(nodes_to_sample <= MaxNodesToSample, ETooManyNodesToSample);
        let echelon_index = select_eligible_echelon_at_random(
            echelons,
            nodes_to_sample,
            max_fee_per_input_token,
            max_fee_per_output_token,
            rng,
        );
        let echelon = echelons.borrow(echelon_index);
        let echelon_id = echelon.get_model_echelon_id();
        let echelon_settlement_timeout_ms =
            echelon.get_model_echelon_settlement_timeout_ms();
        let (input_fee, output_fee) = echelon.get_model_echelon_fees();

        // 3.
        let sampled_nodes = atoma.sample_unique_nodes_by_echelon_index(
            model,
            echelon_index,
            nodes_to_sample,
            rng,
        );

        // 4.
        let extra_cross_validation_counts_count =
            atoma.get_cross_validation_extra_nodes_count();
        let fee_per_node = input_fee * approx_input_tokens_count
            + output_fee * approx_output_tokens_count;

        let collected_fee = if (has_cross_validation) {
            // if the extra nodes were always sampled, this is the fee they
            // would require
            let full_extra_fee = extra_cross_validation_counts_count * fee_per_node;

            // We must take into account that in `1 - p` cases there is just one
            // and conversely in `p` cases there are
            // `extra_cross_validation_counts_count`.
            //
            // We scale down the fee such that on average the fees add up to
            // the number of on average sampled nodes

            let amortized_extra_fee =
              full_extra_fee * atoma.get_cross_validation_probability_permille()
            / //----------------------------------------------------------------
                                        1000;

            // pay the fee for the one node that's always sampled plus the
            // fee that amortizes the cost of the extra nodes
            fee_per_node + amortized_extra_fee
        } else {
            nodes_to_sample * fee_per_node
        };
        // we must fit into u64 bcs that's the limit of Balance
        atoma.deposit_to_fee_treasury(wallet.split(collected_fee));

        // 5.
        let mut ticket = atoma::settlement::new_ticket(
            model,
            echelon_id,
            sampled_nodes,
            input_fee,
            output_fee,
            collected_fee,
            echelon_settlement_timeout_ms,
            ctx,
        );

        if (has_cross_validation) {
            // attach this information to the ticket
            ticket.request_cross_validation(
                atoma.get_cross_validation_probability_permille(),
                extra_cross_validation_counts_count,
            );
            // this is a vector of length one
            let sampled_node = sampled_nodes;

            (ticket, 1 + extra_cross_validation_counts_count, sampled_node)
        } else {
            // nothing special
            (ticket, sampled_nodes.length(), sampled_nodes)
        }
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
        rng: &mut sui::random::RandomGenerator,
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

        // modulo is ok because we don't allow performance to be 0
        let goal = 1 + rng.generate_u256() % total_performance; // B

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

    #[test]
    fun it_selects_correct_echelon() {
        let mut ctx = sui::tx_context::dummy();
        let mut rng = sui::random::new_generator_for_testing();
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_a = 1;
        let echelon_b = 2;
        let manager = atoma::db::create_manager_badge_for_testing(&mut ctx);
        let mut atoma = atoma::db::new_atoma_db(&mut ctx);

        atoma.add_model_entry(&manager, model_name, Text2TextModality, &mut ctx);
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_a,
            150, // input fee
            100, // output fee
            100, // performance
            &mut ctx,
        );
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_b,
            200, // input fee
            130, // output fee
            400, // performance
            &mut ctx,
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, &mut ctx);
        let mut node_badge_2 = atoma.register_node(&mut toma_wallet, &mut ctx);
        let mut node_badge_3 = atoma.register_node(&mut toma_wallet, &mut ctx);
        let mut node_badge_4 = atoma.register_node(&mut toma_wallet, &mut ctx);
        let mut node_badge_5 = atoma.register_node(&mut toma_wallet, &mut ctx);
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_a);
        atoma.add_node_to_model(&mut node_badge_2, model_name, echelon_a);
        atoma.add_node_to_model(&mut node_badge_3, model_name, echelon_a);
        atoma.add_node_to_model(&mut node_badge_4, model_name, echelon_b);
        atoma.add_node_to_model(&mut node_badge_5, model_name, echelon_b);

        let mut i = 0;
        // perform many submissions to take away random luck, always the first
        // echelon must be sampled because of fees
        while (i < 10) {
            let value_before_submission = toma_wallet.value();
            let (ticket, chunks, sampled_nodes) = submit_prompt(
                &mut atoma,
                &mut toma_wallet,
                model_name,
                Text2TextModality,
                160, // input fee
                5, // input tokens
                160, // output fee
                5, // output tokens
                option::some(2), // nodes
                &mut rng,
                &mut ctx,
            );
            sui::transfer::public_share_object(ticket);
            assert!(
                sampled_nodes.contains(&node_badge_1.get_node_id()) ||
                sampled_nodes.contains(&node_badge_2.get_node_id()) ||
                sampled_nodes.contains(&node_badge_3.get_node_id())
            );
            assert!(
                !sampled_nodes.contains(&node_badge_4.get_node_id()) &&
                !sampled_nodes.contains(&node_badge_5.get_node_id())
            );
            assert!(toma_wallet.value() < value_before_submission);
            assert!(chunks == sampled_nodes.length());

            i = i + 1;
        };

        let mut i = 0;
        // perform many submissions to take away random luck, always the first
        // echelon must be sampled because of number of nodes
        while (i < 10) {
            let (ticket, _, sampled_nodes) = submit_prompt(
                &mut atoma,
                &mut toma_wallet,
                model_name,
                Text2TextModality,
                1000, // input fee
                5, // input tokens
                1000, // output fee
                5, // output tokens
                option::some(3), // nodes
                &mut rng,
                &mut ctx,
            );
            sui::transfer::public_share_object(ticket);
            assert!(
                sampled_nodes.contains(&node_badge_1.get_node_id()) ||
                sampled_nodes.contains(&node_badge_2.get_node_id()) ||
                sampled_nodes.contains(&node_badge_3.get_node_id())
            );
            assert!(
                !sampled_nodes.contains(&node_badge_4.get_node_id()) &&
                !sampled_nodes.contains(&node_badge_5.get_node_id())
            );

            i = i + 1;
        };

        // either echelon can be chosen now, but echelon b has higher
        // performance so it should be chosen more often even though it has
        // less nodes
        let mut i = 0;
        let mut echelon_a_count = 0;
        let mut echelon_b_count = 0;
        while (i < 100) {
            let (ticket, _, sampled_nodes) = submit_prompt(
                &mut atoma,
                &mut toma_wallet,
                model_name,
                Text2TextModality,
                1000, // input fee
                5, // input tokens
                1000, // output fee
                5, // output tokens
                option::some(2), // nodes
                &mut rng,
                &mut ctx,
            );
            sui::transfer::public_share_object(ticket);
            let echelon_a_sampled =
                sampled_nodes.contains(&node_badge_1.get_node_id()) ||
                sampled_nodes.contains(&node_badge_2.get_node_id()) ||
                sampled_nodes.contains(&node_badge_3.get_node_id());
            let echelon_b_sampled =
                sampled_nodes.contains(&node_badge_4.get_node_id()) ||
                sampled_nodes.contains(&node_badge_5.get_node_id());

            if (echelon_a_sampled) {
                assert!(!echelon_b_sampled);
                echelon_a_count = echelon_a_count + 1;
            } else {
                assert!(echelon_b_sampled);
                echelon_b_count = echelon_b_count + 1;
            };

            i = i + 1;
        };
        // The chance that by random luck echelon a is chosen more often
        // compared to the number of times this test will ever run is zero.
        assert!(echelon_b_count > echelon_a_count);

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::transfer::public_share_object(node_badge_2);
        sui::transfer::public_share_object(node_badge_3);
        sui::transfer::public_share_object(node_badge_4);
        sui::transfer::public_share_object(node_badge_5);
        sui::balance::destroy_for_testing(toma_wallet);
    }

    #[test]
    #[expected_failure(abort_code = ENoEligibleEchelons)]
    fun it_fails_if_not_enough_nodes() {
        let mut ctx = sui::tx_context::dummy();
        let mut rng = sui::random::new_generator_for_testing();
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_id = 1;
        let manager = atoma::db::create_manager_badge_for_testing(&mut ctx);
        let mut atoma = atoma::db::new_atoma_db(&mut ctx);

        atoma.add_model_entry(&manager, model_name, Text2TextModality, &mut ctx);
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_id,
            150, // input fee
            100, // output fee
            100, // performance
            &mut ctx,
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, &mut ctx);
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_id);

        let (ticket, _, _) = submit_prompt(
                &mut atoma,
                &mut toma_wallet,
                model_name,
                Text2TextModality,
                160, // input fee
                5, // input tokens
                160, // output fee
                5, // output tokens
                option::some(2), // not enough nodes in the echelon, hence fails
                &mut rng,
                &mut ctx,
            );
            sui::transfer::public_share_object(ticket);

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::balance::destroy_for_testing(toma_wallet);
    }

    #[test]
    fun it_enables_cross_validation() {
        let mut ctx = sui::tx_context::dummy();
        let mut rng = sui::random::new_generator_for_testing();
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_id = 1;
        let manager = atoma::db::create_manager_badge_for_testing(&mut ctx);
        let mut atoma = atoma::db::new_atoma_db(&mut ctx);

        atoma.add_model_entry(&manager, model_name, Text2TextModality, &mut ctx);
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_id,
            150, // input fee
            100, // output fee
            100, // performance
            &mut ctx,
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, &mut ctx);
        let mut node_badge_2 = atoma.register_node(&mut toma_wallet, &mut ctx);
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_id);
        atoma.add_node_to_model(&mut node_badge_2, model_name, echelon_id);


        let (ticket, _, _) = submit_prompt(
            &mut atoma,
            &mut toma_wallet,
            model_name,
            Text2TextModality,
            160, // input fee
            5, // input tokens
            160, // output fee
            5, // output tokens
            option::none(), // cross validation
            &mut rng,
            &mut ctx,
        );
        assert!(ticket.has_cross_validation());

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(ticket);
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::transfer::public_share_object(node_badge_2);
        sui::balance::destroy_for_testing(toma_wallet);
    }

    #[test]
    fun it_settles_ticket() {
        let mut scenario = sui::test_scenario::begin(@0x0);
        sui::random::create_for_testing(scenario.ctx());
        sui::test_scenario::next_tx(&mut scenario, @0x1);
        let rnd = sui::test_scenario::take_shared<sui::random::Random>(&scenario);
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_id = 1;
        let manager = atoma::db::create_manager_badge_for_testing(scenario.ctx());
        let mut atoma = atoma::db::new_atoma_db(scenario.ctx());
        let txt2txt_modality = 0;

        atoma.add_model_entry(&manager, model_name, txt2txt_modality, scenario.ctx());
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_id,
            150, // input fee
            100, // output fee
            100, // performance
            scenario.ctx(),
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        let mut node_badge_2 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_id);
        atoma.add_node_to_model(&mut node_badge_2, model_name, echelon_id);

        let (root, chunk_hashes) = example_hashes(2);

        let (ticket_id, node_order) = submit_test_prompt(
            &mut atoma,
            &mut toma_wallet,
            model_name,
            &rnd,
            &mut scenario,
        );
        let (node_chunk_1, node_chunk_2) = if (node_order[0] == node_badge_1.get_node_id()) {
            (chunk_hashes[0], chunk_hashes[1])
        } else {
            (chunk_hashes[1], chunk_hashes[0])
        };

        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_1,
            ticket_id,
            1,
            1,
            root,
            node_chunk_1,
            &rnd,
            scenario.ctx(),
        );
        let ticket =
            atoma::settlement::get_settlement_ticket_mut(&mut atoma, ticket_id);
        assert!(!ticket.is_being_disputed());
        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_2,
            ticket_id,
            1,
            1,
            root,
            node_chunk_2,
            &rnd,
            scenario.ctx(),
        );
        // ticket successfully closed
        assert!(!atoma::settlement::has_ticket(&mut atoma, ticket_id));

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::transfer::public_share_object(node_badge_2);
        sui::balance::destroy_for_testing(toma_wallet);
        sui::test_scenario::return_shared(rnd);
        sui::test_scenario::end(scenario);
    }

    #[test]
    fun it_disputes_if_input_tokens_mismatch() {
        let mut scenario = sui::test_scenario::begin(@0x0);
        sui::random::create_for_testing(scenario.ctx());
        sui::test_scenario::next_tx(&mut scenario, @0x1);
        let rnd = sui::test_scenario::take_shared<sui::random::Random>(&scenario);
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_id = 1;
        let manager = atoma::db::create_manager_badge_for_testing(scenario.ctx());
        let mut atoma = atoma::db::new_atoma_db(scenario.ctx());
        let txt2txt_modality = 0;

        atoma.add_model_entry(&manager, model_name, txt2txt_modality, scenario.ctx());
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_id,
            150, // input fee
            100, // output fee
            100, // performance
            scenario.ctx(),
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        let mut node_badge_2 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_id);
        atoma.add_node_to_model(&mut node_badge_2, model_name, echelon_id);

        let (root, chunk_hashes) = example_hashes(2);

        let (ticket_id, node_order) = submit_test_prompt(
            &mut atoma,
            &mut toma_wallet,
            model_name,
            &rnd,
            &mut scenario,
        );
        let (node_chunk_1, node_chunk_2) = if (node_order[0] == node_badge_1.get_node_id()) {
            (chunk_hashes[0], chunk_hashes[1])
        } else {
            (chunk_hashes[1], chunk_hashes[0])
        };

        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_1,
            ticket_id,
            1,
            1,
            root,
            node_chunk_1,
            &rnd,
            scenario.ctx(),
        );
        let ticket =
            atoma::settlement::get_settlement_ticket_mut(&mut atoma, ticket_id);
        assert!(!ticket.is_being_disputed());
        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_2,
            ticket_id,
            2, // does not match
            1,
            root,
            node_chunk_2,
            &rnd,
            scenario.ctx(),
        );
        let ticket =
            atoma::settlement::get_settlement_ticket_mut(&mut atoma, ticket_id);
        assert!(ticket.is_being_disputed());

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::transfer::public_share_object(node_badge_2);
        sui::balance::destroy_for_testing(toma_wallet);
        sui::test_scenario::return_shared(rnd);
        sui::test_scenario::end(scenario);
    }

    #[test]
    fun it_disputes_if_chunks_dont_hash() {
        let mut scenario = sui::test_scenario::begin(@0x0);
        sui::random::create_for_testing(scenario.ctx());
        sui::test_scenario::next_tx(&mut scenario, @0x1);
        let rnd = sui::test_scenario::take_shared<sui::random::Random>(&scenario);
        let mut toma_wallet = sui::balance::create_for_testing(100_000_000);
        let model_name = ascii::string(b"model");
        let echelon_id = 1;
        let manager = atoma::db::create_manager_badge_for_testing(scenario.ctx());
        let mut atoma = atoma::db::new_atoma_db(scenario.ctx());
        let txt2txt_modality = 0;

        atoma.add_model_entry(&manager, model_name, txt2txt_modality, scenario.ctx());
        atoma.add_model_echelon_entry(
            &manager,
            model_name,
            echelon_id,
            150, // input fee
            100, // output fee
            100, // performance
            scenario.ctx(),
        );
        let mut node_badge_1 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        let mut node_badge_2 = atoma.register_node(&mut toma_wallet, scenario.ctx());
        atoma.add_node_to_model(&mut node_badge_1, model_name, echelon_id);
        atoma.add_node_to_model(&mut node_badge_2, model_name, echelon_id);

        let (root, chunk_hashes) = example_hashes(2);

        let (ticket_id, node_order) = submit_test_prompt(
            &mut atoma,
            &mut toma_wallet,
            model_name,
            &rnd,
            &mut scenario,
        );
        // this is wrong and will make the ticket disputed
        let (node_chunk_1, node_chunk_2) = if (node_order[0] == node_badge_1.get_node_id()) {
            (chunk_hashes[1], chunk_hashes[0])
        } else {
            (chunk_hashes[0], chunk_hashes[1])
        };

        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_1,
            ticket_id,
            1,
            1,
            root,
            node_chunk_1,
            &rnd,
            scenario.ctx(),
        );
        let ticket =
            atoma::settlement::get_settlement_ticket_mut(&mut atoma, ticket_id);
        assert!(!ticket.is_being_disputed());
        atoma::settlement::submit_commitment(
            &mut atoma,
            &node_badge_2,
            ticket_id,
            2, // does not match
            1,
            root,
            node_chunk_2,
            &rnd,
            scenario.ctx(),
        );
        let ticket =
            atoma::settlement::get_settlement_ticket_mut(&mut atoma, ticket_id);
        assert!(ticket.is_being_disputed());

        // clean up
        atoma.share_db_for_testing();
        sui::transfer::public_share_object(manager);
        sui::transfer::public_share_object(node_badge_1);
        sui::transfer::public_share_object(node_badge_2);
        sui::balance::destroy_for_testing(toma_wallet);
        sui::test_scenario::return_shared(rnd);
        sui::test_scenario::end(scenario);
    }

    #[test_only]
    fun example_hashes(number_of_nodes: u64): (vector<u8>, vector<vector<u8>>) {
        let mut collector = vector::empty();
        let mut chunk_hashes = vector::empty();

        let mut i = 0;
        while (i < number_of_nodes) {
            let chunk_hash = sui::hash::blake2b256(&vector::empty());
            collector.append(chunk_hash);
            chunk_hashes.push_back(chunk_hash);
            i = i + 1;
        };

        (sui::hash::blake2b256(&collector), chunk_hashes)
    }

    #[test_only]
    fun submit_test_prompt(
        atoma: &mut AtomaDb,
        toma_wallet: &mut Balance<TOMA>,
        model_name: ascii::String,
        rnd: &sui::random::Random,
        scenario: &mut sui::test_scenario::Scenario,
    ): (ID, vector<SmallId>) {
        let ticket_id = atoma::gate::submit_text2text_prompt(
            atoma,
            toma_wallet,
            atoma::gate::create_text2text_prompt_params(
                1,
                model_name,
                vector::empty(),
                false,
                std::string::utf8(b"prompt"),
                1,
                1,
                1,
                false,
                1,
                1,
                1,
            ),
            1000, // max fee
            option::some(2), // nodes
            vector::empty(), // output_destination
            rnd,
            scenario.ctx(),
        );
        let ticket = atoma::settlement::get_settlement_ticket_mut(atoma, ticket_id);
        let node_order = ticket.get_all_sampled_nodes();

        (ticket_id, node_order)
    }
}
