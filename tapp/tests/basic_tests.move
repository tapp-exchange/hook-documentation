#[test_only]
module tapp::basic_tests {
    use std::option::{none, some};
    use aptos_framework::event;
    use tapp::fixtures::{
        init,
        create_basic_pool,
        add_liquidity_basic_pool,
        remove_liquidity_basic_pool,
        swap_basic_pool,
        create_basic_pool_add_liquidity
    };
    use tapp::router::{Self, PoolCreated, LiquidityAdded, LiquidityRemoved, Swapped};
    use tapp::test_coins::{Self, BTC, USDC};
    use tapp::hook_factory::{hook_type, assets};

    #[test(sender = @0x99)]
    fun test_basic_create_pool(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Verify pool creation event
        let events = event::emitted_events<PoolCreated>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_pool_created_pool_addr(event) == pool_addr);
        assert!(router::event_pool_created_hook_type(event) == 1); // HOOK_BASIC = 1
        let event_assets = router::event_pool_created_assets(event);
        assert!(event_assets.length() == 2);
        assert!(event_assets[0] == usdc_addr);
        assert!(event_assets[1] == btc_addr);

        // Verify hook factory state
        assert!(hook_type(pool_addr) == 1);
        assert!(assets(pool_addr) == event_assets);
    }

    #[test(sender = @0x99)]
    fun test_basic_add_liquidity_new_position(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Add liquidity to create new position
        let position_idx = add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
            500, // min_a
            500   // min_b
        );

        // Verify liquidity added event
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == position_idx);
        let event_assets = router::event_liquidity_added_assets(event);
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_assets.length() == 2);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 1000); // Each asset gets the same value
        assert!(event_amounts[1] == 1000);
    }

    #[test(sender = @0x99)]
    fun test_basic_add_liquidity_existing_position(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Create initial position
        let position_idx = add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
            500, // min_a
            500   // min_b
        );

        // Add more liquidity to existing position
        let position_addr = router::position_addr(pool_addr, position_idx);
        add_liquidity_basic_pool(
            sender,
            pool_addr,
            some(position_addr),
            500, // additional value
            250, // min_a
            250   // min_b
        );

        // Verify two liquidity added events
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 2);

        // Check second event (most recent)
        let event = &events[1];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == position_idx); // Same position
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_amounts[0] == 500); // Additional amounts
        assert!(event_amounts[1] == 500);
    }

    #[test(sender = @0x99)]
    fun test_basic_remove_liquidity(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Add liquidity first
        let position_idx = add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
            500, // min_a
            500   // min_b
        );

        let position_addr = router::position_addr(pool_addr, position_idx);

        // Remove liquidity
        let removed_amounts = remove_liquidity_basic_pool(
            sender,
            pool_addr,
            position_addr,
            500, // remove half
            250, // min_a
            250   // min_b
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 500); // Removed amounts
        assert!(event_amounts[1] == 500);
    }

    #[test(sender = @0x99)]
    fun test_basic_remove_liquidity_complete(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Add liquidity first
        let position_idx = add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
            500, // min_a
            500   // min_b
        );

        let position_addr = router::position_addr(pool_addr, position_idx);

        // Remove all liquidity (should remove position)
        let removed_amounts = remove_liquidity_basic_pool(
            sender,
            pool_addr,
            position_addr,
            1000, // remove all
            500, // min_a
            500   // min_b
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 1000); // All amounts removed
        assert!(event_amounts[1] == 1000);
    }

    #[test(sender = @0x99)]
    fun test_basic_swap(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000
        );

        // Add liquidity first
        add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            10000, // value
            5000, // min_a
            5000   // min_b
        );

        // Perform swap (A to B)
        let (amount_in, amount_out) = swap_basic_pool(
            sender,
            pool_addr,
            true, // a2b
            1000, // amount_in
            950     // amount_out (min)
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        let event_assets = router::event_swapped_assets(event);
        assert!(event_assets.length() == 2);
        assert!(router::event_swapped_asset_in_index(event) == 0); // First asset (BTC)
        assert!(router::event_swapped_asset_out_index(event) == 1); // Second asset (USDC)
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);
    }

    #[test(sender = @0x99)]
    fun test_basic_swap_b_to_a(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool(
            sender,
            vector[usdc_addr, btc_addr],
            3000
        );

        // Add liquidity first
        add_liquidity_basic_pool(
            sender,
            pool_addr,
            none(),
            10000, // value
            5000, // min_a
            5000   // min_b
        );

        // Perform swap (B to A)
        let (amount_in, amount_out) = swap_basic_pool(
            sender,
            pool_addr,
            false, // b2a
            1000, // amount_in
            950     // amount_out (min)
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        let event_assets = router::event_swapped_assets(event);
        assert!(event_assets.length() == 2);
        assert!(router::event_swapped_asset_in_index(event) == 1); // Second asset (USDC)
        assert!(router::event_swapped_asset_out_index(event) == 0); // First asset (BTC)
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);
    }

    #[test(sender = @0x99)]
    fun test_basic_create_pool_add_liquidity(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_basic_pool_add_liquidity(
            sender,
            vector[btc_addr, usdc_addr],
            3000,
            1000, // amount_a
            1000, // amount_b
            500, // min_a
            500   // min_b
        );

        // Verify both pool creation and liquidity added events
        let pool_events = event::emitted_events<PoolCreated>();
        let liquidity_events = event::emitted_events<LiquidityAdded>();

        assert!(pool_events.length() == 1);
        assert!(liquidity_events.length() == 1);

        let pool_event = &pool_events[0];
        assert!(router::event_pool_created_pool_addr(pool_event) == pool_addr);
        assert!(router::event_pool_created_hook_type(pool_event) == 1); // HOOK_BASIC

        let liquidity_event = &liquidity_events[0];
        assert!(router::event_liquidity_added_pool_addr(liquidity_event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(liquidity_event) == 0); // First position
        let liquidity_amounts = router::event_liquidity_added_amounts(liquidity_event);
        assert!(liquidity_amounts[0] == 1000);
        assert!(liquidity_amounts[1] == 1000);
    }
}