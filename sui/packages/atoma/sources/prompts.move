module atoma::prompts {
    //! This module provides some default prompts by Atoma.
    //! However, patterns in this module can be reused by any partnered contract
    //! that was authorized with PromptBadge.
    //!
    //! To convert 1.0 to 1065353216, you can use this snippet:
    //! ```rust
    //! fn main() {
    //!     let float = 1.0_f32;
    //!     let int = u32::from_le_bytes(float.to_le_bytes());
    //!     println!("{int}");
    //! }
    //! ```

    use atoma::db::AtomaDb;
    use atoma::gate::PromptBadge;
    use std::ascii;
    use std::string;
    use sui::coin::Coin;
    use toma::toma::TOMA;

    /// Immutable object.
    ///
    /// Allows users to use standard Atoma prompts.
    public struct AtomaPrompts has key {
        id: UID,
        badge: PromptBadge,
    }

    /// Submits a text prompt to Atoma network that asks for a joke.
    public entry fun tell_me_a_joke(
        atoma: &mut AtomaDb,
        prompts: &AtomaPrompts,
        wallet: &mut Coin<TOMA>,
        model: ascii::String,
        max_fee_per_token: u64,
        ctx: &mut TxContext,
    ) {
        let tokens_count = 64;

        let max_tokens = 64;
        let prompt = string::utf8(b"Tell me a joke please");
        let random_seed = atoma::utils::random_u64(ctx);
        let repeat_last_n = 1;
        let repeat_penalty = 1066192077; // 1.1
        let temperature = 1048576000; // 0.25
        let top_k = 1;
        let top_p = 1063675494; // 0.9
        let params = atoma::gate::create_text2text_prompt_params(
            max_tokens,
            model,
            prompt,
            random_seed,
            repeat_last_n,
            repeat_penalty,
            temperature,
            top_k,
            top_p,
        );
        atoma::gate::submit_text2text_prompt(
            atoma,
            &prompts.badge,
            wallet.balance_mut(),
            params,
            max_fee_per_token,
            tokens_count,
            option::some(1), // default nodes to sample
            ctx,
        );
    }

    /// Submits a text prompt to Atoma network that asks for an image of
    /// a pixel art Colosseum.
    public entry fun generate_nft(
        atoma: &mut AtomaDb,
        prompts: &AtomaPrompts,
        wallet: &mut Coin<TOMA>,
        model: ascii::String,
        max_fee_per_token: u64,
        ctx: &mut TxContext,
    ) {
        let tokens_count = 64;

        let guidance_scale = 1065353216; // 1.0
        let height = 360;
        let n_steps = 40;
        let num_samples = 2;
        let prompt = string::utf8(b"Generate a bored ape NFT");
        let random_seed = atoma::utils::random_u64(ctx);
        let width = 640;

        let params = atoma::gate::create_text2image_prompt_params(
            guidance_scale,
            height,
            model,
            n_steps,
            num_samples,
            prompt,
            random_seed,
            width,
        );
        atoma::gate::submit_text2image_prompt(
            atoma,
            &prompts.badge,
            wallet.balance_mut(),
            params,
            max_fee_per_token,
            tokens_count,
            option::some(1), // default nodes to sample
            ctx,
        );
    }

    /// Other contracts need to be provided the badge object by the
    /// Atoma admin, but since we are in the same package we can simply
    /// grab it in the init function.
    fun init(ctx: &mut TxContext) {
        transfer::share_object(AtomaPrompts {
            id: object::new(ctx),
            badge: atoma::gate::create_prompt_badge_(ctx),
        });
    }
}
