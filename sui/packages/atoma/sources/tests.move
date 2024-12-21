#[test_only]
module atoma::db_tests {
    use atoma::db::{Self, AtomaDb, TaskBadge, EInvalidTaskRole, EInvalidSecurityLevel, ETaskNotFound, 
        ETaskAlreadyDeprecated, ETaskNotDeprecated, ENotEnoughEpochsPassed, NodeBadge, ETaskDeprecated, 
        EInvalidPricePerComputeUnit, ENodeAlreadySubscribedToTask, ENodeNotSubscribedToTask,
        StackBadge, EInvalidComputeUnits, EInsufficientBalance, ENoNodesSubscribedToTask, ENodeNotSelectedForStack, 
        ETooManyComputedUnits, EStackInSettlementDispute, EInvalidCommittedStackProof, EInvalidStackMerkleLeaf, 
        ENoNodesEligibleForTask, ETaskIsPublic, ENodeNotWhitelistedForTask, AtomaManagerBadge,
    };
    use sui::test_scenario::{Self as test, Scenario};
    use sui::coin::{Self, Coin};
    use sui::random::Random;
    use usdc::usdc::USDC;

    const SYSTEM: address = @0x0;
    const ADMIN: address = @0xAD;
    const USER: address = @0xB0B;
    const NODE: address = @0xB0C;
    const NODE2: address = @0xB0D;

    const INFERENCE_ROLE: u16 = 0;

    // At the top of the module, add these test-only constants for coin amounts
    const MINT_AMOUNT: u64 = 1_000_000_000; // 1 billion tokens for testing

    fun setup_test(): Scenario {
        let mut scenario = test::begin(SYSTEM);  // Start scenario with SYSTEM address
        // Initialize the AtomaDb and Random object
        {
            db::init_for_testing(test::ctx(&mut scenario));
            sui::random::create_for_testing(test::ctx(&mut scenario));
        };
        
        scenario
    }

    fun mint_test_tokens(scenario: &mut Scenario, recipient: address, amount: u64) {
        test::next_tx(scenario, ADMIN);
        {
            // Create test coins and transfer to recipient
            let coin = coin::mint_for_testing<USDC>(amount, test::ctx(scenario));
            transfer::public_transfer(coin, recipient);
        };
    }

    #[test]
    fun test_create_task_basic_success() {
        let mut scenario = setup_test();
        
        // First tx: Initialize DB as ADMIN
        test::next_tx(&mut scenario, ADMIN);
        {
            db::init_for_testing(test::ctx(&mut scenario));
        };

        // Second tx: Create task as USER
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            // Create basic task with minimal parameters
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE, // role
                option::none(), // model_name
                option::none(), // security_level
                option::none(), // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)

            );

            // Return the modified db to commit changes
            test::return_shared(db);

            // Verify task creation in a new transaction
            test::next_tx(&mut scenario, USER);
            {
                // Get the task badge that was transferred to the sender
                let task_badge = test::take_from_sender<TaskBadge>(&scenario);
                
                // Verify task badge properties
                assert!(db::verify_task_badge_id(&task_badge), 0);
                assert!(db::get_task_badge_small_id(&task_badge) == 1, 1);
                
                test::return_to_sender(&scenario, task_badge);
            };

            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_create_task_with_all_parameters() {
        let mut scenario = setup_test();
        
        // First tx: Initialize DB as ADMIN
        test::next_tx(&mut scenario, ADMIN);
        {
            db::init_for_testing(test::ctx(&mut scenario));
        };

        // Second tx: Create task as USER
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            // Create task with all optional parameters
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name (none since we haven't registered any models)
                option::some(1),                   // security_level    
                option::none(),                    // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)    
            );

            // Return the modified db to commit changes
            test::return_shared(db);

            // Verify task creation in a new transaction
            test::next_tx(&mut scenario, USER);
            {
                // Get the task badge that was transferred to the sender
                let task_badge = test::take_from_sender<TaskBadge>(&scenario);
                
                // Verify task badge properties
                assert!(db::verify_task_badge_id(&task_badge), 0);
                assert!(db::get_task_badge_small_id(&task_badge) == 1, 1);
                
                test::return_to_sender(&scenario, task_badge);
            };

            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidTaskRole)]
    fun test_create_task_invalid_role() {
        let mut scenario = setup_test();
        
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            
            // Try to create task with invalid role
            db::create_task_entry(
                &mut db,
                &manager_badge,
                999,                               // invalid role
                option::none(),                    // model_name
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidSecurityLevel)]
    fun test_create_task_invalid_security_level() {
        let mut scenario = setup_test();
        
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            // Try to create task with invalid security level
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name
                option::some(999),                 // invalid security level
                option::none(),                    // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_create_multiple_tasks() {
        let mut scenario = setup_test();
        
        // First tx: Initialize DB as ADMIN
        test::next_tx(&mut scenario, ADMIN);
        {
            db::init_for_testing(test::ctx(&mut scenario));
        };

        // Second tx: Create tasks as USER
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            
            // Create first task
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        test::next_tx(&mut scenario, USER);
        {
            // Get the task badges that were transferred to the sender
            let task_badge1 = test::take_from_sender<TaskBadge>(&scenario); 
            
            // Verify task badge properties
            assert!(db::verify_task_badge_id(&task_badge1), 0);
            assert!(db::get_task_badge_small_id(&task_badge1) == 1, 2);
            
            test::return_to_sender(&scenario, task_badge1);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            // Create second task
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name    
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                true, // is_public
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Verify task creation in a new transaction
        test::next_tx(&mut scenario, USER);
        {
            // Get the task badges that were transferred to the sender
            let task_badge2 = test::take_from_sender<TaskBadge>(&scenario);
            
            // Verify task badge properties
            assert!(db::verify_task_badge_id(&task_badge2), 0);
            assert!(db::get_task_badge_small_id(&task_badge2) == 2, 1);
            
            test::return_to_sender(&scenario, task_badge2);
        };
        test::end(scenario);
    }

    #[test]
    fun test_deprecate_task_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task as USER
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            
            // Create basic task
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            let task_small_id = db::get_task_badge_small_id(&task_badge);
            
            // Deprecate the task
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            assert!(db::check_deprecated_task(&db, task_small_id), 0);
            assert!(db::check_task_deprecated_epoch_at(&db, task_small_id, test::ctx(&mut scenario).epoch()), 1);

            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_deprecate_nonexistent_task() {
        let mut scenario = setup_test();
        
        // Create an invalid task badge (not actually created in the DB)
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let invalid_task_badge = db::create_task_badge_for_testing(test::ctx(&mut scenario), 999);
            
            // Try to deprecate a non-existent task
            db::deprecate_task(&mut db, &invalid_task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, invalid_task_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskAlreadyDeprecated)]
    fun test_deprecate_already_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create and deprecate a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            
            // Create basic task
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task first time
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            // Deprecate the task
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            // Try to deprecate the same task again
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_deprecate_task_with_future_valid_until() {
        let mut scenario = setup_test();
        
        // First tx: Create a task with future valid_until_epoch
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
            // Create task with future valid_until_epoch
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            // Deprecate the task
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
                        
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_remove_deprecated_task_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };

        // Advance 2 epochs
        test::next_epoch(&mut scenario, USER);
        test::next_epoch(&mut scenario, USER);

        test::next_tx(&mut scenario, USER);

        // Remove the deprecated task
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            let task_small_id = db::get_task_badge_small_id(&task_badge);
            
            // Verify task exists before removal
            assert!(db::check_task_exists(&db, task_small_id), 0);
            
            db::remove_deprecated_task(&mut db, task_badge, test::ctx(&mut scenario));
            
            // Verify task no longer exists
            assert!(!db::check_task_exists(&db, task_small_id), 1);
            
            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_remove_nonexistent_task() {
        let mut scenario = setup_test();
        
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let invalid_task_badge = db::create_task_badge_for_testing(test::ctx(&mut scenario), 999);
            
            db::remove_deprecated_task(&mut db, invalid_task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotDeprecated)]
    fun test_remove_non_deprecated_task() {
        let mut scenario = setup_test();
        
        // Create a task but don't deprecate it
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Try to remove the non-deprecated task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::remove_deprecated_task(&mut db, task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    fun test_whitelist_nodes_for_task_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                false, // is_public
                test::ctx(&mut scenario)
            );

            // Create nodes vector and whitelist them
            let mut nodes = vector::empty<u64>();
            vector::push_back(&mut nodes, 1);
            vector::push_back(&mut nodes, 2);
            vector::push_back(&mut nodes, 3);

            db::whitelist_nodes_for_task(
                &mut db,
                &manager_badge,
                1, // task_small_id
                nodes
            );

            // Verify nodes are whitelisted
            assert!(db::is_node_whitelisted_for_task(&db, 1, 1), 0);
            assert!(db::is_node_whitelisted_for_task(&db, 1, 2), 1);
            assert!(db::is_node_whitelisted_for_task(&db, 1, 3), 2);

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_whitelist_nodes_for_nonexistent_task() {
        let mut scenario = setup_test();
        
        // Try to whitelist nodes for nonexistent task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            let mut nodes = vector::empty<u64>();
            vector::push_back(&mut nodes, 1);
            
            db::whitelist_nodes_for_task(
                &mut db,
                &manager_badge,
                999, // nonexistent task_small_id
                nodes
            );

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskIsPublic)]
    fun test_whitelist_nodes_for_public_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a private task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );

            // Try to whitelist nodes for private task
            let mut nodes = vector::empty<u64>();
            vector::push_back(&mut nodes, 1);

            db::whitelist_nodes_for_task(
                &mut db,
                &manager_badge,
                1, // task_small_id
                nodes
            );

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_whitelist_nodes_empty_vector() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                false, // is_public
                test::ctx(&mut scenario)
            );

            // Whitelist with empty vector (should succeed but do nothing)
            let nodes = vector::empty<u64>();
            
            db::whitelist_nodes_for_task(
                &mut db,
                &manager_badge,
                1, // task_small_id
                nodes
            );

            // Verify no nodes are whitelisted
            assert!(!db::is_node_whitelisted_for_task(&db, 1, 1), 0);

            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENotEnoughEpochsPassed)]
    fun test_remove_recently_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            // Try to remove immediately without waiting for epochs
            db::remove_deprecated_task(&mut db, task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    fun test_subscribe_node_to_task_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));

            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id   
                1000,    // price_per_one_million_compute_units
            );
            
            // Verify subscription
            assert!(db::is_node_subscribed_to_task(&db, &node_badge, 1), 0);
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 1000, 1);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2_560_000, 2);
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);  
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENodeNotWhitelistedForTask)]
    fun test_subscribe_node_to_private_task_panics() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                false, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));

            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id   
                1000,    // price_per_one_million_compute_units
            );

            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);  
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_subscribe_to_nonexistent_task() {
        let mut scenario = setup_test();
        
        // Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };

        // Try to subscribe to nonexistent task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                999, // nonexistent task_small_id
                1000 // price_per_one_million_compute_units
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskDeprecated)]
    fun test_subscribe_to_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };

        // Third tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };

        // Fourth tx: Try to subscribe to deprecated task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

   #[test]
    #[expected_failure(abort_code = ENodeAlreadySubscribedToTask)]
    fun test_subscribe_already_subscribed_node() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(), 
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task twice
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            // First subscription
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            
            // Try to subscribe again
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // same task_small_id
                200,     // different price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidPricePerComputeUnit)]
    fun test_subscribe_with_zero_price() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };

        // Third tx: Try to subscribe with zero price
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                0,       // zero price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_update_node_subscription_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe to task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            
            // Update subscription
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                2000     // new price
            );
            
            // Verify the update
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2000, 0);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2_560_000, 1);
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_update_subscription_nonexistent_task() {
        let mut scenario = setup_test();
        
        // First tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Second tx: Try to update subscription for nonexistent task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                999,     // nonexistent task_small_id
                200,     // price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENodeNotSubscribedToTask)]
    fun test_update_subscription_not_subscribed() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node but don't subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Try to update nonexistent subscription
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                2000     // price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskDeprecated)]
    fun test_update_subscription_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Third tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };

        // Fourth tx: Try to update subscription for deprecated task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                2000     // new price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidPricePerComputeUnit)]
    fun test_update_subscription_zero_price() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            
            // Try to update with zero price
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                0,       // zero price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_unsubscribe_node_success() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe to task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price
            );
            
            // Verify subscription before unsubscribing
            assert!(db::is_node_subscribed_to_task(&db, &node_badge, 1), 0);
            
            // Unsubscribe
            db::unsubscribe_node_from_task(
                &mut db,
                &mut node_badge,
                1        // task_small_id
            );
            
            // Verify unsubscription
            assert!(!db::is_node_subscribed_to_task(&db, &node_badge, 1), 1);
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_unsubscribe_nonexistent_task() {
        let mut scenario = setup_test();
        
        // First tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Second tx: Try to unsubscribe from nonexistent task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::unsubscribe_node_from_task(
                &mut db,
                &mut node_badge,
                999      // nonexistent task_small_id
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENodeNotSubscribedToTask)]
    fun test_unsubscribe_not_subscribed() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);
    
            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node but don't subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Try to unsubscribe without being subscribed
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::unsubscribe_node_from_task(
                &mut db,
                &mut node_badge,
                1        // task_small_id
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskDeprecated)]
    fun test_unsubscribe_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Third tx: Deprecate the task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let task_badge = test::take_from_sender<TaskBadge>(&scenario);
            
            db::deprecate_task(&mut db, &task_badge, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_to_sender(&scenario, task_badge);
        };

        // Fourth tx: Try to unsubscribe from deprecated task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::unsubscribe_node_from_task(
                &mut db,
                &mut node_badge,
                1        // task_small_id
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_unsubscribe_and_resubscribe() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(), 
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node and subscribe
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            // First subscription
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price
            );
            
            // Unsubscribe
            db::unsubscribe_node_from_task(
                &mut db,
                &mut node_badge,
                1        // task_small_id
            );
            
            // Resubscribe with different parameters
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                2000     // new price
            );
            
            // Verify new subscription parameters
            assert!(db::is_node_subscribed_to_task(&db, &node_badge, 1), 0);
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2000, 1);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2_560_000, 2);
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_acquire_new_stack_basic_success() {
        let mut scenario = setup_test();

        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Create a stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                100,        // num_compute_units
                1000,         // price
                &random,
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };
            
        // Verify stack creation
        test::next_tx(&mut scenario, USER);
        {
            let stack_badge = test::take_from_sender<StackBadge>(&scenario);
            assert!(db::verify_stack_badge_id(&stack_badge), 0);
            assert!(db::get_stack_badge_small_id(&stack_badge) == 1, 1);
            
            test::return_to_sender(&scenario, stack_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_acquire_new_stack_nonexistent_task() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                999,        // nonexistent task_small_id
                100,        // num_compute_units
                10,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidComputeUnits)]
    fun test_acquire_new_stack_zero_compute_units() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Try to create stack with zero compute units
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                0,          // zero compute_units
                1000,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidPricePerComputeUnit)]
    fun test_acquire_new_stack_zero_price() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Try to create stack with zero price
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                100,        // num_compute_units
                0,          // zero price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInsufficientBalance)]
    fun test_acquire_new_stack_insufficient_balance() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                10,     // price_per_one_million_compute_units             
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Try to create stack with insufficient balance
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut empty_wallet = coin::zero<USDC>(test::ctx(&mut scenario));
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut empty_wallet,
                1,          // task_small_id
                100,        // num_compute_units
                1000000,    // very high price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, empty_wallet);
        };
        test::end(scenario);
    }

    #[test]
    fun test_acquire_multiple_stacks() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario); 
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Create first stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                100,        // num_compute_units
                1000,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Verify first stack
        test::next_tx(&mut scenario, USER);
        {
            let stack_badge1 = test::take_from_sender<StackBadge>(&scenario);
            assert!(db::get_stack_badge_small_id(&stack_badge1) == 1, 0);
            test::return_to_sender(&scenario, stack_badge1);
        };

        // Fifth tx: Create second stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                200,        // different num_compute_units
                2000,         // different price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Verify second stack
        test::next_tx(&mut scenario, USER);
        {
            let stack_badge2 = test::take_from_sender<StackBadge>(&scenario);
            assert!(db::get_stack_badge_small_id(&stack_badge2) == 2, 1);
            test::return_to_sender(&scenario, stack_badge2);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENoNodesEligibleForTask)]
    fun test_try_settle_stack_node_price_too_high() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // First tx: Create task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task with high price
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            // Node sets a high price of 100 per compute unit
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units (high price)
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Create a stack with lower price expectation
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            // User creates stack willing to pay only 50 per compute unit
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                50,         // num_compute_units
                50,         // price_per_one_million_compute_units (lower than node's price)
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };
        test::end(scenario);
    }

    #[test]
    fun test_try_settle_stack_basic_success() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Create a stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                50,         // num_compute_units
                1000,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Fifth tx: Try to settle stack
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(
                &mut db,
                &node_badge,
                1,          // stack_small_id
                50,         // num_claimed_compute_units (equal to stack units)
                proof,      // committed_stack_proof
                leaf,       // stack_merkle_leaf
                &random,
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };

        // Verify settlement
        test::next_tx(&mut scenario, NODE);
        {
            let db = test::take_shared<AtomaDb>(&scenario);
            assert!(db::check_stack_settlement_exists(&db, 1), 0);
            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENoNodesSubscribedToTask)]
    fun test_try_settle_stack_wrong_selected_node() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Create a stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                50,         // num_compute_units
                10,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(
                &mut db,
                &node_badge,
                1,          // stack_small_id
                50,         // num_claimed_compute_units
                proof,      // committed_stack_proof
                leaf,       // stack_merkle_leaf
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENodeNotSelectedForStack)]
    fun test_try_settle_stack_wrong_node() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register first node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Register second node
        test::next_tx(&mut scenario, NODE2);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Fourth tx: Subscribe first node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                100     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fifth tx: Subscribe second node to task
        test::next_tx(&mut scenario, NODE2);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Sixth tx: Create a stack (will be assigned to first node)
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                50,         // num_compute_units
                100,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Seventh tx: Try to settle stack with wrong node
        test::next_tx(&mut scenario, NODE2);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(
                &mut db,
                &node_badge,
                1,          // stack_small_id
                50,         // num_claimed_compute_units
                proof,      // committed_stack_proof
                leaf,       // stack_merkle_leaf
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ETooManyComputedUnits)]
    fun test_try_settle_stack_excess_units() {
        let mut scenario = setup_test();
        
        // Mint tokens to USER for testing
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);

        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Second tx: Register node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        // Third tx: Subscribe node to task
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                1000     // price_per_one_million_compute_units
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Fourth tx: Create a stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::acquire_new_stack_entry(
                &mut db,
                &mut wallet,
                1,          // task_small_id
                50,         // num_compute_units
                1000,         // price
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Fifth tx: Try to settle stack with excess units
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(
                &mut db,
                &node_badge,
                1,          // stack_small_id
                100,        // num_claimed_compute_units (more than allocated 50)
                proof,      // committed_stack_proof
                leaf,       // stack_merkle_leaf
                &random,
                test::ctx(&mut scenario)
            );
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EStackInSettlementDispute)]
    fun test_try_settle_stack_already_settled() {
        let mut scenario = setup_test();
        
        // Standard setup
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // First tx: Create task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE, 
                option::none(),
                option::none(), 
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Setup node and subscription
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 1000);
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Create stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            db::acquire_new_stack_entry(
                &mut db, 
                &mut wallet, 
                1, 
                50, 
                1000, 
                &random, 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // First settlement attempt
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, proof, leaf, &random, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };

        // Second settlement attempt (should fail)
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, proof, leaf, &random, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidCommittedStackProof)]
    fun test_try_settle_stack_invalid_proof() {
        let mut scenario = setup_test();
        
        // Standard setup
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // Setup task, node, and stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db, 
                &manager_badge,
                INFERENCE_ROLE, 
                option::none(), 
                option::none(), 
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );      
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 1000);
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            db::acquire_new_stack_entry(
                &mut db, 
                &mut wallet, 
                1, 
                50, 
                1000, 
                &random, 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Try to settle with invalid proof length
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            let invalid_proof = x"0123"; // Too short
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, invalid_proof, leaf, &random, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidStackMerkleLeaf)]
    fun test_try_settle_stack_invalid_leaf() {
        let mut scenario = setup_test();
        
        // Standard setup
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // Setup task, node, and stack (similar to previous test)
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db, 
                &manager_badge,
                INFERENCE_ROLE, 
                option::none(), 
                option::none(), 
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            ); 
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 1000);
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            db::acquire_new_stack_entry(
                &mut db, 
                &mut wallet, 
                1, 
                50, 
                1000, 
                &random, 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Try to settle with invalid merkle leaf length
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let invalid_leaf = x"FEDC"; // Too short
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, proof, invalid_leaf, &random, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ENodeNotSelectedForStack)]
    fun test_try_settle_stack_with_sampling_consensus() {
        let mut scenario = setup_test();
        
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // Create task with SamplingConsensusSecurityLevel
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db,
                &manager_badge,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Setup multiple nodes for potential sampling
        let nodes = vector[@0xB0C, @0xB0D, @0xB0E, @0xB0F];
        let mut i = 0;
        while (i < vector::length(&nodes)) {
            test::next_tx(&mut scenario, *vector::borrow(&nodes, i));
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                db::create_test_node(&mut db, test::ctx(&mut scenario));
                test::return_shared(db);
            };

            test::next_tx(&mut scenario, *vector::borrow(&nodes, i));
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
                db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 10);
                test::return_shared(db);
                test::return_to_sender(&scenario, node_badge);
            };
            i = i + 1;
        };

        // Create and settle stack
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            db::acquire_new_stack_entry(
                &mut db, 
                &mut wallet, 
                1, 
                50, 
                1000, 
                &random, 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        test::next_tx(&mut scenario, *vector::borrow(&nodes, 0));
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
            let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, proof, leaf, &random, test::ctx(&mut scenario));
            
            // Verify that attestation nodes were sampled
            let settlement = db::get_stack_settlement(&db, 1);
            let num_requested_attestation_nodes = db::get_num_requested_attestation_nodes(settlement);
            assert!(num_requested_attestation_nodes > 0, 0);
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    fun test_try_settle_stack_multiple_stacks() {
        let mut scenario = setup_test();
        
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // Create task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let manager_badge = test::take_from_address<AtomaManagerBadge>(&scenario, SYSTEM);

            db::create_task_entry(
                &mut db, 
                &manager_badge,
                INFERENCE_ROLE, 
                option::none(), 
                option::none(), 
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            ); 
            test::return_shared(db);
            test::return_to_address(SYSTEM, manager_badge);
        };

        // Setup node
        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            test::return_shared(db);
        };

        test::next_tx(&mut scenario, NODE);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 1000);
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };

        // Create and settle multiple stacks
        let num_stacks = 3;
        let mut i = 0;
        while (i < num_stacks) {
            // Create stack
            test::next_tx(&mut scenario, USER);
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
                let random = test::take_shared<Random>(&scenario);
                db::acquire_new_stack_entry(
                    &mut db, 
                    &mut wallet, 
                    1, 
                    50, 
                    1000, 
                    &random, 
                    test::ctx(&mut scenario)
                );
                test::return_shared(db);
                test::return_shared(random);
                test::return_to_sender(&scenario, wallet);
            };

            // Settle stack
            test::next_tx(&mut scenario, NODE);
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                let node_badge = test::take_from_sender<NodeBadge>(&scenario);
                let random = test::take_shared<Random>(&scenario);
                let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
                let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";
                
                db::try_settle_stack(&mut db, &node_badge, (i as u64) + 1, 50, proof, leaf, &random, test::ctx(&mut scenario));
                
                test::return_shared(db);
                test::return_shared(random);
                test::return_to_sender(&scenario, node_badge);
            };

            // Verify settlement
            test::next_tx(&mut scenario, NODE);
            {
                let db = test::take_shared<AtomaDb>(&scenario);
                assert!(db::check_stack_settlement_exists(&db, (i as u64) + 1), i);
                test::return_shared(db);
            };
            
            i = i + 1;
        };
        test::end(scenario);
    }

    #[test]
    fun test_submit_stack_settlement_attestation_success() {
        let mut scenario = setup_test();
        
        mint_test_tokens(&mut scenario, USER, MINT_AMOUNT);
        
        // Create task with SamplingConsensusSecurityLevel
        test::next_tx(&mut scenario, SYSTEM);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let admin_badge = test::take_from_sender<AtomaManagerBadge>(&scenario);
            db::set_cross_validation_probability_permille(&mut db, &admin_badge, 1000);
            db::create_task_entry(
                &mut db,
                &admin_badge,
                INFERENCE_ROLE,
                option::none(),
                option::some(2), // Sampling Consensus security level
                option::none(),
                true, // is_public
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_to_sender(&scenario, admin_badge);
        };

        // Setup multiple nodes (1 main + 2 attestation nodes)
        let nodes = vector[@0xB0C, @0xB0D, @0xB0E];
        let mut i = 0;
        while (i < vector::length(&nodes)) {
            test::next_tx(&mut scenario, *vector::borrow(&nodes, i));
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                db::create_test_node(&mut db, test::ctx(&mut scenario));
                test::return_shared(db);
            };

            test::next_tx(&mut scenario, *vector::borrow(&nodes, i));
            {
                let mut db = test::take_shared<AtomaDb>(&scenario);
                let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
                db::subscribe_node_to_task(&mut db, &mut node_badge, 1, 1000);
                test::return_shared(db);
                test::return_to_sender(&scenario, node_badge);
            };
            i = i + 1;
        };

        // Create and initiate stack settlement
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut wallet = test::take_from_sender<Coin<USDC>>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            db::acquire_new_stack_entry(
                &mut db, 
                &mut wallet, 
                1, 
                50, 
                1000, 
                &random, 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, wallet);
        };

        // Main node initiates settlement
        let proof = x"0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        let leaf = x"FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210";

        test::next_tx(&mut scenario, @0xB0C);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            let random = test::take_shared<Random>(&scenario);
            
            db::try_settle_stack(&mut db, &node_badge, 1, 50, proof, leaf, &random, test::ctx(&mut scenario));
            
            test::return_shared(db);
            test::return_shared(random);
            test::return_to_sender(&scenario, node_badge);
        };

        // First attestation node submits attestation, this is the same node as the main node
        // as random always selects the first index for selection
        test::next_tx(&mut scenario, @0xB0C);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::submit_stack_settlement_attestation(
                &mut db,
                &node_badge,
                1,      // stack_small_id
                proof,  // same proof as original
                leaf,   // same leaf as original
                test::ctx(&mut scenario)
            );

            // Get necessary data for StackSettlementTicketEvent verification
            let settlement = db::get_stack_settlement(&db, 1);            
            let stack_badge = test::take_from_address<StackBadge>(&scenario, USER);

            assert!(db::compare_stack_and_settlement_ticket(&stack_badge, settlement), 0);
            assert!(db::get_num_requested_attestation_nodes(settlement) == 1, 0);
            assert!(db::compare_requested_attestation_nodes(settlement, 1), 0);
            assert!(db::confirm_stack_settlement_ticket_dispute_epoch(settlement, test::ctx(&mut scenario).epoch() + 2), 0);
            assert!(db::compare_already_attested_nodes(settlement, 1), 0);
            assert!(db::is_stack_settlement_ticket_disputed(settlement), 0);
            assert!(db::confirm_committed_stack_proof(settlement, proof, leaf), 0);

            test::return_shared(db);
            test::return_to_address(USER, stack_badge);
            test::return_to_sender(&scenario, node_badge);
        };
        
        test::end(scenario);
    }
}
