#[test_only]
module tapp::fixtures {
    use std::bcs::to_bytes;
    use std::option::{Option};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use tapp::router::{create_pool, PoolCreated, LiquidityAdded, LiquidityRemoved, FeeCollected};
    use tapp::test_coins;
    use tapp::router;

    #[test_only]
    public fun init() {
        let aptos_signer = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_signer);
        coin::create_coin_conversion_map(&aptos_signer);

        router::init_module_for_test();
        test_coins::init_module_for_test();
    }

    #[test_only]
    public fun create_pool_args(
        pool_type: u8, assets: vector<address>, fee: u64
    ): vector<u8> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_type));
        args.append(to_bytes(&assets));
        args.append(to_bytes(&fee));
        args
    }

    #[test_only]
    public fun add_liquidity_args(
        pool_addr: address, position_addr: Option<address>
    ): vector<u8> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        args
    }

    // Basic Hook Helper Functions

    #[test_only]
    public fun create_basic_pool(
        signer: &signer, assets: vector<address>, fee: u64
    ): address {
        let pool_args = create_pool_args(1, assets, fee); // HOOK_BASIC = 1
        create_pool(signer, pool_args);

        let events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&events[0])
    }

    #[test_only]
    public fun create_basic_pool_add_liquidity(
        signer: &signer,
        assets: vector<address>,
        fee: u64,
        amount_a: u64,
        amount_b: u64,
        min_a: u64,
        min_b: u64
    ): address {
        let args = vector::empty<u8>();
        args.append(to_bytes(&1u8)); // HOOK_BASIC = 1
        args.append(to_bytes(&assets));
        args.append(to_bytes(&fee));
        args.append(to_bytes(&amount_a));
        args.append(to_bytes(&amount_b));
        args.append(to_bytes(&min_a));
        args.append(to_bytes(&min_b));
        router::create_pool_add_liquidity(signer, args);
        let creation_events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&creation_events[creation_events.length() - 1])
    }

    #[test_only]
    public fun add_liquidity_basic_pool(
        signer: &signer,
        pool_addr: address,
        position_idx: Option<address>,
        value: u64,
        min_a: u64,
        min_b: u64
    ): u64 {
        let args = add_liquidity_args(pool_addr, position_idx);
        args.append(to_bytes(&value));
        args.append(to_bytes(&min_a));
        args.append(to_bytes(&min_b));
        router::add_liquidity(signer, args);
        let events = event::emitted_events<LiquidityAdded>();
        router::event_liquidity_added_position_idx(&events[events.length() - 1])
    }

    #[test_only]
    public fun remove_liquidity_basic_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: address,
        value: u64,
        min_a: u64,
        min_b: u64
    ): vector<u64> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        args.append(to_bytes(&value));
        args.append(to_bytes(&min_a));
        args.append(to_bytes(&min_b));
        router::remove_liquidity(signer, args);

        let events = event::emitted_events<LiquidityRemoved>();
        router::event_liquidity_removed_amounts(&events[events.length() - 1])
    }

    #[test_only]
    public fun swap_basic_pool(
        signer: &signer,
        pool_addr: address,
        a2b: bool,
        amount_in: u64,
        amount_out: u64
    ): (u64, u64) {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&a2b));
        args.append(to_bytes(&amount_in));
        args.append(to_bytes(&amount_out));
        router::swap(signer, args);

        let events = event::emitted_events<router::Swapped>();
        let event = &events[events.length() - 1];
        (router::event_swapped_amount_in(event), router::event_swapped_amount_out(event))
    }

    // Vault Hook Helper Functions

    #[test_only]
    public fun create_vault_pool(
        signer: &signer,
        vault_type: u8,
        assets: vector<address>,
        fee: u64,
        lock_duration: u64
    ): address {
        let args = vector::empty<u8>();
        args.append(to_bytes(&3u8)); // HOOK_VAULT = 3
        args.append(to_bytes(&assets));
        args.append(to_bytes(&fee));
        args.append(to_bytes(&vault_type));
        create_pool(signer, args);

        let events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&events[0])
    }

    #[test_only]
    public fun create_vault_pool_add_liquidity(
        signer: &signer,
        vault_type: u8,
        assets: vector<address>,
        fee: u64,
        lock_duration: u64,
        amounts: vector<u64>,
    ): address {
        let args = vector::empty<u8>();
        args.append(to_bytes(&3u8)); // HOOK_VAULT = 3
        args.append(to_bytes(&assets));
        args.append(to_bytes(&fee));
        args.append(to_bytes(&vault_type));
        if (vault_type == 1) { // TimeLockedVault
            args.append(to_bytes(&lock_duration));
        };
        args.append(to_bytes(&amounts));
        router::create_pool_add_liquidity(signer, args);
        let creation_events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&creation_events[creation_events.length() - 1])
    }

    #[test_only]
    public fun add_liquidity_vault_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: Option<address>,
        lock_duration: Option<u64>,
        amounts: vector<u64>,
    ): u64 {
        let args = add_liquidity_args(pool_addr, position_addr);
        if (lock_duration.is_some()) {
            args.append(to_bytes(&lock_duration.destroy_some()));
        };
        args.append(to_bytes(&amounts));
        router::add_liquidity(signer, args);
        let events = event::emitted_events<LiquidityAdded>();
        router::event_liquidity_added_position_idx(&events[events.length() - 1])
    }

    #[test_only]
    public fun remove_liquidity_vault_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: address,
    ): vector<u64> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        router::remove_liquidity(signer, args);

        let events = event::emitted_events<LiquidityRemoved>();
        router::event_liquidity_removed_amounts(&events[events.length() - 1])
    }

    #[test_only]
    public fun collect_fee_vault_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: address
    ): vector<u64> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        router::collect_fee(signer, args);

        let events = event::emitted_events<FeeCollected>();
        router::event_fee_collected_amounts(&events[events.length() - 1])
    }

    // Advanced Hook Helper Functions

    #[test_only]
    public fun create_advanced_pool(
        signer: &signer, assets: vector<address>, fee: u64
    ): address {
        let pool_args = create_pool_args(2, assets, fee); // HOOK_ADVANCED = 2
        create_pool(signer, pool_args);

        let events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&events[0])
    }

    #[test_only]
    public fun create_advanced_pool_add_liquidity(
        signer: &signer,
        assets: vector<address>,
        fee: u64,
        value: u64,
        min_a: u64,
        min_b: u64
    ): address {
        let args = vector::empty<u8>();
        args.append(to_bytes(&2u8)); // HOOK_ADVANCED = 2
        args.append(to_bytes(&assets));
        args.append(to_bytes(&fee));
        args.append(to_bytes(&value));
        args.append(to_bytes(&min_a));
        args.append(to_bytes(&min_b));
        router::create_pool_add_liquidity(signer, args);
        let creation_events = event::emitted_events<PoolCreated>();
        router::event_pool_created_pool_addr(&creation_events[creation_events.length() - 1])
    }

    #[test_only]
    public fun add_liquidity_advanced_pool(
        signer: &signer,
        pool_addr: address,
        position_idx: Option<address>,
        value: u64,
    ): u64 {
        let args = add_liquidity_args(pool_addr, position_idx);
        args.append(to_bytes(&value));
        router::add_liquidity(signer, args);
        let events = event::emitted_events<LiquidityAdded>();
        router::event_liquidity_added_position_idx(&events[events.length() - 1])
    }

    #[test_only]
    public fun remove_liquidity_advanced_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: address,
        value: u64,
    ): vector<u64> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        args.append(to_bytes(&value));
        router::remove_liquidity(signer, args);

        let events = event::emitted_events<LiquidityRemoved>();
        router::event_liquidity_removed_amounts(&events[events.length() - 1])
    }

    #[test_only]
    public fun swap_advanced_pool(
        signer: &signer,
        pool_addr: address,
        asset_in_index: u64,
        asset_out_index: u64,
        asset_in_amount: u64,
        asset_out_amount: u64
    ): (u64, u64, u64, u64) {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&asset_in_index));
        args.append(to_bytes(&asset_out_index));
        args.append(to_bytes(&asset_in_amount));
        args.append(to_bytes(&asset_out_amount));
        router::swap(signer, args);

        let events = event::emitted_events<router::Swapped>();
        let event = &events[events.length() - 1];
        (
            router::event_swapped_asset_in_index(event),
            router::event_swapped_asset_out_index(event),
            router::event_swapped_amount_in(event),
            router::event_swapped_amount_out(event)
        )
    }

    #[test_only]
    public fun collect_fee_advanced_pool(
        signer: &signer,
        pool_addr: address,
        position_addr: address
    ): vector<u64> {
        let args = vector::empty<u8>();
        args.append(to_bytes(&pool_addr));
        args.append(to_bytes(&position_addr));
        router::collect_fee(signer, args);

        let events = event::emitted_events<FeeCollected>();
        router::event_fee_collected_amounts(&events[events.length() - 1])
    }
}

