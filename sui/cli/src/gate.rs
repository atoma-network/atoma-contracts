//! Commands related to the gate module.
//! Mainly concerned with submitting prompts.

mod send_image_prompt;
mod send_prompt;
mod send_prompt_to_gateway;
mod send_prompt_to_ipfs;

pub(crate) use send_image_prompt::command as send_image_prompt;
pub(crate) use send_prompt::command as send_prompt;
pub(crate) use send_prompt_to_gateway::command as send_prompt_to_gateway;
pub(crate) use send_prompt_to_ipfs::command as send_prompt_to_ipfs;
