module tapp::router {
    use std::option::{none, some};
    use std::signer::address_of;
    use aptos_std::bcs_stream;
    use aptos_std::bcs_stream::{deserialize_address, deserialize_u8, deserialize_option};
    use aptos_framework::account::{create_resource_account, create_signer_with_capability};
    use aptos_framework::event::emit;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::{
        is_object,
        generate_signer,
        generate_extend_ref,
        address_to_object,
        generate_signer_for_extending
    };
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use tapp::position::{authorized_borrow, mint_position, burn_position};
    use tapp::hook_factory::{Tx, hook_type};
    use tapp::hook_factory;
    use tapp::position;

    #[test_only]
    use aptos_framework::account::create_signer_for_test;

    const EUNAUTHORIZED_ACCESS: u64 = 0xb0;
    const EPAUSED_POOL: u64 = 0xb1;
    const EPAUSED_HOOK: u64 = 0xb2;
    const ECALC_PLATFORM_FEE_UNSUPPORTED_HOOK: u64 = 0xb4;
    const ESWAP_AMOUNT_TOO_SMALL_FOR_PLATFORM_FEE: u64 = 0xb5;
    const EINSUFFICIENT_AMOUNT_TO_VAULT: u64 = 0xb6;
    const EPOOL_EXISTED: u64 = 0xb7;
    const EPOOL_NOTEXISTED: u64 = 0xb8;

    struct Manager has key {
        vault: 0x1::account::SignerCapability,
        pools: vector<address>
    }

    struct PoolCap has key {
        extend_ref: 0x1::object::ExtendRef
    }

    #[event]
    struct PoolCreated has drop, store {
        pool_addr: address,
        hook_type: u8,
        assets: vector<address>,
        creator: address,
        ts: u64
    }

    #[event]
    struct LiquidityAdded has drop, store {
        pool_addr: address,
        position_idx: u64,
        assets: vector<address>,
        amounts: vector<u64>,
        creator: address,
        ts: u64
    }

    #[event]
    struct LiquidityRemoved has drop, store {
        pool_addr: address,
        position_idx: u64,
        assets: vector<address>,
        amounts: vector<u64>,
        creator: address,
        ts: u64
    }

    #[event]
    struct Swapped has drop, store {
        pool_addr: address,
        assets: vector<address>,
        asset_in_index: u64,
        asset_out_index: u64,
        amount_in: u64,
        amount_out: u64,
        creator: address,
        ts: u64
    }

    #[event]
    struct FeeCollected has drop, store {
        pool_addr: address,
        hook_type: u8,
        position_idx: u64,
        assets: vector<address>,
        amounts: vector<u64>,
        creator: address,
        ts: u64
    }

    public entry fun create_pool(sender: &signer, args: vector<u8>) acquires Manager {
        let (manager, vault) = manager_vault_mut();

        let stream = &mut bcs_stream::new(args);
        let hook_type = deserialize_u8(stream);

        let cref = &hook_factory::create_pool(
            &vault, address_of(sender), hook_type, stream
        );
        let pool_signer = &generate_signer(cref);
        move_to(pool_signer, PoolCap { extend_ref: generate_extend_ref(cref) });

        let pool_addr = address_of(pool_signer);
        assert!(!manager.pools.contains(&pool_addr), EPOOL_EXISTED);
        manager.pools.push_back(pool_addr);

        emit(
            PoolCreated {
                pool_addr,
                hook_type: hook_type(pool_addr),
                assets: hook_factory::assets(pool_addr),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );
    }

    public entry fun add_liquidity(sender: &signer, args: vector<u8>) acquires Manager, PoolCap {
        internal_add_liquidity(sender, args);
    }

    public(package) fun internal_add_liquidity(
        sender: &signer, args: vector<u8>
    ): (u64, address) acquires Manager, PoolCap {
        let (manager, vault) = manager_vault_mut();

        let stream = &mut bcs_stream::new(args);
        let pool_addr = deserialize_address(stream);
        assert!(
            manager.pools.contains(&pool_addr) && is_object(pool_addr),
            EPOOL_NOTEXISTED
        );

        let position_addr = deserialize_option<address>(
            stream, |s| deserialize_address(s)
        );
        let position_idx =
            if (position_addr.is_some()) {
                let position_addr = position_addr.destroy_some();
                let position_meta =
                    authorized_borrow(&vault, sender, pool_addr, position_addr);
                some(position_meta.position_idx())
            } else { none() };

        let pool_signer = &generate_signer_for_extending(&PoolCap[pool_addr].extend_ref);
        let (amounts, mint_position_idx) =
            hook_factory::add_liquidity(
                pool_signer,
                address_of(sender),
                position_idx,
                stream
            );

        do_accounting(pool_signer, sender, &vault, amounts);

        if (mint_position_idx.is_some()) {
            position_idx = mint_position_idx;
            position_addr = some(
                mint_position(
                    &vault,
                    hook_type(pool_addr),
                    pool_addr,
                    position_idx.destroy_some(),
                    address_of(sender)
                )
            );
        };

        emit(
            LiquidityAdded {
                pool_addr,
                position_idx: position_idx.destroy_some(),
                assets: hook_factory::assets(pool_addr),
                amounts: amounts.map(|tx| tx.tx_amount()),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );

        (position_idx.destroy_some(), position_addr.destroy_some())
    }

    public entry fun create_pool_add_liquidity(
        sender: &signer, args: vector<u8>
    ) acquires Manager {
        let (manager, vault) = manager_vault_mut();
        let stream = &mut bcs_stream::new(args);
        let hook_type = deserialize_u8(stream);

        let cref = &hook_factory::create_pool(
            &vault, address_of(sender), hook_type, stream
        );
        let pool_signer = &generate_signer(cref);
        move_to(pool_signer, PoolCap { extend_ref: generate_extend_ref(cref) });

        let pool_addr = address_of(pool_signer);
        assert!(!manager.pools.contains(&pool_addr), EPOOL_EXISTED);
        manager.pools.push_back(pool_addr);

        let (amounts, mint_position_idx) =
            hook_factory::add_liquidity(
                pool_signer,
                address_of(sender),
                none(),
                stream
            );

        do_accounting(pool_signer, sender, &vault, amounts);

        if (mint_position_idx.is_some()) {
            let position_idx = mint_position_idx.destroy_some();
            mint_position(
                &vault,
                hook_type(pool_addr),
                pool_addr,
                position_idx,
                address_of(sender)
            );
        };

        emit(
            PoolCreated {
                pool_addr,
                hook_type: hook_type(pool_addr),
                assets: hook_factory::assets(pool_addr),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );

        emit(
            LiquidityAdded {
                pool_addr,
                position_idx: mint_position_idx.destroy_some(),
                assets: hook_factory::assets(pool_addr),
                amounts: amounts.map(|tx| tx.tx_amount()),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );
    }

    public entry fun remove_liquidity(sender: &signer, args: vector<u8>) acquires Manager, PoolCap {
        let (manager, vault) = manager_vault();

        let stream = &mut bcs_stream::new(args);
        let pool_addr = deserialize_address(stream);
        assert!(
            manager.pools.contains(&pool_addr) && is_object(pool_addr),
            EPOOL_NOTEXISTED
        );

        let position_addr = deserialize_address(stream);
        let position_meta = authorized_borrow(&vault, sender, pool_addr, position_addr);

        let pool_signer = &generate_signer_for_extending(&PoolCap[pool_addr].extend_ref);
        let (amounts, burn_position_idx) =
            hook_factory::remove_liquidity(
                pool_signer,
                address_of(sender),
                position_meta.position_idx(),
                stream
            );

        do_accounting(pool_signer, sender, &vault, amounts);

        if (burn_position_idx.is_some()) {
            burn_position(sender, position_addr);
        };

        emit(
            LiquidityRemoved {
                pool_addr,
                position_idx: position_meta.position_idx(),
                assets: hook_factory::assets(pool_addr),
                amounts: amounts.map(|tx| tx.tx_amount()),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );
    }

    public entry fun swap(sender: &signer, args: vector<u8>) acquires Manager, PoolCap {
        let (manager, vault) = manager_vault();

        let stream = &mut bcs_stream::new(args);
        let pool_addr = deserialize_address(stream);
        assert!(
            manager.pools.contains(&pool_addr) && is_object(pool_addr),
            EPOOL_NOTEXISTED
        );

        let pool_signer = &generate_signer_for_extending(&PoolCap[pool_addr].extend_ref);
        let txs = hook_factory::swap(pool_signer, address_of(sender), stream);

        do_accounting(pool_signer, sender, &vault, txs);

        let (tx_in, tx_out) = (txs[0], txs[1]); // swap returns two txs [tx in; tx out]
        let (amount_in, asset_in_index) = {
            let (_, index) = hook_factory::assets(pool_addr).index_of(&tx_in.tx_asset());
            (tx_in.tx_amount(), index)
        };
        let (amount_out, asset_out_index) = {
            let (_, index) = hook_factory::assets(pool_addr).index_of(&tx_out.tx_asset());
            (tx_out.tx_amount(), index)
        };
        emit(
            Swapped {
                pool_addr,
                assets: hook_factory::assets(pool_addr),
                asset_in_index,
                asset_out_index,
                amount_in,
                amount_out,
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );
    }

    public entry fun collect_fee(sender: &signer, args: vector<u8>) acquires Manager, PoolCap {
        let (manager, vault) = manager_vault_mut();

        let stream = &mut bcs_stream::new(args);
        let pool_addr = deserialize_address(stream);
        assert!(
            manager.pools.contains(&pool_addr) && is_object(pool_addr),
            EPOOL_NOTEXISTED
        );

        let position_addr = deserialize_address(stream);
        let position_meta = authorized_borrow(&vault, sender, pool_addr, position_addr);

        let pool_signer = &generate_signer_for_extending(&PoolCap[pool_addr].extend_ref);
        let amounts =
            hook_factory::collect_fee(
                pool_signer,
                address_of(sender),
                position_meta.position_idx()
            );

        emit(
            FeeCollected {
                pool_addr,
                hook_type: hook_type(pool_addr),
                position_idx: position_meta.position_idx(),
                assets: hook_factory::assets(pool_addr),
                amounts: amounts.map(|tx| tx.tx_amount()),
                creator: address_of(sender),
                ts: timestamp::now_microseconds()
            }
        );

        do_accounting(pool_signer, sender, &vault, amounts);
    }

    fun do_accounting(
        pool_signer: &signer,
        sender: &signer,
        vault: &signer,
        txs: vector<Tx>
    ) {
        let vault_addr = address_of(vault);
        let sender_addr = address_of(sender);

        txs.for_each_ref(
            |_tx| {
                let tx_asset = _tx.tx_asset();
                let tx_amount = _tx.tx_amount();
                let is_in = _tx.is_in();
                let is_incentive = _tx.is_incentive();
                let asset = address_to_object<Metadata>(tx_asset);
                if (tx_amount > 0) {
                    if (is_in) {
                        let start_balance =
                            primary_fungible_store::balance(vault_addr, asset);
                        primary_fungible_store::transfer(
                            sender, asset, vault_addr, tx_amount
                        );
                        let end_balance =
                            primary_fungible_store::balance(vault_addr, asset);
                        assert!(
                            tx_amount <= end_balance - start_balance,
                            EINSUFFICIENT_AMOUNT_TO_VAULT
                        );
                    } else {
                        primary_fungible_store::transfer(
                            vault, asset, sender_addr, tx_amount
                        );
                    };

                    if (is_incentive) {
                        hook_factory::update_incentive_reserve(
                            pool_signer, tx_asset, tx_amount, is_in
                        );
                    } else {
                        hook_factory::update_reserve(
                            pool_signer, tx_asset, tx_amount, is_in
                        );
                    }
                }
            }
        );
    }

    inline fun manager_vault(): (&Manager, signer) {
        let manager = borrow_global<Manager>(@tapp);
        let vault = create_signer_with_capability(&manager.vault);
        (manager, vault)
    }

    inline fun manager_vault_mut(): (&mut Manager, signer) {
        let manager = borrow_global_mut<Manager>(@tapp);
        let vault = create_signer_with_capability(&manager.vault);
        (manager, vault)
    }

    fun init_module(sender: &signer) {
        let (vault, vault_cap) = create_resource_account(sender, b"VAULT");
        position::init_collection(&vault);

        let manager = Manager { vault: vault_cap, pools: vector[] };
        move_to(sender, manager);
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&create_signer_for_test(@tapp));

        // basic::basic::init_module_for_test();
        // advanced::advanced::init_module_for_test();
        // vault::vault::init_module_for_test();
    }

    #[test_only]
    public fun get_vault(): signer acquires Manager {
        let manager = borrow_global_mut<Manager>(@tapp);
        create_signer_with_capability(&manager.vault)
    }

    #[test_only]
    public fun position_addr(
        pool_addr: address, position_idx: u64
    ): address acquires Manager {
        let vault = get_vault();
        let vault_addr = address_of(&vault);
        position::position_address(vault_addr, pool_addr, position_idx)
    }

    #[test_only]
    public fun event_pool_created_pool_addr(event: &PoolCreated): address {
        event.pool_addr
    }

    #[test_only]
    public fun event_pool_created_hook_type(event: &PoolCreated): u8 {
        event.hook_type
    }

    #[test_only]
    public fun event_pool_created_assets(event: &PoolCreated): vector<address> {
        event.assets
    }

    #[test_only]
    public fun event_pool_created_creator(event: &PoolCreated): address {
        event.creator
    }

    #[test_only]
    public fun event_pool_created_ts(event: &PoolCreated): u64 {
        event.ts
    }

    #[test_only]
    public fun event_liquidity_added_pool_addr(event: &LiquidityAdded): address {
        event.pool_addr
    }

    #[test_only]
    public fun event_liquidity_added_position_idx(event: &LiquidityAdded): u64 {
        event.position_idx
    }

    #[test_only]
    public fun event_liquidity_added_assets(event: &LiquidityAdded): vector<address> {
        event.assets
    }

    #[test_only]
    public fun event_liquidity_added_amounts(event: &LiquidityAdded): vector<u64> {
        event.amounts
    }

    #[test_only]
    public fun event_liquidity_added_creator(event: &LiquidityAdded): address {
        event.creator
    }

    #[test_only]
    public fun event_liquidity_added_ts(event: &LiquidityAdded): u64 {
        event.ts
    }

    #[test_only]
    public fun event_liquidity_removed_pool_addr(
        event: &LiquidityRemoved
    ): address {
        event.pool_addr
    }

    #[test_only]
    public fun event_liquidity_removed_position_idx(
        event: &LiquidityRemoved
    ): u64 {
        event.position_idx
    }

    #[test_only]
    public fun event_liquidity_removed_assets(event: &LiquidityRemoved): vector<address> {
        event.assets
    }

    #[test_only]
    public fun event_liquidity_removed_amounts(event: &LiquidityRemoved): vector<u64> {
        event.amounts
    }

    #[test_only]
    public fun event_liquidity_removed_creator(event: &LiquidityRemoved): address {
        event.creator
    }

    #[test_only]
    public fun event_liquidity_removed_ts(event: &LiquidityRemoved): u64 {
        event.ts
    }

    #[test_only]
    public fun event_swapped_pool_addr(event: &Swapped): address {
        event.pool_addr
    }

    #[test_only]
    public fun event_swapped_assets(event: &Swapped): vector<address> {
        event.assets
    }

    #[test_only]
    public fun event_swapped_asset_in_index(event: &Swapped): u64 {
        event.asset_in_index
    }

    #[test_only]
    public fun event_swapped_asset_out_index(event: &Swapped): u64 {
        event.asset_out_index
    }

    #[test_only]
    public fun event_swapped_amount_in(event: &Swapped): u64 {
        event.amount_in
    }

    #[test_only]
    public fun event_swapped_amount_out(event: &Swapped): u64 {
        event.amount_out
    }

    #[test_only]
    public fun event_swapped_creator(event: &Swapped): address {
        event.creator
    }

    #[test_only]
    public fun event_swapped_ts(event: &Swapped): u64 {
        event.ts
    }

    #[test_only]
    public fun event_fee_collected_pool_addr(event: &FeeCollected): address {
        event.pool_addr
    }

    #[test_only]
    public fun event_fee_collected_hook_type(event: &FeeCollected): u8 {
        event.hook_type
    }

    #[test_only]
    public fun event_fee_collected_position_idx(event: &FeeCollected): u64 {
        event.position_idx
    }

    #[test_only]
    public fun event_fee_collected_assets(event: &FeeCollected): vector<address> {
        event.assets
    }

    #[test_only]
    public fun event_fee_collected_amounts(event: &FeeCollected): vector<u64> {
        event.amounts
    }

    #[test_only]
    public fun event_fee_collected_creator(event: &FeeCollected): address {
        event.creator
    }

    #[test_only]
    public fun event_fee_collected_ts(event: &FeeCollected): u64 {
        event.ts
    }
}

