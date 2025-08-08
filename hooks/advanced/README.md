# Advanced Hook

An advanced liquidity pool implementation for the Aptos blockchain with campaign rewards, fee collection, and sophisticated position management. This module extends the basic functionality with additional features for complex DeFi operations.

## Overview

The Advanced Hook module implements a sophisticated Automated Market Maker (AMM) with the following features:
- Pool creation and management with multiple assets
- Advanced liquidity provision and removal with position tracking
- Asset swapping with fee collection
- Campaign reward distribution system
- Position-based fee accumulation and collection
- Custom pool operations

## Structures

### PoolState
```move
struct PoolState has key {
    fee_rate: u64,                           // Pool fee rate
    total_value: u64,                        // Total value locked in pool
    assets: vector<address>,                 // Vector of asset addresses
    positions: OrderedMap<u64, Position>,    // Map of position ID to Position
    positions_count: u64,                    // Total number of positions created
}
```

### Position
```move
struct Position has key {
    value: vector<u64>,  // Amount of liquidity for each asset
    fee: vector<u64>,    // Accumulated fees for each asset
}
```

### CampaignRegistry
```move
struct CampaignRegistry {
    campaigns: vector<Campaign>,  // List of active campaigns
    campaigns_counter: u64,       // Total number of campaigns created
}
```

### Campaign
```move
struct Campaign {
    campaign_idx: u64,                    // Unique campaign identifier
    token: address,                       // Reward token address
    total_amount: u64,                    // Total reward amount
    distributed_amount: u64,              // Amount already distributed
    distribution_rps: u64,                // Rewards per second rate
    last_distribution_at: u64,            // Last distribution timestamp
    position_rewards: vector<u64>         // Rewards per position
}
```

### CampaignReward
```move
struct CampaignReward has copy, drop, store {
    token: address,  // Reward token address
    amount: u64      // Reward amount
}
```

## Functions

### Create Pool
```move
public fun create_pool(
    pool_signer: &signer,
    assets: vector<address>,
    fee: u64,
    _sender: address
)
```

Creates a new liquidity pool with the specified assets and fee rate.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `assets`: Vector of asset addresses (supports multiple assets)
- `fee`: Fee rate for the pool
- `_sender`: Address of the pool creator

**Events:** Emits `Created` event

**Logic:**
- Initializes pool with zero total value and empty positions
- Sets up fee rate and asset list
- Creates campaign registry for reward distribution

### Add Liquidity
```move
public fun add_liquidity(
    pool_signer: &signer,
    position_idx: Option<u64>,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

Adds liquidity to the pool with sophisticated position management.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `position_idx`: Optional position index (None for new position, Some for existing)
- `stream`: BCS stream containing liquidity amount
- `_sender`: Address of the liquidity provider

**Returns:**
- `vector<u64>`: Amount of each asset added to the pool
- `Option<u64>`: New position index if a new position was created

**Events:** Emits `Added` event

**Logic:**
- If `position_idx` is `None`: Creates a new position with equal amounts for each asset
- If `position_idx` is `Some`: Updates the existing position by adding to each asset
- Updates pool total value
- Distributes equal amounts across all assets in the pool

### Remove Liquidity
```move
public fun remove_liquidity(
    pool_signer: &signer,
    position_idx: u64,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>, vector<CampaignReward>)
```

Removes liquidity from a specific position and collects accumulated rewards.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `position_idx`: Index of the position to remove liquidity from
- `stream`: BCS stream containing amount to remove
- `_sender`: Address of the liquidity provider

**Returns:**
- `vector<u64>`: Amount of each asset removed from the pool
- `Option<u64>`: Position index if the position was completely removed
- `vector<CampaignReward>`: Collected campaign rewards

**Logic:**
- Validates that the position exists
- Removes equal amounts from each asset in the position
- Updates pool total value
- Collects all accumulated campaign rewards for the position
- Removes position if total value becomes zero
- Resets position rewards to zero after collection

### Swap
```move
public fun swap(
    pool_signer: &signer,
    _stream: &mut BCSStream,
    _sender: address
): (u64, u64, u64, u64)
```

Swaps assets within the pool and distributes campaign rewards.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `_stream`: BCS stream containing swap parameters
- `_sender`: Address of the swapper

**Returns:**
- `u64`: Asset in index
- `u64`: Asset out index
- `u64`: Amount in
- `u64`: Amount out

**Events:** Emits `Swapped` event

**Logic:**
- Deserializes swap parameters from stream
- Distributes campaign rewards to all positions based on time elapsed
- Calculates rewards per position and updates campaign state
- Caps rewards to remaining campaign amount
- Updates last distribution timestamp

### Collect Fee
```move
public fun collect_fee(
    pool_signer: &signer,
    position_idx: u64,
    _creator: address
): vector<u64>
```

Collects accumulated fees from a specific position.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `position_idx`: Index of the position to collect fees from
- `_creator`: Address of the fee collector

**Returns:**
- `vector<u64>`: Collected fee amounts for each asset

**Events:** Emits `CollectedFee` event

**Logic:**
- Retrieves accumulated fees for the position
- Resets position fees to zero
- Returns collected fee amounts

### Add Campaign
```move
public fun add_campaign(
    pool_signer: &signer,
    stream: &mut BCSStream
)
```

Creates a new reward campaign for the pool.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `stream`: BCS stream containing campaign parameters

**Logic:**
- Deserializes campaign parameters (token, total amount, distribution rate)
- Creates new campaign with current timestamp
- Adds campaign to registry
- Increments campaign counter

### Stop Campaign
```move
public fun pool_stop_campaign(
    pool_signer: &signer,
    stream: &mut BCSStream
): u64
```

Stops a campaign and returns remaining reward amount.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `stream`: BCS stream containing campaign index

**Returns:**
- `u64`: Remaining reward amount

**Logic:**
- Calculates remaining undistributed amount
- Returns total amount minus distributed amount

### Run Pool Operation
```move
public fun run_pool_op(
    pool_signer: &signer,
    _stream: &mut BCSStream
)
```

Executes custom pool operations based on operation code.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `_stream`: BCS stream containing operation parameters

**Logic:**
- Deserializes operation code from stream
- Routes to appropriate operation handler:
  - `OP_DO_STH` (0): Executes `do_sth` function
  - `OP_DO_OTHER` (1): Executes `do_other` function
- Aborts with `ENOT_IMPLEMENTED` for unknown operations

## Campaign Reward System

The advanced hook implements a sophisticated reward distribution system:

1. **Campaign Creation**: Pools can create multiple reward campaigns with different tokens
2. **Time-based Distribution**: Rewards are distributed based on time elapsed and rate per second
3. **Position-based Allocation**: Rewards are distributed equally among all positions
4. **Automatic Collection**: Rewards are automatically collected when liquidity is removed
5. **Capped Distribution**: Total distributed amount cannot exceed campaign total

## Fee Collection System

The module includes a comprehensive fee collection mechanism:

1. **Fee Accumulation**: Fees are accumulated per position and per asset
2. **Manual Collection**: Fees can be collected manually using `collect_fee`
3. **Reset on Collection**: Collected fees are reset to zero
4. **Asset-specific Tracking**: Fees are tracked separately for each asset

## Events

The module emits the following events:

- `Created`: When a new pool is created
- `Added`: When liquidity is added to a pool
- `Removed`: When liquidity is removed from a pool
- `Swapped`: When assets are swapped in a pool
- `CollectedFee`: When fees are collected from a position

## Error Codes

- `ENOT_IMPLEMENTED = 0`: Used when a function is not yet implemented

## Operation Codes

- `OP_DO_STH = 0`: Custom operation 1
- `OP_DO_OTHER = 1`: Custom operation 2

## Usage Examples

### Creating a Pool
```move
let assets = vector[coin_a_address, coin_b_address, coin_c_address];
let fee = 3000; // 0.3% fee
create_pool(pool_signer, assets, fee, creator_address);
```

### Adding Liquidity
```move
// Create new position
let (amounts, new_position) = add_liquidity(pool_signer, none(), stream, sender);

// Add to existing position
let (amounts, _) = add_liquidity(pool_signer, some(position_idx), stream, sender);
```

### Removing Liquidity with Rewards
```move
let (amounts, removed_position, rewards) = remove_liquidity(pool_signer, position_idx, stream, sender);
```

### Collecting Fees
```move
let fees = collect_fee(pool_signer, position_idx, collector_address);
```

### Adding Campaign
```move
add_campaign(pool_signer, campaign_stream);
```

### Swapping Assets
```move
let (in_idx, out_idx, in_amount, out_amount) = swap(pool_signer, swap_stream, sender);
```

## Advanced Features

### Multi-Asset Support
Unlike the basic hook, the advanced hook supports pools with multiple assets, allowing for more complex DeFi operations.

### Campaign Rewards
The reward system enables pools to distribute tokens to liquidity providers based on time and participation.

### Fee Management
Sophisticated fee tracking and collection system that accumulates fees per position and per asset.

### Custom Operations
Extensible operation framework allowing pools to implement custom logic through the `run_pool_op` function.

## Notes

- This implementation supports multiple assets in a single pool
- Campaign rewards are distributed automatically during swaps
- Fees are accumulated per position and can be collected manually
- The swap function includes reward distribution logic
- Position management is more sophisticated with per-asset tracking
- Error handling should be enhanced for production deployment
