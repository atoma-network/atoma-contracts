module atoma::atoma {
    //! # Terminology
    //! - Node: a machine that can serve prompts.
    //! - Model: a machine learning model that can be served by nodes.
    //! - Echelon: a set of hardware and software specifications of a node.
    //!   We group specs off-chain into a single identifier.
    //! - Commitment: a process of submitting prompt evaluation by a node.
    //! - Asserter: the first node to provide a commitment.
    //! - Validator: any other node that provides a commitment and is not the asserter.

    use sui::package;

    public struct ATOMA has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: ATOMA, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        let pub = package::claim(otw, ctx);
        transfer::public_transfer(pub, ctx.sender());
    }
}
