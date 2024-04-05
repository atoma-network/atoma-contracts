module atoma::gate {
    use atoma::db::{AtomaManagerBadge, AtomaDb};
    use std::ascii;
    use std::option::{Self, Option};
    use std::string;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object_table::{Self, ObjectTable};
    use sui::object::{Self, UID, ID};
    use sui::table_vec::{Self, TableVec};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct PromptBadge has key, store {
        id: UID,
    }

    struct TextPromptParams has store, copy, drop {
        prompt: string::String,
        max_tokens: u64,
        /// Represents a floating point number between 0 and 1, big endian.
        temperature: u32,
    }

    struct TextRequestEvent has copy, drop {
        params: TextPromptParams,
    }

    public fun submit_text_prompt(
        atoma: &mut AtomaDb,
        params: TextPromptParams,
        _:& PromptBadge,
    ) {
        //
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
}
