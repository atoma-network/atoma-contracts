//! Commands related to the gate module.
//! Mainly concerned with submitting prompts.

mod submit_generate_nft_prompt;
mod submit_tell_me_a_joke_prompt;

pub(crate) use submit_generate_nft_prompt::command as submit_generate_nft_prompt;
pub(crate) use submit_tell_me_a_joke_prompt::command as submit_tell_me_a_joke_prompt;
