module guess_ai::contract {
    //! # Secret Guessing Contract
    //!
    //! This contract manages the game state and interactions with the AI agent.
    //! It also keeps track of the treasury pool and distributes the prize to the winner.
    
    use std::ascii::String;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::random::Random;
    use sui::sui::SUI;

    /// The initial fee rate increase per guess
    const InitialFeeRateIncreasePerGuessPerMille: u64 = 100; // 10%
    /// The protocol fee per guess applied by the protocol
    const ProtocolFeePerMille: u64 = 50; // 5%
    /// The initial fee for the first guess
    const StartingFee: u64 = 1000;
    /// The number of guesses after which the fee will be updated
    const UpdateFeeEveryNGuesses: u64 = 100;

    /// The address of the AI agent that will be used to guess the secret
    const AI_AGENT_ADDRESS: address = @0x0;

    /// Base error code
    const EBase: u64 = 312012_000;
    /// The total permille must be less than 1000
    const ETotalPermilleMustBeLessThan1000: u64 = EBase + 1;
    /// Insufficient balance for guessing secret
    const EInsufficientBalance: u64 = EBase + 2;
    /// Only the AI agent can withdraw funds from the treasury pool
    const EOnlyAgentCanWithdrawFunds: u64 = EBase + 3;
    /// Only the AI agent can resubmit the TDX attestation
    const EOnlyAgentCanResubmitRemoteAttestation: u64 = EBase + 4;

    /// Event emitted when the contract is initialized
    public struct PublishEvent has copy, drop { 
        /// The ID of the newly created AtomaSecretGuessingDb object
        id: ID,

        /// The ID of the manager badge that has administrative privileges
        manager_badge: ID,
    }

    /// Event emitted when a new guess is made by some participant
    public struct NewGuessEvent has copy, drop {
        /// The fee paid by the participant
        fee: u64,

        /// The guess made by the participant
        guess: String,

        /// The total number of guesses made
        guess_count: u64,

        /// The balance of the treasury pool
        treasury_pool_balance: u64,
    }

    /// Event emitted when the TDX quote needs to be rotated by the AI agent
    /// and a new secret guessing game is started
    public struct RotateTdxQuoteEvent has copy, drop {
        /// The epoch at which the TDX quote was rotated
        epoch: u64,

        /// Random seed to be used for inference
        random_seed: u64
    }

    /// Event emitted when the TDX quote is resubmitted by the AI agent
    public struct TDXQuoteResubmittedEvent has copy, drop {
        /// The epoch at which the TDX quote was resubmitted
        epoch: u64,

        /// The TDX quote V4
        tdx_quote_v4: vector<u8>,

        /// The public key bytes of the AI agent for encrypted AI inference
        public_key_bytes: vector<u8>,
    }

    /// A badge that represents the manager of the AtomaSecretGuessingDb object
    public struct AtomaSecretGuessingManagerBadge has key, store {
        /// The ID of the manager badge
        id: UID,
    }

    /// A badge that represents a guess made by a participant
    public struct GuessBadge has key, store {
        /// The ID of the guess badge
        id: UID,
    }

    /// The main object of the contract, it stores the full secret guessing 
    /// state, including the treasury pool, the guess count, etc.
    public struct AtomaSecretGuessingDb has key {
        /// The ID of the database object
        id: UID,

        /// The balance of the treasury pool
        treasury_pool: Balance<SUI>,

        /// The current fee for the next guess
        next_fee: u64,

        /// The total number of guesses made
        guess_count: u64,

        /// Whether the secret guessing is still ongoing or not. It stops when
        /// the secret is successfully guessed.
        is_active: bool,

        /// The fee rate increase per guess
        fee_rate_increase_per_guess_per_mille: u64,

        /// The protocol fee per guess applied by the protocol
        protocol_fee_per_mille: u64,

        /// The protocol treasury address
        protocol_fee_pool: Balance<SUI>,

        /// The AI agent address that will be used to guess the secret
        agent_address: address,

        /// The number of guesses after which the fee will be updated
        update_fee_every_n_guesses: u64,

        /// The address of the winner
        winner_address: Option<address>,
    }        

    /// Initializes the secret guessing game by creating and sharing the main database object
    /// and transferring the manager badge to the deployer.
    /// 
    /// # Arguments
    /// * `ctx` - The transaction context used to create new objects and access the sender
    ///
    /// # Effects
    /// * Creates and shares an `AtomaSecretGuessingDb` object with:
    ///   - An empty treasury pool
    ///   - Zero guess count
    ///   - Active game state
    /// * Creates and transfers an `AtomaSecretGuessingManagerBadge` to the transaction sender
    /// * Emits a `PublishEvent` with the IDs of both created objects
    ///
    /// # Access Control
    /// * This function can only be called once during module initialization
    #[allow(unused_function)]
    fun init(ctx: &mut TxContext) {
        let db = AtomaSecretGuessingDb { 
            id: object::new(ctx),
            treasury_pool: balance::zero(),
            protocol_fee_pool: balance::zero(),
            guess_count: 0,
            next_fee: StartingFee,
            is_active: true,
            fee_rate_increase_per_guess_per_mille: InitialFeeRateIncreasePerGuessPerMille,
            protocol_fee_per_mille: ProtocolFeePerMille,
            agent_address: AI_AGENT_ADDRESS,
            update_fee_every_n_guesses: UpdateFeeEveryNGuesses,
            winner_address: std::option::none(),
        };

        let secret_guessing_db_badge = AtomaSecretGuessingManagerBadge { 
            id: object::new(ctx),
        };

        sui::event::emit(PublishEvent { 
            id: object::id(&db),
            manager_badge: object::id(&secret_guessing_db_badge),
        });

        transfer::share_object(db);
        transfer::transfer(secret_guessing_db_badge, ctx.sender());
    }

    /// Entry function that allows participants to make a guess in the secret guessing game.
    /// This function wraps the main `guess` function to provide a convenient entry point for
    /// transactions.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object that stores the game state
    /// * `wallet` - Mutable reference to the participant's SUI coin that will be used to pay the fee
    /// * `guess` - The participant's guess as a string
    /// * `ctx` - The transaction context used to access the sender and create new objects
    ///
    /// # Effects
    /// * Calls the `guess` function with the provided parameters
    /// * Transfers the resulting GuessBadge to the transaction sender
    ///
    /// # Example
    /// ```
    /// guess_entry(
    ///     &mut db,
    ///     &mut my_sui_coin,
    ///     ascii::string("my_guess"),
    ///     ctx
    /// );
    /// ```
    entry fun guess_entry(
        db: &mut AtomaSecretGuessingDb,
        wallet: &mut Coin<SUI>,
        guess: String,
        ctx: &mut TxContext,
    ) {
        let badge = guess(db, wallet.balance_mut(), guess, ctx);
        transfer::transfer(badge, ctx.sender());
    }

    /// Allows the AI agent to resubmit their TDX attestation quote.
    /// This function is used to maintain an up-to-date on-chain TDX quote for the AI agent.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `tdx_quote_v4` - The new TDX quote in V4 format as a byte vector
    /// * `ctx` - The transaction context used to access the sender and epoch
    ///
    /// # Effects
    /// * Emits a `TDXQuoteResubmittedEvent` with the current epoch and new TDX quote
    ///
    /// # Aborts
    /// * If the transaction sender is not the registered AI agent (EOnlyAgentCanResubmitRemoteAttestation)
    ///
    /// # Access Control
    /// * Only callable by the registered AI agent address stored in `db.agent_address`
    public entry fun resubmit_tdx_attestation(
        db: &mut AtomaSecretGuessingDb,
        tdx_quote_v4: vector<u8>,
        public_key_bytes: vector<u8>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == db.agent_address, EOnlyAgentCanResubmitRemoteAttestation);
        sui::event::emit(TDXQuoteResubmittedEvent { 
            epoch: ctx.epoch(),
            tdx_quote_v4: tdx_quote_v4,
            public_key_bytes: public_key_bytes,
        });
    }

    /// Makes a guess in the secret guessing game and returns a badge representing the guess.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object that stores the game state
    /// * `wallet` - Mutable reference to the balance from which the fee will be paid
    /// * `guess` - The participant's guess as a string
    /// * `ctx` - The transaction context used to create new objects
    ///
    /// # Returns
    /// * `GuessBadge` - A badge representing the participant's guess
    ///
    /// # Effects
    /// * Increments the total guess count
    /// * Deducts the fee from the participant's wallet
    /// * Adds the fee to the treasury pool
    /// * Updates the fee for the next guess
    /// * Emits a `NewGuessEvent` with the guess details
    ///
    /// # Aborts
    /// * If the wallet has insufficient balance to pay the required fee
    ///
    /// # Events
    /// Emits a `NewGuessEvent` containing:
    /// * The fee paid
    /// * The guess string
    /// * The updated guess count
    /// * The current treasury pool balance
    public fun guess(
        db: &mut AtomaSecretGuessingDb,
        wallet: &mut Balance<SUI>,
        guess: String,
        ctx: &mut TxContext,
    ): GuessBadge {
        // 1. Check if the wallet has enough balance to pay for the guess
        assert!(
            balance::value(wallet) >= db.next_fee,
            EInsufficientBalance
        );

        // 2. Update the guess count
        db.guess_count = db.guess_count + 1;

        // 3. Deposit the fee to the treasury pool
        deposit_fee_to_treasury_pool(db, wallet);

        // 4. Update the next fee, if there have been N guesses for the current fee
        if (db.guess_count % db.update_fee_every_n_guesses == 0) {
            db.next_fee = db.next_fee + (db.fee_rate_increase_per_guess_per_mille * db.next_fee / 1000);
        };

        // 6. Emit the new guess event
        sui::event::emit(NewGuessEvent { 
            fee: db.next_fee,
            guess: guess,
            guess_count: db.guess_count,
            treasury_pool_balance: balance::value(&db.treasury_pool),
        });

        // 7. Return the guess badge
        GuessBadge { 
            id: object::new(ctx),
        }
    }

    /// Withdraws and distributes funds from the treasury pool to the winner and developer.
    /// The distribution is based on the configured percentage split between winner and developer.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `winner_address` - The address of the winner who will receive their portion of the funds
    /// * `ctx` - The transaction context used to create new coin objects and access the sender
    ///
    /// # Effects
    /// * Splits the treasury pool balance according to the configured percentage
    /// * Creates two new Coin objects for the winner and developer portions
    /// * Transfers the winner's portion to the provided winner address
    /// * Transfers the developer's portion to the configured developer address
    /// * Empties the treasury pool
    ///
    /// # Aborts
    /// * If the transaction sender is the AI agent (EOnlyAgentCanWithdrawFunds)
    ///
    /// # Access Control
    /// * Cannot be called by the AI agent address
    ///
    /// # Example Split Calculation
    /// If the treasury pool contains 1000 SUI and winner percentage is 70%:
    /// * Winner receives: 700 SUI (70%)
    /// * Developer receives: 300 SUI (30%)
    public fun withdraw_funds_from_treasury_pool(
        db: &mut AtomaSecretGuessingDb,
        winner_address: address,
        ctx: &mut TxContext,
    ) {
        assert!(
            db.agent_address != ctx.sender(),
            EOnlyAgentCanWithdrawFunds
        );

        let total_balance = balance::value(&db.treasury_pool);
        // Split the winner's portion and convert to Coin
        let total_balance = balance::split(&mut db.treasury_pool, total_balance);
        let total_balance_coin = coin::from_balance(total_balance, ctx);
        
        // Transfer to respective addresses
        transfer::public_transfer(total_balance_coin, winner_address);
    }

    // ||================================||
    // ||          Admin functions       ||
    // ||================================||

    /// Updates the fee rate increase per guess in permille (parts per thousand).
    /// This rate determines how much the fee increases with each subsequent guess.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_fee_rate_increase_per_guess_per_mille` - The new fee rate increase in permille (must be <= 1000)
    ///
    /// # Effects
    /// * Updates the `fee_rate_increase_per_guess_per_mille` field in the database
    ///
    /// # Aborts
    /// * If `new_fee_rate_increase_per_guess_per_mille` is greater than 1000
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public fun set_fee_rate_increase_per_guess_per_mille(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_fee_rate_increase_per_guess_per_mille: u64,
    ) {
        assert!(
            new_fee_rate_increase_per_guess_per_mille <= 1000,
            ETotalPermilleMustBeLessThan1000
        );
        db.fee_rate_increase_per_guess_per_mille = new_fee_rate_increase_per_guess_per_mille;
    }

    /// Sets the game to inactive, which means that no more guesses can be made.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    ///
    /// # Effects
    /// * Sets the `is_active` field in the database to false
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public entry fun set_game_inactive(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
    ) {
        db.is_active = false;
    }

    /// Updates the AI agent address that will be used to guess the secret.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_agent_address` - The new address that will be used to guess the secret
    ///
    /// # Effects
    /// * Updates the `agent_address` field in the database
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public entry fun set_agent_address(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_agent_address: address,
    ) {
        db.agent_address = new_agent_address;
    }

    /// Rotates the TDX quote by generating a new challenge nonce and emitting an event.
    /// 
    /// # Arguments
    /// * `_` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `random` - Reference to the random number generator
    /// * `ctx` - The transaction context used to access the sender and epoch
    ///
    /// # Effects
    /// * Emits a `RotateTdxQuoteEvent` with the current epoch and new challenge nonce
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    entry fun rotate_tdx_quote(
        _: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        random: &Random,
        ctx: &mut TxContext,
    ) {
        let mut rng = random.new_generator(ctx);
        let random_seed = rng.generate_u64();
        sui::event::emit(RotateTdxQuoteEvent { 
            epoch: ctx.epoch(),
            random_seed,
        });
    }

    /// Sets the starting fee for the first guess.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_starting_fee` - The new starting fee for the first guess
    ///
    /// # Effects
    /// * Updates the `next_fee` field in the database
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public entry fun set_starting_fee(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_starting_fee: u64,
    ) {
        db.next_fee = new_starting_fee;
    }

    /// Sets the number of guesses after which the fee will be updated.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_update_fee_every_n_guesses` - The new number of guesses after which the fee will be updated
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public entry fun set_update_fee_every_n_guesses(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_update_fee_every_n_guesses: u64,
    ) {
        db.update_fee_every_n_guesses = new_update_fee_every_n_guesses;
    }

    /// Sets the protocol fee per guess applied by the protocol
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_protocol_fee_per_mille` - The new protocol fee per guess in permille (must be <= 1000)
    ///
    /// # Aborts
    /// * If `new_protocol_fee_per_mille` is greater than 1000
    ///
    /// # Access Control
    /// * Only callable by the holder of the [`AtomaSecretGuessingManagerBadge`]
    public fun set_protocol_fee_per_mille(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_protocol_fee_per_mille: u64,
    ) {
        db.protocol_fee_per_mille = new_protocol_fee_per_mille;
    }

    // ||================================||
    // ||          Utility functions     ||
    // ||================================||

    /// Deposits a fee from the provided wallet balance into both the treasury pool and protocol fee pool.
    /// The fee is split between the treasury and protocol based on the protocol_fee_per_mille setting.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `wallet` - Mutable reference to the balance from which the fee will be deducted
    ///
    /// # Effects
    /// * Calculates protocol fee portion based on protocol_fee_per_mille
    /// * Splits the total fee into treasury and protocol portions
    /// * Adds the treasury portion to the treasury pool balance
    /// * Adds the protocol portion to the protocol fee pool balance
    ///
    /// # Example
    /// If next_fee is 1000 and protocol_fee_per_mille is 50 (5%):
    /// * Protocol fee = 50 (5% of 1000)
    /// * Treasury fee = 950 (remaining 95%)
    ///
    /// # Note
    /// This is an internal utility function used by the guess mechanism to handle
    /// fee distribution between the protocol and treasury pools.
    fun deposit_fee_to_treasury_pool(
        db: &mut AtomaSecretGuessingDb, 
        wallet: &mut Balance<SUI>,
    ) {
        let next_fee = db.next_fee;
        let protocol_fee = next_fee * db.protocol_fee_per_mille / 1000;
        let treasury_fee = next_fee - protocol_fee;
        let treasury_fee_balance = wallet.split(treasury_fee);
        let protocol_fee_balance = wallet.split(protocol_fee);

        db.treasury_pool.join(treasury_fee_balance);
        db.protocol_fee_pool.join(protocol_fee_balance);
    }

    // Test-only functions

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun verify_guess_badge_id(guess_badge: &GuessBadge): bool {
        let _id = object::uid_to_inner(&guess_badge.id);
        true
    }
}