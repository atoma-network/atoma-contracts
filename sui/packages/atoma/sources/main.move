module atoma::atoma {
    use sui::package;

    public struct ATOMA has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: ATOMA, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        let pub = package::claim(otw, ctx);
        transfer::public_transfer(pub, ctx.sender());
    }
}
