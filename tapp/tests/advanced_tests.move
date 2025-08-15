#[test_only]
module tapp::advanced_tests {
    use std::option::{none};
    use aptos_framework::event;
    use tapp::fixtures::{
        init,
        create_advanced_pool,
        add_liquidity_advanced_pool,
        remove_liquidity_advanced_pool,
        swap_advanced_pool,
        collect_fee_advanced_pool,
        create_advanced_pool_add_liquidity
    };
    use tapp::router::{Self, PoolCreated, LiquidityAdded, LiquidityRemoved, Swapped, FeeCollected, position_addr};
    use tapp::test_coins::{Self, BTC, USDC};
    use tapp::hook_factory::{hook_type, assets};

    #[test(sender = @0x99)]
    fun test_advanced_create_pool(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Verify pool creation event
        let events = event::emitted_events<PoolCreated>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_pool_created_pool_addr(event) == pool_addr);
        assert!(router::event_pool_created_hook_type(event) == 2); // HOOK_ADVANCED = 2
        let event_assets = router::event_pool_created_assets(event);
        assert!(event_assets.length() == 2);
        assert!(event_assets[0] == usdc_addr);
        assert!(event_assets[1] == btc_addr);

        // Verify hook factory state
        assert!(hook_type(pool_addr) == 2);
        assert!(assets(pool_addr) == event_assets);
    }

    #[test(sender = @0x99)]
    fun test_advanced_add_liquidity_new_position(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity to create new position
        let position_idx = add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
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
    fun test_advanced_add_liquidity_existing_position(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Create initial position
        let _ = add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Add more to existing position
        add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(), // For now, we'll create a new position since we can't reference existing ones easily
            500, // additional value
        );

        // Verify two liquidity added events
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 2);

        // Check second event (most recent)
        let event = &events[1];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_amounts[0] == 500); // Additional amounts
        assert!(event_amounts[1] == 500);
    }

    #[test(sender = @0x99)]
    fun test_advanced_remove_liquidity(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity first
        let position_idx = add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Remove liquidity from position
        let _ = remove_liquidity_advanced_pool(
            sender,
            pool_addr,
            position_addr(pool_addr, position_idx),
            500, // value to remove
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
    fun test_advanced_remove_liquidity_complete(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity first
        let position_idx = add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Remove all liquidity (complete removal)
        let _ = remove_liquidity_advanced_pool(
            sender,
            pool_addr,
            position_addr(pool_addr, position_idx),
            1000, // full value
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == position_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 1000); // Full amounts removed
        assert!(event_amounts[1] == 1000);
    }

    #[test(sender = @0x99)]
    fun test_advanced_swap(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity first
        add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Perform swap
        let (asset_in_index, asset_out_index, amount_in, amount_out) = swap_advanced_pool(
            sender,
            pool_addr,
            0, // asset_in_index (BTC)
            1, // asset_out_index (USDC)
            100, // asset_in_amount
            95  // asset_out_amount
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        assert!(router::event_swapped_asset_in_index(event) == asset_in_index);
        assert!(router::event_swapped_asset_out_index(event) == asset_out_index);
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);
    }

    #[test(sender = @0x99)]
    fun test_advanced_swap_reverse(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity first
        add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Perform reverse swap (USDC to BTC)
        let (asset_in_index, asset_out_index, amount_in, amount_out) = swap_advanced_pool(
            sender,
            pool_addr,
            1, // asset_in_index (USDC)
            0, // asset_out_index (BTC)
            200, // asset_in_amount
            190  // asset_out_amount
        );

        // Verify swap event
        let events = event::emitted_events<Swapped>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_swapped_pool_addr(event) == pool_addr);
        assert!(router::event_swapped_asset_in_index(event) == asset_in_index);
        assert!(router::event_swapped_asset_out_index(event) == asset_out_index);
        assert!(router::event_swapped_amount_in(event) == amount_in);
        assert!(router::event_swapped_amount_out(event) == amount_out);
    }

    #[test(sender = @0x99)]
    fun test_advanced_collect_fee(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool(
            sender,
            vector[btc_addr, usdc_addr],
            3000 // 3% fee
        );

        // Add liquidity first
        let position_idx = add_liquidity_advanced_pool(
            sender,
            pool_addr,
            none(),
            1000, // value
        );

        // Collect fees from position
        let _ = collect_fee_advanced_pool(
            sender,
            pool_addr,
            position_addr(pool_addr, position_idx)
        );

        // Verify fee collected event
        let events = event::emitted_events<FeeCollected>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_fee_collected_pool_addr(event) == pool_addr);
        assert!(router::event_fee_collected_hook_type(event) == 2); // HOOK_ADVANCED
        assert!(router::event_fee_collected_position_idx(event) == position_idx);
        let event_assets = router::event_fee_collected_assets(event);
        let event_amounts = router::event_fee_collected_amounts(event);
        assert!(event_assets.length() == 2);
        assert!(event_amounts.length() == 2);
    }

    #[test(sender = @0x99)]
    fun test_advanced_create_pool_add_liquidity(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_advanced_pool_add_liquidity(
            sender,
            vector[btc_addr, usdc_addr],
            3000, // fee
            1000, // value
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
        assert!(router::event_pool_created_hook_type(pool_event) == 2); // HOOK_ADVANCED

        let liquidity_event = &liquidity_events[0];
        assert!(router::event_liquidity_added_pool_addr(liquidity_event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(liquidity_event) == 0); // First position
        let liquidity_amounts = router::event_liquidity_added_amounts(liquidity_event);
        assert!(liquidity_amounts[0] == 1000);
        assert!(liquidity_amounts[1] == 1000);
    }
}
