module advanced::advanced {
    use std::bcs::to_bytes;
    use std::option::{none, some, Option};
    use std::signer::address_of;
    use aptos_std::bcs_stream::{BCSStream, deserialize_u64, deserialize_address};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::signer;
    use aptos_framework::event::emit;
    use aptos_framework::timestamp;

    const OP_DO_STH: u64 = 0;
    const OP_DO_OTHER: u64 = 1;

    const ENOT_IMPLEMENTED: u64 = 0;

    struct PoolState has key {
        fee_rate: u64,
        total_value: u64,
        assets: vector<address>,
        positions: OrderedMap<u64, Position>,
        positions_count: u64
    }

    struct CampaignRegistry has key {
        campaigns: vector<Campaign>,
        campaigns_counter: u64
    }

    struct Campaign has store {
        campaign_idx: u64,
        token: address,
        total_amount: u64,
        distributed_amount: u64,
        distribution_rps: u64,
        last_distribution_at: u64,
        position_rewards: vector<u64>
    }

    struct Position has copy, drop, store {
        value: vector<u64>,
        fee: vector<u64>
    }

    struct CampaignReward has copy, drop, store {
        token: address,
        amount: u64
    }

    #[event]
    struct Created has drop, store {}

    #[event]
    struct Added has drop, store {}

    #[event]
    struct Removed has drop, store {}

    #[event]
    struct Swapped has drop, store {}

    #[event]
    struct CollectedFee has drop, store {}

    public fun pool_seed(assets: vector<address>, fee: u64): vector<u8> {
        let seed = vector[];
        seed.append(to_bytes(&assets));
        seed.append(to_bytes(&fee));
        seed
    }

    /// Create new pool
    public fun create_pool(
        pool_signer: &signer,
        assets: vector<address>,
        fee: u64,
        _sender: address
    ) {
        // TODO: write your logic of pool creation here
        move_to(
            pool_signer,
            PoolState {
                assets,
                fee_rate: fee,
                positions: ordered_map::new(),
                positions_count: 0,
                total_value: 0 // initial state
            }
        );
        move_to(pool_signer, CampaignRegistry { campaigns: vector[], campaigns_counter: 0 });
        emit(Created {});
    }

    public fun add_liquidity(
        pool_signer: &signer,
        position_idx: Option<u64>,
        stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, 0x1::option::Option<u64>) acquires PoolState, CampaignRegistry {
        // TODO: write your logic of adding liquidity here

        // deserialize params
        let value = deserialize_u64(stream);

        // get mutable pool state
        let pool_state = &mut PoolState[signer::address_of(pool_signer)];

        // based on `value` and `pool_factor` calculate how much money goes in to pool
        // here we use very simple logic, just put `value` into each asset
        let amounts = pool_state.assets.map(|_| value);

        // update pool state
        let additional_value = amounts.fold(0, |acc, amount| acc + amount);
        pool_state.total_value += additional_value;

        // update position and mint new position if needed
        let mint_position = none();
        if (position_idx.is_none()) {
            pool_state.positions.add(
                pool_state.positions_count,
                Position {
                    value: amounts,
                    fee: amounts.map(|_| 0)
                }
            );
            mint_position = some(pool_state.positions_count);
            pool_state.positions_count += 1;

            // add position to campaign rewards
            let campaign_registry = &mut CampaignRegistry[address_of(pool_signer)];
            campaign_registry.campaigns.for_each_mut(|campaign| {
                campaign.position_rewards.push_back(0);
            });
        } else {
            let position_idx = position_idx.destroy_some();
            let position = pool_state.positions.borrow_mut(&position_idx);
            position.value = position.value.zip_map(amounts, |a, b| a + b);
        };

        // emit event
        emit(Added {});

        // return additional asset amounts and minted position index
        (
            amounts, // amount of money goes in to pool
            mint_position
        )
    }

    public fun remove_liquidity(
        pool_signer: &signer,
        position_idx: u64,
        stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, 0x1::option::Option<u64>, vector<CampaignReward>) acquires PoolState, CampaignRegistry {
        // TODO: write your logic of removing liquidity here

        // deserialize params
        let value = deserialize_u64(stream);

        // get mutable pool state
        let pool_state = &mut PoolState[signer::address_of(pool_signer)];

        // check if position exists
        assert!(pool_state.positions.contains(&position_idx));
        let position = pool_state.positions.borrow_mut(&position_idx);

        // based on `value` and `pool_factor` calculate how much money goes out from pool
        let amounts = pool_state.assets.map(|_| value);

        // update pool state
        let removal_value = amounts.fold(0, |acc, amount| acc + amount);
        pool_state.total_value -= removal_value;

        // update position
        let position = pool_state.positions.borrow_mut(&position_idx);
        position.value = position.value.zip_map(amounts, |a, b| a - b);

        // collect rewards
        let campaign_registry = &mut CampaignRegistry[address_of(pool_signer)];
        let position_campaign_rewards = vector[];
        campaign_registry.campaigns.for_each_mut(|campaign| {
            let position_reward = campaign.position_rewards.borrow_mut(position_idx);
            position_campaign_rewards.push_back(
                CampaignReward { token: campaign.token, amount: *position_reward }
            );
            *position_reward = 0;
        });

        // remove position if value becomes 0
        let removed_position = none();
        if (position.value.fold(0, |ac, amt| ac + amt) == 0) {
            pool_state.positions.remove(&position_idx);
            removed_position = some(position_idx);
        };

        (
            amounts, // amount of money goes out from pool
            removed_position,
            position_campaign_rewards
        )
    }

    public fun swap(
        pool_signer: &signer, _stream: &mut 0x1::bcs_stream::BCSStream, _sender: address
    ): (u64, u64, u64, u64) acquires PoolState, CampaignRegistry {
        /// Swap two assets, one will be put into the pool, one will be taken out of the pool
        let pool_state = &mut PoolState[address_of(pool_signer)];

        // TODO: write your logic of swapping here
        let asset_in_index = deserialize_u64(_stream);
        let asset_out_index = deserialize_u64(_stream);
        let asset_in_amount = deserialize_u64(_stream);
        let asset_out_amount = deserialize_u64(_stream);
        emit(Swapped {});

        // we could add campaign rewards here to related positions during swap
        let campaign_registry = &mut CampaignRegistry[address_of(pool_signer)];
        // TODO: write your logic of adding campaign rewards here. Example:
        campaign_registry.campaigns.for_each_mut(
            |campaign| {
                let rewards_to_distribute =
                    campaign.distribution_rps
                        * (timestamp::now_seconds() - campaign.last_distribution_at);

                // capped rewards_to_distribute down to remaining amount
                if (rewards_to_distribute + campaign.distributed_amount
                    > campaign.total_amount) {
                    rewards_to_distribute =
                        campaign.total_amount - campaign.distributed_amount;
                };

                // distribute rewards to positions
                if (rewards_to_distribute > 0) {
                    let rewards_each_position =
                        rewards_to_distribute / pool_state.positions.length();
                    campaign.position_rewards = campaign.position_rewards.map(
                        |position_reward| position_reward + rewards_each_position
                    );
                    campaign.last_distribution_at = timestamp::now_seconds();
                    campaign.distributed_amount += rewards_to_distribute;
                }
            }
        );

        // We return the indices of assets and their amounts
        (asset_in_index, asset_out_index, asset_in_amount, asset_out_amount)
    }

    public fun collect_fee(
        pool_signer: &signer, position_idx: u64, _creator: address
    ): vector<u64> acquires PoolState {
        let pool = &mut PoolState[address_of(pool_signer)];
        let position = pool.positions.borrow_mut(&position_idx);

        // collected fee
        let fee = position.fee;

        // reset accumulated fee to 0
        position.fee = position.fee.map(|_| 0);

        emit(CollectedFee {});

        // return fee amounts
        fee
    }

    public fun add_campaign(
        pool_signer: &signer, stream: &mut BCSStream
    ) acquires CampaignRegistry, PoolState {
        // serialize params
        let token = deserialize_address(stream);
        let total_amount = deserialize_u64(stream);
        let distribution_rps = deserialize_u64(stream);

        // get pool state
        let pool_state = &mut PoolState[address_of(pool_signer)];
        let positions = pool_state.positions.keys();

        let campaign_registry = &mut CampaignRegistry[address_of(pool_signer)];
        campaign_registry.campaigns.push_back(
            Campaign {
                campaign_idx: campaign_registry.campaigns_counter,
                token,
                total_amount,
                distributed_amount: 0,
                distribution_rps,
                last_distribution_at: timestamp::now_seconds(),
                position_rewards: positions.map(|_| 0)
            }
        );
        campaign_registry.campaigns_counter += 1;
        // update pool state
    }

    public fun pool_stop_campaign(
        pool_signer: &signer, stream: &mut BCSStream
    ): u64 acquires CampaignRegistry {
        // serialize params
        let campaign_idx = deserialize_u64(stream);

        // calc remaining amount
        let campaign_registry = &mut CampaignRegistry[address_of(pool_signer)];
        let campaign = campaign_registry.campaigns.borrow_mut(campaign_idx);

        campaign.total_amount - campaign.distributed_amount
    }

    public fun run_pool_op(pool_signer: &signer, _stream: &mut BCSStream) acquires PoolState {
        // Run pool operation. It's useful when your pool have special logic.
        // This function returns nothing, just purely receives arguments and modify state.
        let op_code = deserialize_u64(_stream);
        let pool_state = &mut PoolState[address_of(pool_signer)];
        if (op_code == OP_DO_STH) {
            do_sth(pool_state, _stream);
        } else if (op_code == OP_DO_OTHER) {
            do_other(pool_signer, _stream);
        } else {
            abort ENOT_IMPLEMENTED
        };
    }

    fun do_sth(pool_state: &mut PoolState, stream: &mut BCSStream) {
        // serialize params
        // calculate something
        // update pool state
    }

    fun do_other(pool_signer: &signer, stream: &mut BCSStream) {
        // serialize params
        // calculate something else
        // update pool signer: publish new struct
        // move_to(pool_signer, NewStruct {...});
    }

    public fun campaign_reward_token(self: &CampaignReward): address {
        self.token
    }

    public fun campaign_reward_amount(self: &CampaignReward): u64 {
        self.amount
    }
}

