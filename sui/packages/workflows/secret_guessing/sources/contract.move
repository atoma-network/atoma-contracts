module secret_guessing::contract {
    //! # Secret Guessing Contract
    //!
    //! This contract manages the game state and interactions with the AI agent.
    //! It also keeps track of the treasury pool and distributes the prize to the winner.
    
    use std::ascii::String;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    /// The initial fee rate increase per guess
    const InitialFeeRateIncreasePerGuessPerMille: u64 = 100;
    /// The percentage of the treasury pool that will be given to the winner
    const WinnerPercentageOfTreasuryPoolPerMille: u64 = 70;
    /// The initial fee for the first guess
    const StartingFee: u64 = 1000;
    /// The number of guesses after which the fee will be updated
    const UpdateFeeEveryNGuesses: u64 = 100;

    /// The address of the developer of the contract
    const ATOMA_DEV_ADDRESS: address = @0x0;
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

        /// The percentage of the treasury pool that will be given to the winner
        percentage_treasury_to_winner_per_mille: u64,

        /// The AI agent address that will be used to guess the secret
        agent_address: address,

        /// The address of the developer of the contract
        dev_address: address,

        /// The number of guesses after which the fee will be updated
        update_fee_every_n_guesses: u64,
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
            guess_count: 0,
            next_fee: StartingFee,
            is_active: true,
            fee_rate_increase_per_guess_per_mille: InitialFeeRateIncreasePerGuessPerMille,
            percentage_treasury_to_winner_per_mille: WinnerPercentageOfTreasuryPoolPerMille,
            dev_address: ATOMA_DEV_ADDRESS,
            agent_address: AI_AGENT_ADDRESS,
            update_fee_every_n_guesses: UpdateFeeEveryNGuesses,
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
        
        // 5. Emit the new guess event
        sui::event::emit(NewGuessEvent { 
            fee: db.next_fee,
            guess: guess,
            guess_count: db.guess_count,
            treasury_pool_balance: balance::value(&db.treasury_pool),
        });

        // 6. Return the guess badge
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
        let winner_amount = total_balance * db.percentage_treasury_to_winner_per_mille / 1000;
        let dev_amount = total_balance - winner_amount;

        // Split the winner's portion and convert to Coin
        let winner_balance = balance::split(&mut db.treasury_pool, winner_amount);
        let winner_coin = coin::from_balance(winner_balance, ctx);
        
        // Split the dev's portion and convert to Coin
        let dev_balance = balance::split(&mut db.treasury_pool, dev_amount);
        let dev_coin = coin::from_balance(dev_balance, ctx);

        // Transfer to respective addresses
        transfer::public_transfer(winner_coin, winner_address);
        transfer::public_transfer(dev_coin, ATOMA_DEV_ADDRESS);
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
    /// * Only callable by the holder of the AtomaSecretGuessingManagerBadge
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

    /// Updates the developer address that receives a portion of the treasury pool funds.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `_` - Reference to the manager badge for access control
    /// * `new_dev_address` - The new address that will receive developer funds
    ///
    /// # Effects
    /// * Updates the `dev_address` field in the database
    ///
    /// # Access Control
    /// * Only callable by the holder of the AtomaSecretGuessingManagerBadge
    public fun set_dev_address(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_dev_address: address,
    ) {
        db.dev_address = new_dev_address;
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
    /// * Only callable by the holder of the AtomaSecretGuessingManagerBadge
    public fun set_agent_address(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_agent_address: address,
    ) {
        db.agent_address = new_agent_address;
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
    /// * Only callable by the holder of the AtomaSecretGuessingManagerBadge
    public fun set_starting_fee(
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
    /// * Only callable by the holder of the AtomaSecretGuessingManagerBadge
    public fun set_update_fee_every_n_guesses(
        db: &mut AtomaSecretGuessingDb,
        _: &AtomaSecretGuessingManagerBadge,
        new_update_fee_every_n_guesses: u64,
    ) {
        db.update_fee_every_n_guesses = new_update_fee_every_n_guesses;
    }

    // ||================================||
    // ||          Utility functions     ||
    // ||================================||

    /// Deposits a fee from the provided wallet balance into the treasury pool.
    /// The fee amount is determined by the current fee rate increase per guess setting.
    /// 
    /// # Arguments
    /// * `db` - Mutable reference to the AtomaSecretGuessingDb object
    /// * `wallet` - Mutable reference to the balance from which the fee will be deducted
    ///
    /// # Effects
    /// * Splits the fee amount from the provided wallet balance
    /// * Adds the fee to the treasury pool balance
    ///
    /// # Access Control
    /// * This function can be called by anyone with access to an AtomaSecretGuessingDb object
    /// and a Balance<SUI>
    public fun deposit_fee_to_treasury_pool(
        db: &mut AtomaSecretGuessingDb, 
        wallet: &mut Balance<SUI>,
    ) {
        let fee = wallet.split(db.next_fee);
        db.treasury_pool.join(fee);
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