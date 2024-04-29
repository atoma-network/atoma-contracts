//! Commands related to on-chain db module.
//!
//! Mainly concerned with node and model state management and global
//! configurations.

mod add_model;
mod add_model_echelon;
mod add_node_to_model;
mod register_node;
mod set_required_registration_collateral;

pub(crate) use add_model::command as add_model;
pub(crate) use add_model_echelon::command as add_model_echelon;
pub(crate) use add_node_to_model::command as add_node_to_model;
pub(crate) use register_node::command as register_node;
pub(crate) use set_required_registration_collateral::command as set_required_registration_collateral;
