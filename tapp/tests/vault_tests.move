#[test_only]
module tapp::vault_tests {
    use std::option::{none, some};
    use aptos_std::debug::print;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::timestamp::{update_global_time_for_test_secs, fast_forward_seconds};
    use tapp::fixtures::{
        init,
        create_vault_pool,
        add_liquidity_vault_pool,
        remove_liquidity_vault_pool,
        collect_fee_vault_pool,
        create_vault_pool_add_liquidity
    };
    use tapp::router::{Self, PoolCreated, LiquidityAdded, LiquidityRemoved, FeeCollected, position_addr};
    use tapp::test_coins::{Self, BTC, USDC};
    use tapp::hook_factory::{hook_type, assets};

    // Vault type constants
    const T_TIMELOCKED_VAULT: u8 = 1;
    const T_INSURANCE_VAULT: u8 = 2;

    #[test(sender = @0x99)]
    fun test_vault_create_timelocked_pool(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000,
        );

        // Verify pool creation event
        let events = event::emitted_events<PoolCreated>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_pool_created_pool_addr(event) == pool_addr);
        assert!(router::event_pool_created_hook_type(event) == 3); // HOOK_VAULT = 3
        let event_assets = router::event_pool_created_assets(event);
        assert!(event_assets.length() == 2);
        assert!(event_assets[0] == usdc_addr);
        assert!(event_assets[1] == btc_addr);

        // Verify hook factory state
        assert!(hook_type(pool_addr) == 3);
        assert!(assets(pool_addr) == event_assets);
    }

    #[test(sender = @0x99)]
    fun test_vault_create_insurance_pool(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_INSURANCE_VAULT,
            vector[btc_addr, usdc_addr],
            1000, // 1% fee
        );

        // Verify pool creation event
        let events = event::emitted_events<PoolCreated>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_pool_created_pool_addr(event) == pool_addr);
        assert!(router::event_pool_created_hook_type(event) == 3); // HOOK_VAULT = 3
        let event_assets = router::event_pool_created_assets(event);
        assert!(event_assets.length() == 2);
        assert!(event_assets[0] == usdc_addr);
        assert!(event_assets[1] == btc_addr);

        // Verify hook factory state
        assert!(hook_type(pool_addr) == 3);
        assert!(assets(pool_addr) == event_assets);
    }

    #[test(sender = @0x99)]
    fun test_vault_deposit_timelocked_new_slot(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000,
        );

        // Deposit to create new slot
        let slot_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            some(1000), // lock duration
            vector[500, 500], // amounts
        );

        // Verify liquidity added event
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == slot_idx);
        let event_assets = router::event_liquidity_added_assets(event);
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_assets.length() == 2);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 500);
        assert!(event_amounts[1] == 500);
    }

    #[test(sender = @0x99)]
    fun test_vault_deposit_insurance_new_slot(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_INSURANCE_VAULT,
            vector[btc_addr, usdc_addr],
            1000, // 1% fee
        );

        // Deposit to create new slot
        let slot_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            none(), // No lock duration for insurance vault
            vector[1000, 1000], // amounts
        );

        // Verify liquidity added event
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == slot_idx);
        let event_assets = router::event_liquidity_added_assets(event);
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_assets.length() == 2);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] == 1000);
        assert!(event_amounts[1] == 1000);
    }

    #[test(sender = @0x99)]
    fun test_vault_deposit_existing_slot(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000,
        );

        // Create initial slot
        let slot_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            some(1000), // lock duration
            vector[500, 500], // amounts
        );

        // Add more to existing slot
        let slot_addr = router::position_addr(pool_addr, slot_idx);
        add_liquidity_vault_pool(
            sender,
            pool_addr,
            some(slot_addr),
            none(), // No new lock duration
            vector[300, 300], // additional amounts
        );

        // Verify two liquidity added events
        let events = event::emitted_events<LiquidityAdded>();
        assert!(events.length() == 2);

        // Check second event (most recent)
        let event = &events[1];
        assert!(router::event_liquidity_added_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(event) == slot_idx); // Same slot
        let event_amounts = router::event_liquidity_added_amounts(event);
        assert!(event_amounts[0] == 300); // Additional amounts
        assert!(event_amounts[1] == 300);
    }

    #[test(sender = @0x99, aptos= @0x1)]
    fun test_vault_withdraw_timelocked(sender: &signer, aptos: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        timestamp::set_time_has_started_for_testing(aptos);
        update_global_time_for_test_secs(1000);
        let pool_addr = create_vault_pool(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000,
        );

        // Add liquidity first
        let slot_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            some(3600), // lock duration
            vector[1000, 1000], // amounts
        );

        let slot_addr = router::position_addr(pool_addr, slot_idx);

        fast_forward_seconds(4000);
        // Withdraw from slot (should work after lock period)
        let _ = remove_liquidity_vault_pool(
            sender,
            pool_addr,
            slot_addr,
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == slot_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] > 0); // Withdrawn amounts (after fees)
        assert!(event_amounts[1] > 0);
    }

    #[test(sender = @0x99)]
    fun test_vault_withdraw_insurance(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_INSURANCE_VAULT,
            vector[btc_addr, usdc_addr],
            1000, // 1% fee
        );

        // Deposit to create new slot
        let slot_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            none(), // No lock duration for insurance vault
            vector[1000, 1000], // amounts
        );

        let slot_addr = router::position_addr(pool_addr, slot_idx);

        // Withdraw from slot (should work immediately)
        let _ = remove_liquidity_vault_pool(
            sender,
            pool_addr,
            slot_addr,
        );

        // Verify liquidity removed event
        let events = event::emitted_events<LiquidityRemoved>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_liquidity_removed_pool_addr(event) == pool_addr);
        assert!(router::event_liquidity_removed_position_idx(event) == slot_idx);
        let event_amounts = router::event_liquidity_removed_amounts(event);
        assert!(event_amounts.length() == 2);
        assert!(event_amounts[0] > 0); // Withdrawn amounts (after fees)
        assert!(event_amounts[1] > 0);
    }

    #[test(sender = @0x99)]
    fun test_vault_collect_fee(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000, // 3% fee
        );

        // Add liquidity first
        let position_idx = add_liquidity_vault_pool(
            sender,
            pool_addr,
            none(),
            some(3600), // lock duration
            vector[1000, 1000], // amounts
        );

        // Collect fees
        let _ = collect_fee_vault_pool(
            sender,
            pool_addr,
            position_addr(pool_addr, position_idx),
        );

        // Verify fee collected event
        let events = event::emitted_events<FeeCollected>();
        assert!(events.length() == 1);
        let event = &events[0];
        assert!(router::event_fee_collected_pool_addr(event) == pool_addr);
        assert!(router::event_fee_collected_hook_type(event) == 3); // HOOK_VAULT
        assert!(router::event_fee_collected_position_idx(event) == 0); // No specific position for vault
        let event_assets = router::event_fee_collected_assets(event);
        let event_amounts = router::event_fee_collected_amounts(event);
        assert!(event_assets.length() == 2);
        assert!(event_amounts.length() == 2);
        // Fees should be collected from the vault
    }

    #[test(sender = @0x99)]
    fun test_vault_create_pool_add_liquidity(sender: &signer) {
        init();
        test_coins::quick_mint(sender, 1_000_000_000_000_000_000);
        let btc_addr = test_coins::asset_address<BTC>();
        let usdc_addr = test_coins::asset_address<USDC>();

        let pool_addr = create_vault_pool_add_liquidity(
            sender,
            T_TIMELOCKED_VAULT,
            vector[btc_addr, usdc_addr],
            3000,
            86400, // 24 hours lock duration
            vector[1000, 1000], // amounts
        );

        // Verify both pool creation and liquidity added events
        let pool_events = event::emitted_events<PoolCreated>();
        let liquidity_events = event::emitted_events<LiquidityAdded>();

        assert!(pool_events.length() == 1);
        assert!(liquidity_events.length() == 1);

        let pool_event = &pool_events[0];
        assert!(router::event_pool_created_pool_addr(pool_event) == pool_addr);
        assert!(router::event_pool_created_hook_type(pool_event) == 3); // HOOK_VAULT

        let liquidity_event = &liquidity_events[0];
        assert!(router::event_liquidity_added_pool_addr(liquidity_event) == pool_addr);
        assert!(router::event_liquidity_added_position_idx(liquidity_event) == 0); // First slot
        let liquidity_amounts = router::event_liquidity_added_amounts(liquidity_event);
        print(&liquidity_amounts);
        assert!(liquidity_amounts[0] == 1000);
        assert!(liquidity_amounts[1] == 1000);
    }
}
