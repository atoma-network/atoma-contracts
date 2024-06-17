module toma::main {
    public struct MAIN has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: MAIN, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        sui::package::claim_and_keep(otw, ctx);
    }
}
