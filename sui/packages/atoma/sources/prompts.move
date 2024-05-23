module atoma::prompts {
    //! This module provides some example prompts by Atoma.
    //! If you are writing your own smart contract that depends on Atoma, this
    //! is a great place to start.
    //!
    //! # Floating point numbers
    //! Since Sui does not have floating point number representation, we store
    //! floating point numbers as u32 integers.
    //! For example, to convert 1.0 to 1065353216, you can use this snippet:
    //! ```rust
    //! fn main() {
    //!     let float = 1.0_f32;
    //!     let int = u32::from_le_bytes(float.to_le_bytes());
    //!     println!("{int}");
    //! }
    //! ```

    use atoma::db::AtomaDb;
    use std::ascii;
    use std::string;
    use sui::coin::Coin;
    use toma::toma::TOMA;

    
    /// Submits a text prompt to Atoma network that asks for a joke.
    public entry fun send_prompt(
        atoma: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        model: ascii::String,
        output_destination: vector<u8>,
        pre_prompt_tokens: vector<u32>,
        prepend_output_with_input: bool,
        max_fee_per_token: u64,
        prompt: string::String,
        should_stream_output: bool,
        max_tokens: u64,
        repeat_last_n: u64,
        repeat_penalty: u32,
        temperature: u32,
        top_k: u64,
        top_p: u32,
        nodes_to_sample: Option<u64>,
        ctx: &mut TxContext,
    ) {
        let random_seed = atoma::utils::random_u64(ctx);
        let params = atoma::gate::create_text2text_prompt_params(
            max_tokens,
            model,
            output_destination,
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
        );
        atoma::gate::submit_text2text_prompt(
            atoma,
            wallet.balance_mut(),
            params,
            max_fee_per_token,
            // we sample just one node because of the illustrative purposes of
            // this prompt, so that we can deploy this contract on devnet and
            // have it produce output without many nodes
            //
            // you can set this to none to let Atoma network decide how many
            // nodes to sample
            nodes_to_sample,
            ctx,
        );
    }

    /// Submits a text prompt to Atoma network that asks for a joke.
    public entry fun tell_me_a_joke(
        atoma: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        model: ascii::String,
        output_destination: vector<u8>,
        max_fee_per_token: u64,
        ctx: &mut TxContext,
    ) {
        let max_tokens = 64;
        let pre_prompt_tokens = vector::empty();
        let prepend_output_with_input = false;
        let prompt = string::utf8(b"Tell me a joke please");
        let random_seed = atoma::utils::random_u64(ctx);
        let repeat_last_n = 1;
        let repeat_penalty = 1066192077; // 1.1
        let should_stream_output = false;
        let temperature = 1048576000; // 0.25
        let top_k = 1;
        let top_p = 1063675494; // 0.9
        let params = atoma::gate::create_text2text_prompt_params(
            max_tokens,
            model,
            output_destination,
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
        );
        atoma::gate::submit_text2text_prompt(
            atoma,
            wallet.balance_mut(),
            params,
            max_fee_per_token,
            // we sample just one node because of the illustrative purposes of
            // this prompt, so that we can deploy this contract on devnet and
            // have it produce output without many nodes
            //
            // you can set this to none to let Atoma network decide how many
            // nodes to sample
            option::some(1),
            ctx,
        );
    }

    /// Submits a text prompt to Atoma network that asks for an image of
    /// a pixel art Colosseum.
    public entry fun generate_nft(
        atoma: &mut AtomaDb,
        wallet: &mut Coin<TOMA>,
        model: ascii::String,
        output_destination: vector<u8>,
        max_fee_per_input_token: u64,
        max_fee_per_output_pixel: u64,
        ctx: &mut TxContext,
    ) {
        let guidance_scale = 1065353216; // 1.0
        let height = 256;
        let n_steps = 40;
        let num_samples = 2;
        let prompt = string::utf8(b"Generate a bored ape NFT");
        let uncond_prompt = string::utf8(b"Shinny, bright, bored, blue background");
        let random_seed = atoma::utils::random_u32(ctx);
        let width = 256;
        let img2img_strength = 1065353216; // 1.0
        let img2img = option::none();

        let params = atoma::gate::create_text2image_prompt_params(
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
        );
        atoma::gate::submit_text2image_prompt(
            atoma,
            wallet.balance_mut(),
            params,
            max_fee_per_input_token,
            max_fee_per_output_pixel,
            // we sample just one node because of the illustrative purposes of
            // this prompt, so that we can deploy this contract on devnet and
            // have it produce output without many nodes
            //
            // you can set this to none to let Atoma network decide how many
            // nodes to sample
            option::some(1),
            ctx,
        );
    }
}
