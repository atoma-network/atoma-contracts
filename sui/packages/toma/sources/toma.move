module toma::toma {
    use sui::coin;
    use sui::package::Publisher;

    /// The coin type.
    public struct TOMA has drop {}

    const DECIMALS: u8 = 9;
    const SYMBOL: vector<u8> = b"TOMA";
    const NAME: vector<u8> = b"TOMA";
    const DESCRIPTION: vector<u8> = b"Atoma network coin";

    /// Used to mint TOMA tokens.
    public struct Faucet has key, store {
        id: UID,
        treasury: Option<coin::TreasuryCap<TOMA>>,
    }

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

        // by default, faucet is disabled
        transfer::share_object(Faucet {
            id: object::new(ctx),
            treasury: option::none(),
        });
    }

    /// Only call this on testnet or devnet.
    entry fun enable_faucet(
        faucet: &mut Faucet, treasury: coin::TreasuryCap<TOMA>,
    ) {
        faucet.treasury.fill(treasury);
    }

    /// Faucet should never be enabled on mainnet.
    entry fun disable_faucet(
        faucet: &mut Faucet, publisher: &Publisher, ctx: &TxContext,
    ) {
        assert!(sui::package::from_package<TOMA>(publisher));
        let treasury = faucet.treasury.extract();
        transfer::public_transfer(treasury, ctx.sender());
    }

    /// Mints some TOMA if the faucet is enabled.
    entry fun faucet(faucet: &mut Faucet, amount: u64, ctx: &mut TxContext) {
        let treasury = faucet.treasury.borrow_mut();
        let wallet = treasury.mint(amount, ctx);
        transfer::public_transfer(wallet, ctx.sender());
    }
}
