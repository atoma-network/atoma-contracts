#[test_only]
module guess_ai::guess_ai_tests {
    use std::ascii::Self;
    use guess_ai::contract::{Self, AtomaSecretGuessingDb, GuessBadge};
    use sui::test_scenario::{Self as test, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    const SYSTEM: address = @0x0;
    const ADMIN: address = @0xAD;
    const USER: address = @0xB0B;

    const MINT_AMOUNT: u64 = 1_000_000_000_000;

    fun setup_test(): Scenario {
        let mut scenario = test::begin(SYSTEM);  // Start scenario with SYSTEM address
        // Initialize the AtomaDb and Random object
        {
            contract::init_for_testing(test::ctx(&mut scenario));
            sui::random::create_for_testing(test::ctx(&mut scenario));
        };
        
        scenario
    }

    fun mint_test_tokens(scenario: &mut Scenario, recipient: address, amount: u64) {
        test::next_tx(scenario, ADMIN);
        {
            // Create test coins and transfer to recipient
            let coin = coin::mint_for_testing<SUI>(amount, test::ctx(scenario));
            transfer::public_transfer(coin, recipient);
        };
    }

    #[test]
    fun test_guess_entry_success() { 
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Initialize DB as ADMIN
        test::next_tx(&mut scenario, ADMIN);
        {
            contract::init_for_testing(test::ctx(&mut scenario));
        };

        // Second tx: Create task as USER
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaSecretGuessingDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<SUI>>(&scenario);

            // Create basic task with minimal parameters
            contract::guess_entry(
                &mut db,
                &mut wallet,
                ascii::string(b"my_guess"),
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_to_sender(&scenario, wallet);
        };

        // Verify task creation in a new transaction
        test::next_tx(&mut scenario, USER);
        {
            // Get the task badge that was transferred to the sender
            let guess_badge = test::take_from_sender<GuessBadge>(&scenario);
            let wallet = test::take_from_sender<Coin<SUI>>(&scenario);

            // Verify guess badge properties and wallet balance updates
            assert!(contract::verify_guess_badge_id(&guess_badge), 0);
            assert!(wallet.value() == MINT_AMOUNT - 1000, 1);
            
            test::return_to_sender(&scenario, guess_badge);
            test::return_to_sender(&scenario, wallet);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = secret_guessing::contract::EInsufficientBalance)]
    fun test_guess_entry_insufficient_balance() {
        let mut scenario = setup_test();
        
        // Mint small amount of tokens to USER (less than required fee)
        mint_test_tokens(&mut scenario, USER, 999); // Less than StartingFee (1000)

        test::next_tx(&mut scenario, ADMIN);
        {
            contract::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaSecretGuessingDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<SUI>>(&scenario);

            // Should fail due to insufficient balance
            contract::guess_entry(
                &mut db,
                &mut wallet,
                ascii::string(b"my_guess"),
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_to_sender(&scenario, wallet);
        };

        test::end(scenario);
    }

    #[test]
    fun test_guess_entry_multiple_guesses() {
        let mut scenario = setup_test();
        
        // Mint enough tokens for multiple guesses
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        test::next_tx(&mut scenario, ADMIN);
        {
            contract::init_for_testing(test::ctx(&mut scenario));
        };

        // Make multiple guesses and verify increasing fees
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaSecretGuessingDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<SUI>>(&scenario);
            let initial_balance = coin::value(&wallet);

            // First guess
            contract::guess_entry(
                &mut db,
                &mut wallet,
                ascii::string(b"guess_1"),
                test::ctx(&mut scenario)
            );

            // Second guess
            contract::guess_entry(
                &mut db,
                &mut wallet,
                ascii::string(b"guess_2"),
                test::ctx(&mut scenario)
            );

            // Verify wallet balance after two guesses
            let final_balance = coin::value(&wallet);
            assert!(initial_balance - final_balance == 2000, 1); // Two guesses at 1000 each

            test::return_shared(db);
            test::return_to_sender(&scenario, wallet);
        };

        // Verify both guess badges were received
        test::next_tx(&mut scenario, USER);
        {
            let guess_badge1 = test::take_from_sender<GuessBadge>(&scenario);
            let guess_badge2 = test::take_from_sender<GuessBadge>(&scenario);

            assert!(contract::verify_guess_badge_id(&guess_badge1), 2);
            assert!(contract::verify_guess_badge_id(&guess_badge2), 3);

            test::return_to_sender(&scenario, guess_badge1);
            test::return_to_sender(&scenario, guess_badge2);
        };

        test::end(scenario);
    }

    #[test]
    fun test_guess_entry_fee_increase_after_n_guesses() {
        let mut scenario = setup_test();
        
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        test::next_tx(&mut scenario, ADMIN);
        {
            contract::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaSecretGuessingDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<SUI>>(&scenario);
            let initial_balance = coin::value(&wallet);

            // Make 100 guesses (UpdateFeeEveryNGuesses)
            let mut i = 0;
            while (i < 100) {
                contract::guess_entry(
                    &mut db,
                    &mut wallet,
                    ascii::string(b"guess"),
                    test::ctx(&mut scenario)
                );
                i = i + 1;
            };

            // The 101st guess should cost more
            contract::guess_entry(
                &mut db,
                &mut wallet,
                ascii::string(b"expensive_guess"),
                test::ctx(&mut scenario)
            );

            let final_balance = coin::value(&wallet);
            let total_spent = initial_balance - final_balance;
            // First 100 guesses cost 1000 each, 101st guess costs 1100 (10% increase)
            assert!(total_spent == (100 * 1000 + 1100), 1);

            test::return_shared(db);
            test::return_to_sender(&scenario, wallet);
        };

        test::end(scenario);
    }
}
