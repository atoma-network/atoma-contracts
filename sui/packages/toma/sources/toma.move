module toma::toma {
    use sui::coin;

    /// The coin type.
    public struct TOMA has drop {}

    const DECIMALS: u8 = 9;
    const SYMBOL: vector<u8> = b"TOMA";
    const NAME: vector<u8> = b"TOMA";
    const DESCRIPTION: vector<u8> = b"Atoma network coin";

    /// A treasury cap is sent to the publisher, who then controls minting and
    /// burning of TOMA tokens.
    fun init(otw: TOMA, ctx: &mut TxContext) {
        let url = option::none();
        let (treasury, metadata) = coin::create_currency(
            otw,
            DECIMALS,
            SYMBOL,
            NAME,
            DESCRIPTION,
            url,
            ctx
        );

        transfer::public_transfer(treasury, ctx.sender());
        transfer::public_transfer(metadata, ctx.sender());
    }
}
