module atoma_tee::atoma_tee {
    //! # Terminology
    //! - Node: a machine that can serve execution workloads, through Trusted Execution Environments (TEEs).
    //!   We group specs off-chain into a single identifier.
    //! - Commitment: a process of submitting prompt evaluation by a node.
    //! - Asserter: the first node to provide a commitment.
    //! - Validator: any other node that provides a commitment and is not the asserter.

    public struct ATOMA_TEE has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: ATOMA_TEE, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        sui::package::claim_and_keep(otw, ctx);
    }
}
