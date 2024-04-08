module atoma::atoma {
    use sui::package;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    struct ATOMA has drop {}

    /// The package publisher allows upgrades and admin access to other modules.
    fun init(otw: ATOMA, ctx: &mut TxContext) {
        // https://examples.sui.io/basics/publisher.html
        let pub = package::claim(otw, ctx);
        transfer::public_transfer(pub, tx_context::sender(ctx));
    }
}
