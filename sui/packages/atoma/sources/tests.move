#[test_only]
module atoma::db_tests {
    use atoma::db::{Self, AtomaDb, TaskBadge, EInvalidTaskRole, EInvalidSecurityLevel, EModelNotFound, ETaskNotFound, ETaskAlreadyDeprecated, ETaskNotDeprecated, 
        ENotEnoughEpochsPassed, NodeBadge, ETaskDeprecated, EInvalidPricePerComputeUnit, EInvalidMaxNumComputeUnits, ENodeAlreadySubscribedToTask, ENodeNotSubscribedToTask};
    use sui::test_scenario::{Self as test, Scenario};
    use std::ascii;

    const ADMIN: address = @0xAD;
    const USER: address = @0xB0B;

    const INFERENCE_ROLE: u16 = 0;

    fun setup_test(): Scenario {
        let mut scenario = test::begin(ADMIN);
        // Initialize the AtomaDb
        {
            db::init_for_testing(test::ctx(&mut scenario));
        };
        scenario
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
            
            // Create basic task with minimal parameters
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE, // role
                option::none(), // model_name
                option::none(), // security_level
                option::none(), // minimum_reputation_score
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
            
            // Create task with all optional parameters
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name (none since we haven't registered any models)
                option::some(1),                   // security_level    
                option::none(),                    // minimum_reputation_score
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
            
            // Try to create task with invalid role
            db::create_task_entry(
                &mut db,
                999,                               // invalid role
                option::none(),                    // model_name
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
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
            
            // Try to create task with invalid security level
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name
                option::some(999),                 // invalid security level
                option::none(),                    // minimum_reputation_score
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EModelNotFound)]
    fun test_create_task_nonexistent_model() {
        let mut scenario = setup_test();
        
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            
            // Try to create task with non-existent model
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,                                     // role
                option::some(ascii::string(b"nonexistent_model")),  // non-existent model
                option::none(),                                     // security_level
                option::none(),                                     // minimum_reputation_score
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
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
            
            // Create first task
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            // Create second task
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,                    // role
                option::none(),                    // model_name    
                option::none(),                    // security_level
                option::none(),                    // minimum_reputation_score
                test::ctx(&mut scenario)
            );

            test::return_shared(db);
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
            
            // Create basic task
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            
            // Create basic task
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            
            // Create task with future valid_until_epoch
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
    #[expected_failure(abort_code = ENotEnoughEpochsPassed)]
    fun test_remove_recently_deprecated_task() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price_per_compute_unit
                1000,    // max_num_compute_units
            );
            
            // Verify subscription
            assert!(db::is_node_subscribed_to_task(&db, &node_badge, 1), 0);
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 100, 1);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 1000, 2);
            
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
                100, // price_per_compute_unit
                1000 // max_num_compute_units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price_per_compute_unit
                1000     // max_num_compute_units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(), 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price_per_compute_unit
                1000     // max_num_compute_units
            );
            
            // Try to subscribe again
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // same task_small_id
                200,     // different price
                2000     // different max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                1000     // max_num_compute_units
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMaxNumComputeUnits)]
    fun test_subscribe_with_zero_compute_units() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
        };

        // Second tx: Register a node
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_test_node(&mut db, test::ctx(&mut scenario));
            
            test::return_shared(db);
        };

        // Third tx: Try to subscribe with zero compute units
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            let mut node_badge = test::take_from_sender<NodeBadge>(&scenario);
            
            db::subscribe_node_to_task(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                100,     // price_per_compute_unit
                0        // zero compute units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // initial price
                1000     // initial max units
            );
            
            // Update subscription
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                200,     // new price
                2000     // new max units
            );
            
            // Verify the update
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 200, 0);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2000, 1);
            
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
                2000     // max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                200,     // price
                2000     // max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price
                1000     // max units
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
                200,     // new price
                2000     // new max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // initial price
                1000     // initial max units
            );
            
            // Try to update with zero price
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                0,       // zero price
                2000     // max units
            );
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidMaxNumComputeUnits)]
    fun test_update_subscription_zero_compute_units() {
        let mut scenario = setup_test();
        
        // First tx: Create a task
        test::next_tx(&mut scenario, USER);
        {
            let mut db = test::take_shared<AtomaDb>(&scenario);
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(), 
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // initial price
                1000     // initial max units
            );
            
            // Try to update with zero compute units
            db::update_node_subscription(
                &mut db,
                &mut node_badge,
                1,       // task_small_id
                200,     // price
                0        // zero compute units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price
                1000     // max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price
                1000     // max units
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
            db::create_task_entry(
                &mut db,
                INFERENCE_ROLE,
                option::none(),
                option::none(),
                option::none(),
                test::ctx(&mut scenario)
            );
            test::return_shared(db);
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
                100,     // price
                1000     // max units
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
                200,     // new price
                2000     // new max units
            );
            
            // Verify new subscription parameters
            assert!(db::is_node_subscribed_to_task(&db, &node_badge, 1), 0);
            assert!(db::get_node_subscription_price(&db, 1, db::get_node_badge_small_id(&node_badge)) == 200, 1);
            assert!(db::get_node_subscription_max_units(&db, 1, db::get_node_badge_small_id(&node_badge)) == 2000, 2);
            
            test::return_shared(db);
            test::return_to_sender(&scenario, node_badge);
        };
        test::end(scenario);
    }
}
