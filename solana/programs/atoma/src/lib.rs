use anchor_lang::{prelude::*, solana_program::clock::Slot};
use bytemuck::{Pod, Zeroable};

declare_id!("Cf8jbVDAgQcNy9TCt9PtSVvZZV5AcX7gpq7vx1ccgbcg");

/// Determines how many ranges of node IDs can be stored in an echelon.
/// One range is 8 bytes.
/// When the range array is full and nodes cannot unsubscribe without swapping
/// anymore, there will now be 2 times this amount of nodes that can be swapped
/// with.
/// This along with the self-repairing mechanism ensures that nodes can
/// unsubscribe freely
const MAX_ECHELON_RANGES: usize = 64;
/// Due to restrictions of the Solana account size, we limit the number of
/// echelons per one group.
/// The account size of [`ModelEchelonGroupV1`] can be increased with a special
/// instruction if needed.
const MAX_ECHELONS_PER_MODEL_GROUP_V1: usize = 16;

#[program]
pub mod atoma {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize {}

/// The main account that stores echelons and their node IDs for sampling.
/// It's a PDA whose seed contains the model name.
/// For the sake of brevity, we don't store the model name directly on the
/// account.
///
/// User provides this account when creating a prompt.
/// According to their token price requirements and number of sampled nodes, we
/// randomly select an echelon from all the echelons that can serve the prompt.
#[account(zero_copy)]
pub struct ModelEchelonGroupV1 {
    /// If the first bit is set, the model is initialized.
    /// Using `u64` because of zero copy.
    pub flags: u64,
    /// We don't store enums because of zero copy.
    /// This translates to [`ModelModality`].
    pub modality: u64,
    /// The echelons.
    pub echelons: [ModelEchelon; MAX_ECHELONS_PER_MODEL_GROUP_V1],
    /// Some reserved space for future use.
    pub reserved: [u64; 8],
}

/// The modality of the model determines the sort of prompts it can serve.
pub enum ModelModality {
    Text2Text = 0,
    Text2Image = 1,
}

/// An echelon is a group of nodes that can serve prompts with the expectation
/// that the output will be the same because the nodes are grouped by HW and SW
/// characteristics.
#[derive(Clone, Copy, Pod, Zeroable)]
#[repr(C)]
pub struct ModelEchelon {
    /// If the first bit is set, the echelon is initialized.
    /// If the second bit is set, the echelon is enabled.
    ///
    /// Using `u64` because of zero copy.
    pub flags: u64,
    /// How much per input token is charged by nodes in this group.
    /// In TOMA tokens.
    pub input_fee_per_token: u64,
    /// How much per output token is charged by nodes in this group.
    /// In TOMA tokens.
    ///
    /// The difference between input and output is made because the input
    /// could be text and output could be an image, in which case this is
    /// interpreted as a fee per pixel.
    pub output_fee_per_token: u64,
    /// The higher this number, the more likely this echelon is to be
    /// selected to serve a prompt.
    /// Read it as "relative performance compared to other echelons".
    pub relative_performance: u64,
    /// If settlement is not done within this time, we attempt to settle
    /// without waiting for nodes that did not respond.
    pub settlement_timeout_slots: Slot,
    /// Determines which nodes can be sampled for prompts.
    /// Boxed to lower the stack size.
    pub ranges: ModelEchelonIdRanges,
    /// Some reserved space for future use.
    pub reserved: [u64; 8],
}

/// Self repairing data structure that contains ranges of node IDs.
/// The optimal condition is when there is exactly one range.
/// What that means is that all nodes are subscribed and there are no holes in
/// the ID space.
///
/// If a node unsubscribes and its ID is not a low/high of any range, the
/// range it belongs to is split into two ranges.
///
/// The goal of this data structure is to tend towards the optimal condition.
/// When given a chance, it will merge ranges back.
/// This avoids overflowing the Solana account space.
///
/// The self repairing mechanism that merges ranges back comprises these
/// processes:
/// 1. When a new node is subscribed, it is assigned ID of the first range
///    low/high minus/plus 1.
/// 2. When a node submits its commitment, we check if the ID is a low/high of a
///    range that's not the first range. If it is, we _reassign_ its ID to the
///    high plus 1 of the first range. From this slot onwards, the node will
///    respond to prompts containing the new ID. Re-assignment can happen
///    multiple times, but there's minimal delay between two re-assignments. The
///    delay is set so that all tickets that were created for the old ID are
///    closed. Since timeout of a prompt ticket is on the scale of seconds to
///    minutes, the minimal delay is an magnitude higher.
///    [`AssignedNodeId::Reassigned`] variant is used to represent this state.
/// 3. When a node wants to unsubscribe but the array of ranges reached its
///    limit (temporary before some other ranges get merged) then the node can
///    still swap places with a node that's high/low of some range and has not
///    been reassigned recently.
///
/// These three processes together ensure that nodes can unsubscribe at any
/// point, IDs can be randomly sampled and the Solana account size is
/// predictable and not too large.
#[derive(Clone, Copy, Pod, Zeroable)]
#[repr(C)]
pub struct ModelEchelonIdRanges {
    /// If we add up all the ranges, they equal this.
    /// Useful to take track of for load balancing.
    pub len: u64,
    pub ranges: [NodeIdRange; MAX_ECHELON_RANGES],
}

/// Inclusive range of node IDs.
///
/// If both [`NodeId`]s are equal 0 then this range is empty.
#[derive(Clone, Copy, Pod, Zeroable)]
#[repr(C)]
pub struct NodeIdRange {
    /// Inclusive
    pub low: NodeId,
    /// Inclusive
    pub high: NodeId,
}

/// An account created for a node.
#[account]
pub struct ModelEchelonNode {
    pub id: AssignedNodeId,
}

#[derive(AnchorSerialize, AnchorDeserialize, Copy, Clone, PartialEq, Eq)]
pub enum AssignedNodeId {
    /// The node is currently subscribed to resolve prompts for the echelon.
    /// Its ID will be in the range of IDs for the echelon.
    Subscribed { id: NodeId, at_slot: Slot },
    /// This node unsubscribed from the echelon at the given slot.
    /// It won't be receiving any more prompts.
    /// Some other node can take the ID of this node.
    /// There can be at most one subscribed node with the same ID at the same
    /// time.
    ///
    /// TBD: An unsubscribed node can never be assigned again, the node's
    /// account must be destroyed and then recreated.
    Unsubscribed { id: NodeId, at_slot: Slot },
    /// The most complicated case.
    ///
    /// Because
    /// 1. of limitations of the Solana account size;
    /// 2. we want to support large number of nodes in any given echelon;
    /// 3. nodes can unsubscribe at any time
    ///
    /// we store ranges of IDs that are valid for the echelon and are randomly
    /// sampled.
    ///
    /// See [`ModelEchelonIdRanges`] and [`NodeId`] for more information.
    Reassigned {
        /// When did the reassignment happen.
        at_slot: Slot,
        /// What was the previous ID.
        /// Important to remember so that existing tickets still can be
        /// resolved with the old ID.
        from_id: NodeId,
        /// The new ID.
        /// All prompt tickets created after the `at_slot` inclusive will be
        /// resolved with this ID.
        to_id: NodeId,
        /// When was the old ID assigned to the node.
        /// Tickets that are older than this slot have nothing to do with the
        /// old ID anymore.
        old_id_assigned_at_slot: Slot,
    },
}

/// Understanding the ID assignment is crucial.
///
/// Some relevant constraints:
/// - Node must be able to unsubscribe
/// - It must be possible to randomly sample node IDs that are ready to serve
///   prompts
/// - Support for tens of thousands of nodes and more
///
/// An ID is assigned per echelon.
/// Since echelons are independent, we don't need to care about ID collisions.
///
/// An ID is only relevant when accompanied with a temporal information (slot).
/// This is what allows us to support large number of nodes with limited space.
/// We opt for a self-repairing data structure that contains ranges of node IDs.
/// A node ID can be changed at any time and that ID can later again be given
/// to a different node.
/// Therefore, without the temporal information, we cannot resolve a prompt.
///
/// Please see also [`AssignedNodeId`] which contains this temporal information.
///
/// # Important
/// Node ID 0 is reserved and cannot be assigned to a node.
/// TODO: Provide constructor that fails if 0 is passed.
#[derive(
    AnchorSerialize,
    AnchorDeserialize,
    Copy,
    Clone,
    PartialEq,
    Eq,
    Pod,
    Zeroable,
)]
#[repr(C)]
pub struct NodeId(pub u32);
