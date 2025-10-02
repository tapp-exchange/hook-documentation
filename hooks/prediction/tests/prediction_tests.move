#[test_only]
module tapp::prediction_tests {
    use std::option::{none, some};
    use std::string;
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::aptos_coin;
    use aptos_framework::coin::{BurnCapability, MintCapability};
    use aptos_framework::object;
    use tapp::fixtures::{
        init,
        create_prediction_pool,
        add_liquidity_prediction_pool,
        remove_liquidity_prediction_pool,
        swap_prediction_pool,
        create_prediction_pool_add_liquidity
    };
    use tapp::router::{Self, PoolCreated, LiquidityAdded, LiquidityRemoved, Swapped};
    use tapp::test_coins;
    use tapp::hook_factory::{hook_type, assets};
    use VeriFiPublisher::verifi_protocol::{Self, Market};
    use VeriFiPublisher::oracle_registry;
    use VeriFiPublisher::access_control;

    // Test capabilities storage
    struct TestCaps has key {
        burn_cap: BurnCapability<aptos_coin::AptosCoin>,
        mint_cap: MintCapability<aptos_coin::AptosCoin>,
    }

    // Constants
    const OCTAS_PER_APT: u64 = 100000000;
    const OPERATOR_GREATER_THAN: u8 = 0;

    // Helper function to setup VeriFi protocol
    fun setup_verifi_protocol(admin: &signer) {
        // Initialize AptosCoin
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&account::create_signer_for_test(@0x1));

        // Initialize VeriFi modules
        access_control::init_for_test(admin);
        oracle_registry::init_for_test(admin);
        verifi_protocol::init_for_test(admin);

        // Store capabilities
        move_to(admin, TestCaps { burn_cap, mint_cap });

        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        timestamp::fast_forward_seconds(1000);
    }

    // Helper to create a test VeriFi market
    fun create_test_market(admin: &signer, creator: &signer): object::Object<Market> {
        // Register oracle
        let oracle_id = string::utf8(b"test_oracle");
        oracle_registry::register_oracle(admin, oracle_id, string::utf8(b"Test Oracle"));

        // Create market with 1 hour until resolution
        let resolution_time = timestamp::now_seconds() + 3600;

        verifi_protocol::create_market(
            creator,
            string::utf8(b"Test Market"),
            resolution_time,
            signer::address_of(admin),
            oracle_id,
            @0x1234,
            string::utf8(b"balance"),
            100,
            OPERATOR_GREATER_THAN,
        );

        // Get created market
        let all_markets = verifi_protocol::get_all_markets();
        *all_markets.borrow(0)
    }

    // ===== CORE OPERATIONS TESTS =====

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_create_prediction_pool(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Verify pool creation event
        let events = event::emitted_events<PoolCreated>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_pool_created_pool_addr(event) == pool_addr);
        assert!(router::event_pool_created_hook_type(event) == 4); // HOOK_PREDICTION = 4
        let event_assets = router::event_pool_created_assets(event);
        assert!(event_assets.length() == 2);

        // Verify hook factory state
        assert!(hook_type(pool_addr) == 4);
        assert!(assets(pool_addr) == event_assets);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_add_initial_liquidity(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Buy YES/NO shares first (using test coins as proxy)
        // In real scenario, would call verifi_protocol::buy_shares
        // For testing, we assume shares are available

        // Add liquidity to create new position
        let position_idx = add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            1000 * OCTAS_PER_APT, // amount_yes
            1000 * OCTAS_PER_APT, // amount_no
            500 * OCTAS_PER_APT   // min_lp_tokens
        );

        // Verify liquidity added event
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 1000 * OCTAS_PER_APT);
        assert!(event_amounts[1] == 1000 * OCTAS_PER_APT);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_add_liquidity_existing_position(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Create initial position
        let position_idx = add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            1000 * OCTAS_PER_APT,
            1000 * OCTAS_PER_APT,
            500 * OCTAS_PER_APT
        );

        // Add more liquidity to existing position
        let position_addr = router::position_addr(pool_addr, position_idx);
        add_liquidity_prediction_pool(
            sender,
            pool_addr,
            some(position_addr),
            500 * OCTAS_PER_APT,  // additional amount_yes
            500 * OCTAS_PER_APT,  // additional amount_no
            250 * OCTAS_PER_APT   // min_lp_tokens
        );

        // Verify two liquidity added events
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 2);

        // Check second event (most recent)
        let event = &events[1];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == position_idx); // Same position
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_amounts[0] == 500 * OCTAS_PER_APT);
        assert!(event_amounts[1] == 500 * OCTAS_PER_APT);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_swap_yes_to_no(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Add liquidity first
        add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            10000 * OCTAS_PER_APT,
            10000 * OCTAS_PER_APT,
            5000 * OCTAS_PER_APT
        );

        // Perform swap (YES to NO)
        let (amount_in, amount_out) = swap_prediction_pool(
            sender,
            pool_addr,
            1000 * OCTAS_PER_APT, // amount_in
            true,                  // yes_to_no
            950 * OCTAS_PER_APT    // min_amount_out
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);

        // Verify CPMM formula (amount_out should be less than amount_in due to fees)
        assert!(amount_out < amount_in);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_swap_no_to_yes(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Add liquidity first
        add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            10000 * OCTAS_PER_APT,
            10000 * OCTAS_PER_APT,
            5000 * OCTAS_PER_APT
        );

        // Perform swap (NO to YES)
        let (amount_in, amount_out) = swap_prediction_pool(
            sender,
            pool_addr,
            1000 * OCTAS_PER_APT, // amount_in
            false,                 // no_to_yes
            950 * OCTAS_PER_APT    // min_amount_out
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);

        // Verify reverse direction works
        assert!(amount_out < amount_in);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_remove_partial_liquidity(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Add liquidity first
        let position_idx = add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            1000 * OCTAS_PER_APT,
            1000 * OCTAS_PER_APT,
            500 * OCTAS_PER_APT
        );

        let position_addr = router::position_addr(pool_addr, position_idx);

        // Remove 50% liquidity
        let _ = remove_liquidity_prediction_pool(
            sender,
            pool_addr,
            position_addr,
            500 * OCTAS_PER_APT, // remove half
            250 * OCTAS_PER_APT, // min_yes
            250 * OCTAS_PER_APT  // min_no
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);

        // Verify proportional withdrawal (approximately 50%)
        assert!(event_amounts[0] >= 400 * OCTAS_PER_APT && event_amounts[0] <= 600 * OCTAS_PER_APT);
        assert!(event_amounts[1] >= 400 * OCTAS_PER_APT && event_amounts[1] <= 600 * OCTAS_PER_APT);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_remove_full_liquidity(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool(
            sender,
            vector[yes_addr, no_addr],
            3000
        );

        // Add liquidity first
        let position_idx = add_liquidity_prediction_pool(
            sender,
            pool_addr,
            none(),
            1000 * OCTAS_PER_APT,
            1000 * OCTAS_PER_APT,
            500 * OCTAS_PER_APT
        );

        let position_addr = router::position_addr(pool_addr, position_idx);

        // Remove all liquidity
        let _ = remove_liquidity_prediction_pool(
            sender,
            pool_addr,
            position_addr,
            1000 * OCTAS_PER_APT, // remove all
            500 * OCTAS_PER_APT,  // min_yes
            500 * OCTAS_PER_APT   // min_no
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);

        // Verify all amounts removed (approximately 100%)
        assert!(event_amounts[0] >= 900 * OCTAS_PER_APT);
        assert!(event_amounts[1] >= 900 * OCTAS_PER_APT);
    }

    #[test(sender = @0x99, admin = @VeriFiPublisher, creator = @0xCAFE)]
    fun test_create_pool_add_liquidity(sender: &signer, admin: &signer, creator: &signer) {
        init();
        setup_verifi_protocol(admin);
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);

        let market = create_test_market(admin, creator);
        let (yes_token, no_token) = verifi_protocol::get_market_tokens(market);
        let yes_addr = object::object_address(&yes_token);
        let no_addr = object::object_address(&no_token);

        let pool_addr = create_prediction_pool_add_liquidity(
            sender,
            vector[yes_addr, no_addr],
            3000,
            1000 * OCTAS_PER_APT, // amount_yes
            1000 * OCTAS_PER_APT, // amount_no
            500 * OCTAS_PER_APT   // min_lp_tokens
        );

        // Verify both pool creation and liquidity added events
        let pool_events = event::emitted_events<PoolCreated>();
        let liquidity_events = event::emitted_events<LiquidityAdded>();

        assert!(pool_events.length() == 1);
        assert!(liquidity_events.length() == 1);

        let pool_event = &pool_events[0];
        assert!(router::event_pool_created_pool_addr(pool_event) == pool_addr);
        assert!(router::event_pool_created_hook_type(pool_event) == 4); // HOOK_PREDICTION

        let liquidity_event = &liquidity_events[0];
        assert!(router::event_liquidity_added_pool_addr(liquidity_event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(liquidity_event) == 0); // First position
        let liquidity_amounts = router::event_liquidity_added_amounts(liquidity_event);
        assert!(liquidity_amounts[0] == 1000 * OCTAS_PER_APT);
        assert!(liquidity_amounts[1] == 1000 * OCTAS_PER_APT);
    }
}
