module atoma::prompts {
    //! This module provides some default prompts by Atoma.
    //! However, patterns in this module can be reused by any partnered contract
    //! that was authorized with PromptBadge.

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
        let temperature = 0;
        let params = atoma::gate::create_text_prompt_params(
            model,
            string::utf8(b"Tell me a joke please"),
            max_tokens,
            temperature,
        );
        atoma::gate::submit_text_prompt(
            atoma,
            &prompts.badge,
            wallet.balance_mut(),
            params,
            max_fee_per_token,
            tokens_count,
            option::none(), // default nodes to sample
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
