module tapp::hook_factory {
    use std::option::{Option};
    use std::signer::address_of;
    use std::vector::{range};
    use aptos_std::bcs_stream;
    use aptos_std::bcs_stream::{BCSStream, deserialize_u64, deserialize_vector};
    use aptos_std::ordered_map;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object;
    use aptos_framework::object::{ConstructorRef, create_named_object, generate_signer};

    const HOOK_BASIC: u8 = 1;
    const HOOK_ADVANCED: u8 = 2;
    const HOOK_VAULT: u8 = 3;
    const YOUR_HOOK: u8 = 4;

    const EPOOL_NOT_IMPLEMENTED: u64 = 0xa10001;
    const E_INCENTIVE_TOKEN_NOT_FOUND: u64 = 0xb4;
    const E_INSUFFICIENT_INCENTIVE_RESERVE: u64 = 0xb5;

    struct PoolMeta has key, drop, copy, store {
        pool_addr: address,
        hook_type: u8,
        assets: vector<address>,
        reserves: vector<u64>,
        is_paused: bool
    }

    struct PoolIncentiveMeta has key, drop, copy, store {
        pool_addr: address,
        assets: vector<address>,
        reserves: vector<u64>
    }

    struct Tx has copy, drop {
        asset: address,
        amount: u64,
        in: bool,
        is_incentive: bool
    }

    public(package) fun create_pool(
        vault: &signer,
        creator: address,
        hook_type: u8,
        stream: &mut BCSStream
    ): ConstructorRef {
        let assets =
            sort_check_assets(
                deserialize_vector(
                    stream, |stream| bcs_stream::deserialize_address(stream)
                )
            );
        let fee = deserialize_u64(stream);

        if (hook_type == HOOK_BASIC) {
            let seed = vector[hook_type];
            seed.append(basic::basic::pool_seed(assets, fee));
            let cref = create_named_object(vault, seed);            let pool_signer = &generate_signer(&cref);
            let pool_addr = address_of(pool_signer);
            basic::basic::create_pool(pool_signer, assets, fee, creator);
            let pool_meta = new_pool_meta(pool_addr, hook_type, assets);
            move_to(pool_signer, pool_meta);
            return cref
        };

        if (hook_type == HOOK_VAULT) {
            let seed = vector[hook_type];
            seed.append(basic::basic::pool_seed(assets, fee));
            let cref = create_named_object(vault, seed);
            let pool_signer = &generate_signer(&cref);
            let pool_addr = address_of(pool_signer);
            vault::vault::create_pool(pool_signer, assets, fee, stream, creator);
            let pool_meta = new_pool_meta(pool_addr, hook_type, assets);
            move_to(pool_signer, pool_meta);
            return cref
        };

        if (hook_type == HOOK_ADVANCED) {
            let seed = vector[hook_type];
            seed.append(basic::basic::pool_seed(assets, fee));
            let cref = create_named_object(vault, seed);            let pool_signer = &generate_signer(&cref);
            let pool_addr = address_of(pool_signer);
            advanced::advanced::create_pool(pool_signer, assets, fee, creator);
            let pool_meta = new_pool_meta(pool_addr, hook_type, assets);
            move_to(pool_signer, pool_meta);
            return cref
        };

        // TODO: your hook type here
        if (hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun add_liquidity(
        pool_signer: &signer,
        creator: address,
        position_idx: Option<u64>,
        stream: &mut BCSStream
    ): (vector<Tx>, Option<u64>) acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];
        if (pool_meta.hook_type == HOOK_BASIC) {
            let (amounts, mint_position) =
                basic::basic::add_liquidity(pool_signer, position_idx, stream, creator);
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], amt, true)
                );
            return (txs, mint_position)
        };

        if (pool_meta.hook_type == HOOK_VAULT) {
            let (amounts, mint_position) =
                vault::vault::deposit(pool_signer, position_idx, stream, creator);
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], (amt as u64), true)
                );
            return (txs, mint_position)
        };

        if (pool_meta.hook_type == HOOK_ADVANCED) {
            let (amounts, mint_position) =
                advanced::advanced::add_liquidity(
                    pool_signer, position_idx, stream, creator
                );
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], amt, true)
                );
            return (txs, mint_position)
        };

        // TODO: your hook type here
        if (pool_meta.hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun remove_liquidity(
        pool_signer: &signer,
        creator: address,
        position_idx: u64,
        stream: &mut BCSStream
    ): (vector<Tx>, Option<u64>) acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];

        if (pool_meta.hook_type == HOOK_BASIC) {
            let (amounts, burn_position) =
                basic::basic::remove_liquidity(pool_signer, position_idx, stream, creator);
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], amt, false)
                );
            return (txs, burn_position)
        };

        if (pool_meta.hook_type == HOOK_VAULT) {
            let (amounts, burn_position) =
                vault::vault::withdraw(pool_signer, position_idx, stream, creator);
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], (amt as u64), false)
                );
            return (txs, burn_position)
        };

        if (pool_meta.hook_type == HOOK_ADVANCED) {
            let (amounts, burn_position, rewards) =
                advanced::advanced::remove_liquidity(
                    pool_signer, position_idx, stream, creator
                );
            let assets = pool_meta.assets;
            let txs =
                range(0, amounts.length()).zip_map(
                    amounts, |index, amt| tx(assets[index], amt, false)
                );
            rewards.for_each(|reward| {
                txs.push_back(
                    incentive_tx(
                        reward.campaign_reward_token(),
                        reward.campaign_reward_amount(),
                        false
                    )
                );
            });

            return (txs, burn_position)
        };

        // TODO: your hook type here
        if (pool_meta.hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun swap(
        pool_signer: &signer, creator: address, stream: &mut BCSStream
    ): vector<Tx> acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];
        if (pool_meta.hook_type == HOOK_BASIC) {
            let (a2b, amount_in, amount_out) =
                basic::basic::swap(pool_signer, stream, creator);
            let assets = pool_meta.assets;
            return if (a2b) {
                vector[tx(assets[0], amount_in, true), tx(assets[1], amount_out, false)]
            } else {
                vector[tx(assets[1], amount_in, true), tx(assets[0], amount_out, false)]
            }
        };

        if (pool_meta.hook_type == HOOK_VAULT) {
            vault::vault::swap(pool_signer, stream, creator);
            return vector[]
        };

        if (pool_meta.hook_type == HOOK_ADVANCED) {
            let (i, j, dx, dy) = advanced::advanced::swap(pool_signer, stream, creator);
            let assets = pool_meta.assets;
            return vector[tx(assets[i], dx as u64, true), tx(assets[j], dy as u64, false)]
        };

        // TODO: your hook type here
        if (pool_meta.hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun collect_fee(
        pool_signer: &signer, creator: address, position_idx: u64
    ): vector<Tx> acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];
        if (pool_meta.hook_type == HOOK_VAULT) {
            let (amounts) = vault::vault::collect_fee(pool_signer, creator);

            let txs =
                pool_meta.assets.zip_map(
                    amounts, |asset, amount| tx(asset, amount as u64, false)
                );
            return txs
        };

        if (pool_meta.hook_type == HOOK_ADVANCED) {
            let (amounts) =
                advanced::advanced::collect_fee(pool_signer, position_idx, creator);
            let txs =
                pool_meta.assets.zip_map(
                    amounts, |asset, amount| tx(asset, amount as u64, false)
                );
            return txs
        };

        // TODO: your hook type here
        if (pool_meta.hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun run_pool_op(
        pool_signer: &signer, stream: &mut BCSStream
    ) acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];

        if (pool_meta.hook_type == HOOK_ADVANCED) {
            advanced::advanced::run_pool_op(pool_signer, stream);
            return;
        };

        // TODO: your hook type here
        if (pool_meta.hook_type == YOUR_HOOK) {
            abort EPOOL_NOT_IMPLEMENTED
        };

        abort EPOOL_NOT_IMPLEMENTED
    }

    public(package) fun new_pool_meta(
        pool_addr: address, hook_type: u8, assets: vector<address>
    ): PoolMeta {
        PoolMeta {
            pool_addr,
            hook_type,
            assets,
            reserves: assets.map(|_| 0),
            is_paused: false
        }
    }

    public(package) fun update_incentive_reserve(
        pool_signer: &signer,
        asset: address,
        amount: u64,
        is_in: bool
    ) acquires PoolIncentiveMeta {
        let incentive_meta = &mut PoolIncentiveMeta[address_of(pool_signer)];
        let (found, index) = incentive_meta.assets.index_of(&asset);
        if (found) {
            if (is_in) {
                *incentive_meta.reserves.borrow_mut(index) += amount
            } else {
                assert!(
                    amount <= *incentive_meta.reserves.borrow(index),
                    E_INSUFFICIENT_INCENTIVE_RESERVE
                );
                *incentive_meta.reserves.borrow_mut(index) -= amount
            };
        } else {
            assert!(is_in, E_INCENTIVE_TOKEN_NOT_FOUND);
            incentive_meta.assets.push_back(asset);
            incentive_meta.reserves.push_back(amount);
        };
    }

    public(package) fun update_reserve(
        pool_signer: &signer,
        asset: address,
        amount: u64,
        is_in: bool
    ) acquires PoolMeta {
        let pool_meta = &mut PoolMeta[address_of(pool_signer)];
        let (found, index) = pool_meta.assets.index_of(&asset);
        if (found) {
            if (is_in) {
                *pool_meta.reserves.borrow_mut(index) += amount
            } else {
                *pool_meta.reserves.borrow_mut(index) -= amount
            };
        } else {
            assert!(is_in);
            pool_meta.assets.push_back(asset);
            pool_meta.reserves.push_back(amount);
        };
    }

    public(package) fun assets(pool: address): vector<address> acquires PoolMeta {
        PoolMeta[pool].assets
    }

    public(package) fun reserves(pool: address): vector<u64> acquires PoolMeta {
        PoolMeta[pool].reserves
    }

    public(package) fun tx(asset: address, amount: u64, in: bool): Tx {
        Tx { asset, amount, in, is_incentive: false }
    }

    public(package) fun incentive_tx(
        asset: address, amount: u64, in: bool
    ): Tx {
        Tx { asset, amount, in, is_incentive: true }
    }

    public(package) fun tx_asset(self: &Tx): address {
        self.asset
    }

    public(package) fun tx_amount(self: &Tx): u64 {
        self.amount
    }

    public(package) fun is_in(self: &Tx): bool {
        self.in
    }

    public(package) fun is_incentive(self: &Tx): bool {
        self.is_incentive
    }

    public(package) fun hook_type(pool: address): u8 acquires PoolMeta {
        PoolMeta[pool].hook_type
    }

    inline fun sort_check_assets(unsorted: vector<address>): vector<address> {
        let map = ordered_map::new();
        let i = 0;
        loop {
            if (i == unsorted.length()) break;
            let asset_addr = unsorted[i];
            object::address_to_object<Metadata>(asset_addr); // check asset
            map.add(unsorted[i], true);
            i += 1;
        };
        let sorted_assets = map.keys();
        sorted_assets
    }

    #[test_only]
    public fun get_pool_reserves(pool_addr: address): vector<u64> acquires PoolMeta {
        PoolMeta[pool_addr].reserves
    }
}

