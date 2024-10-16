//! Commands related to on-chain db module.
//!
//! Mainly concerned with node and model state management and global
//! configurations.

mod acquire_new_stack_entry;
mod add_model;
mod add_model_echelon;
mod add_node_to_model;
mod create_task_entry;
mod deprecate_task;
mod destroy_disabled_node;
mod permanently_disable_node;
mod print_env;
mod register_node;
mod remove_deprecated_task;
mod remove_node_from_model;
mod set_required_registration_collateral;
mod submit_stack_settlement_attestation;
mod subscribe_node_to_task;
mod try_settle_stack;
mod unsubscribe_node_from_task;
mod unsubscribe_node_from_task_by_index;
mod claim_funds;
mod start_attestation_dispute;

pub(crate) use acquire_new_stack_entry::command as acquire_new_stack_entry;
pub(crate) use add_model::command as add_model;
pub(crate) use add_model_echelon::command as add_model_echelon;
pub(crate) use add_node_to_model::command as add_node_to_model;
pub(crate) use create_task_entry::command as create_task_entry;
pub(crate) use deprecate_task::command as deprecate_task;
pub(crate) use destroy_disabled_node::command as destroy_disabled_node;
pub(crate) use permanently_disable_node::command as permanently_disable_node;
pub(crate) use print_env::command as print_env;
pub(crate) use register_node::command as register_node;
pub(crate) use remove_deprecated_task::command as remove_deprecated_task;
pub(crate) use remove_node_from_model::command as remove_node_from_model;
pub(crate) use set_required_registration_collateral::command as set_required_registration_collateral;
pub(crate) use submit_stack_settlement_attestation::command as submit_stack_settlement_attestation;
pub(crate) use subscribe_node_to_task::command as subscribe_node_to_task;
pub(crate) use try_settle_stack::command as try_settle_stack;
pub(crate) use unsubscribe_node_from_task::command as unsubscribe_node_from_task;
pub(crate) use unsubscribe_node_from_task_by_index::command as unsubscribe_node_from_task_by_index;
pub(crate) use claim_funds::command as claim_funds;
pub(crate) use start_attestation_dispute::command as start_attestation_dispute;
