module toma::toma {
    use sui::coin;
    use sui::package::Publisher;

    const DECIMALS: u8 = 9;
    const SYMBOL: vector<u8> = b"ALPHA_TOMA";
    const NAME: vector<u8> = b"ALPHA_TOMA";
    const DESCRIPTION: vector<u8> = b"Atoma network coin";

    /// The coin type.
    public struct TOMA has drop {}

    /// Emitted once when the package is published.
    public struct PublishedEvent has copy, drop {
        faucet: ID,
        treasury: ID,
        metadata: ID,
    }

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
        let faucet = Faucet {
            id: object::new(ctx),
            treasury: option::none(),
        };

        sui::event::emit(PublishedEvent {
            faucet: object::id(&faucet),
            treasury: object::id(&treasury),
            metadata: object::id(&metadata),
        });

        transfer::public_transfer(treasury, ctx.sender());
        transfer::public_transfer(metadata, ctx.sender());
        // by default, faucet is disabled
        transfer::share_object(faucet);
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
