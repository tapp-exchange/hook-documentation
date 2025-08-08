# Basic Hook

A simple liquidity pool implementation for the Aptos blockchain. This module provides basic functionality for creating pools, adding/removing liquidity, and swapping assets.

## Overview

The Base Hook module implements a basic Automated Market Maker (AMM) with the following features:
- Pool creation and management
- Liquidity provision and removal
- Asset swapping (swapping )
- Position tracking for liquidity providers

## Structures

### PoolState
```move
struct PoolState has key {
    state: u64,                    // Pool state identifier
    positions: OrderedMap<u64, Position>,  // Map of position ID to Position
    positions_count: u64,          // Total number of positions created
}
```

### Position
```move
struct Position has key {
    value: u64,  // Amount of liquidity in this position
}
```

## Functions

### Create Pool
```move
public fun create_pool(
    pool_signer: &signer,
    assets: vector<address>,
    fee: u64,
    sender: address
) {
    move_to(pool_signer, PoolState {
        state: 0,
        positions: ordered_map::new(),
        positions_count: 0,
    });
    event::emit(Created {});
}
```

Creates a new liquidity pool with the specified assets and fee rate.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `assets`: Vector of asset addresses (currently supports 2 assets)
- `fee`: Fee rate for the pool
- `sender`: Address of the pool creator

**Events:** Emits `Created` event

### Add Liquidity
```move
public fun add_liquidity(
    pool_signer: &signer,
    position_idx: Option<u64>,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>) {
    let value = deserialize_u64(stream);
    let pool_state = &mut PoolState[signer::address_of(pool_signer)];

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
    (vector[], mint_position)
}
```

Adds liquidity to the pool. Can either create a new position or add to an existing one.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `position_idx`: Optional position index (None for new position, Some for existing)
- `stream`: BCS stream containing liquidity amount
- `_sender`: Address of the liquidity provider

**Returns:**
- `vector<u64>`: Amount of assets added to the pool
- `Option<u64>`: New position index if a new position was created

**Events:** Emits `Added` event

**Logic:**
- If `position_idx` is `None`: Creates a new position with the provided value
- If `position_idx` is `Some`: Updates the existing position with the new value

### Remove Liquidity

```move
public fun remove_liquidity(
    pool_signer: &signer,
    position_idx: u64,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>) {
    let value = deserialize_u64(stream);
    let pool_state = &mut PoolState[signer::address_of(pool_signer)];

    assert!(pool_state.positions.contains(&position_idx));
    let position = pool_state.positions.borrow_mut(&position_idx);
    assert!(position.value >= value);
    position.value -= value;

    let removed_position = none();
    if (position.value == 0) {
        pool_state.positions.remove(&position_idx);
        removed_position = some(position_idx);
    };

    (vector[value], removed_position)
}
```

Removes liquidity from a specific position in the pool.

**Parameters:**
- `pool_signer`: The signer for the pool account
- `position_idx`: Index of the position to remove liquidity from
- `stream`: BCS stream containing amount to remove
- `_sender`: Address of the liquidity provider

**Returns:**
- `vector<u64>`: Amount of assets removed from the pool
- `Option<u64>`: Position index if the position was completely removed

**Logic:**
- Validates that the position exists
- Ensures the position has sufficient liquidity
- Reduces the position value by the requested amount
- If position value becomes 0, removes the position entirely

### Swap
```move
public fun swap(
    _pool_signer: &signer, 
    _stream: &mut 0x1::bcs_stream::BCSStream, 
    _sender: address
): (bool, u64, u64)
```

Swaps assets within the pool. Currently a placeholder implementation.

**Parameters:**
- `_pool_signer`: The signer for the pool account
- `_stream`: BCS stream containing swap parameters
- `_sender`: Address of the swapper

**Returns:**
- `bool`: Success status
- `u64`: Amount in
- `u64`: Amount out

**Events:** Emits `Swapped` event

### Run Pool Operation
```move
public fun run_pool_op(
    _pool_signer: &signer, 
    _stream: &mut BCSStream
)
```

Executes pool-specific operations. Currently not implemented.

**Parameters:**
- `_pool_signer`: The signer for the pool account
- `_stream`: BCS stream containing operation parameters

**Error:** Aborts with `ENOT_IMPLEMENTED` error code

## Events

The module emits the following events:

- `Created`: When a new pool is created
- `Added`: When liquidity is added to a pool
- `Removed`: When liquidity is removed from a pool
- `Swapped`: When assets are swapped in a pool

## Error Codes

- `ENOT_IMPLEMENTED = 0`: Used when a function is not yet implemented

## Usage Examples

### Creating a Pool
```move
let assets = vector[coin_a_address, coin_b_address];
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

### Removing Liquidity
```move
let (amounts, removed_position) = remove_liquidity(pool_signer, position_idx, stream, sender);
```

## Notes

- This is a basic implementation and may need additional features for production use
- The swap function is currently a placeholder and needs proper implementation
- Position management is simplified and may need more sophisticated logic for real-world scenarios
- Error handling is minimal and should be enhanced for production deployment