module basic::basic {
    use std::bcs::to_bytes;
    use std::option::{none, some, Option};
    use aptos_std::bcs_stream::{BCSStream, deserialize_u64, deserialize_bool};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::signer;
    use aptos_framework::event;

    const ENOT_IMPLEMENTED: u64 = 0;

    struct PoolState has key {
        state: u64,
        amounts: vector<u64>,
        positions: OrderedMap<u64, Position>,
        positions_count: u64
    }

    struct Position has copy, drop, store {
        value: u64
    }

    #[event]
    struct Created has drop, store {}

    #[event]
    struct Added has drop, store {}

    #[event]
    struct Removed has drop, store {}

    #[event]
    struct Swapped has drop, store {}

    public fun pool_seed(assets: vector<address>, fee: u64): vector<u8> {
        let seed = vector[];
        seed.append(to_bytes(&assets));
        seed.append(to_bytes(&fee));
        seed
    }

    public fun create_pool(
        pool_signer: &signer,
        assets: vector<address>,
        fee: u64,
        _sender: address
    ) {
        // TODO: write your logic of pool creation here

        // assertions
        assert!(assets.length() == 2); // only two assets supported
        assert!(fee > 0 && fee < 10000);

        // publish pool state
        move_to(
            pool_signer,
            PoolState {
                state: 0, // initial state
                amounts: vector[0, 0], // initial amounts
                positions: ordered_map::new(),
                positions_count: 0
            }
        );
        event::emit(Created {});
    }

    public fun add_liquidity(
        pool_signer: &signer,
        position_idx: Option<u64>,
        stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, 0x1::option::Option<u64>) acquires PoolState {
        // TODO: write your logic of adding liquidity here

        // deserialize params
        let value = deserialize_u64(stream);

        // get mutable pool state
        let pool_state = &mut PoolState[signer::address_of(pool_signer)];

        // based on `value` calculate how much money goes in to pool
        // here we use very simple logic, just put `value` into each asset
        let additional_values = pool_state.amounts.map(|_| value);

        // update pool state
        pool_state.amounts = pool_state.amounts.zip_map(additional_values, |a, b| a + b);

        // update and mint position (if any)
        let mint_position = none();
        if (position_idx.is_none()) {
            pool_state.positions.add(pool_state.positions_count, Position { value });
            mint_position = some(pool_state.positions_count);
            pool_state.positions_count += 1;
        } else {
            let position_idx = position_idx.destroy_some();
            let position = pool_state.positions.borrow_mut(&position_idx);
            position.value = value;
        };

        event::emit(Added {});

        (
            additional_values, // amount of money goes in to pool
            mint_position
        )
    }

    public fun remove_liquidity(
        pool_signer: &signer,
        position_idx: u64,
        stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, 0x1::option::Option<u64>) acquires PoolState {
        // TODO: write your logic of removing liquidity here

        // deserialize params
        let value = deserialize_u64(stream);

        // get mutable pool state
        let pool_state = &mut PoolState[signer::address_of(pool_signer)];

        // check if position exists
        assert!(pool_state.positions.contains(&position_idx));
        let position = pool_state.positions.borrow_mut(&position_idx);

        // based on `value` calculate how much money goes in to pool
        // here we use very simple logic, just put `value` into each asset
        let removal_values = pool_state.amounts.map(|_| value);

        // update pool state
        pool_state.amounts = pool_state.amounts.zip_map(removal_values, |a, b| a - b);

        // update position
        assert!(position.value >= value);
        position.value -= value;

        // remove position if value becomes 0
        let removed_position = none();
        if (position.value == 0) {
            pool_state.positions.remove(&position_idx);
            removed_position = some(position_idx);
        };

        (
            removal_values, // amount of money goes out from pool
            removed_position
        )
    }

    public fun swap(
        _pool_signer: &signer, _stream: &mut 0x1::bcs_stream::BCSStream, _sender: address
    ): (bool, u64, u64) {
        // TODO: write your logic of swapping here

        // deserialize params
        let a2b = deserialize_bool(_stream);
        let amount_in = deserialize_u64(_stream);
        let amount_out = deserialize_u64(_stream);

        // do swapping logic

        event::emit(Swapped {});

        // return whether it was a2b swap, amount_in and amount_out
        (a2b, amount_in, amount_out)
    }
}
