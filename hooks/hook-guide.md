# Hook Interface Specification

- [Hook Interface Specification](#hook-interface-specification)
  - [Hook Interfaces](#hook-interfaces)
    - [`create_pool`](#create_pool)
    - [`add_liquidity`](#add_liquidity)
    - [`remove_liquidity` / `withdraw`](#remove_liquidity--withdraw)
      - [Basic Hook](#basic-hook)
      - [Advanced Hook](#advanced-hook)
      - [Vault Hook](#vault-hook)
    - [`swap`](#swap)
      - [Basic Hook](#basic-hook-1)
      - [Advanced Hook](#advanced-hook-1)
      - [Vault Hook](#vault-hook-1)
    - [`collect_fee` (Optional)](#collect_fee-optional)
      - [Basic Hook](#basic-hook-2)
      - [Advanced Hook](#advanced-hook-2)
      - [Vault Hook](#vault-hook-2)
    - [`run_pool_op` (Optional)](#run_pool_op-optional)
  - [State Management Patterns](#state-management-patterns)
    - [Basic Hook State](#basic-hook-state)
    - [Vault Hook State](#vault-hook-state)
    - [Advanced Hook State](#advanced-hook-state)
  - [Event Emission](#event-emission)
  - [Testing Your Hook](#testing-your-hook)
    - [Unit Test Structure](#unit-test-structure)


## Hook Interfaces
Every hook module must implement the following interface functions

### `create_pool`

**Purpose:** Initialize a new pool with the specified configuration.

**Signature:**

```move
public fun create_pool(
    pool_signer: &signer,
    assets: vector<address>,
    fee: u64,
    sender: address
)
```

**Parameters:**

- `pool_signer`: Signer for the pool account (provided by TAPP)
- `assets`: Vector of supported asset addresses
- `fee`: Fee rate in basis points (e.g., 3000 = 0.3%)
- `sender`: Address of the pool creator

**Implementation Requirements:**

- Must use `move_to(pool_signer, ...)` to store pool state
- Should emit appropriate events
- Can include additional parameters via BCS stream

Examples:
- [../basic/README.md](./basic/README.md)
- [../advanced/README.md](./advanced/README.md)
- [../vault/README.md](./vault/README.md)

### `add_liquidity`

**Purpose:** Add liquidity to the pool, creating or updating positions.

**Signature:**

```move
public fun add_liquidity(
    pool_signer: &signer,
    position_idx: Option<u64>,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

**Parameters:**

- `pool_signer`: Pool account signer
- `position_idx`: Optional position index (None for new, Some for existing)
- `stream`: BCS stream with liquidity parameters
- `_sender`: Liquidity provider address

**Return Values:**

- `vector<u64>`: Amounts of each asset added to pool
- `Option<u64>`: New position index if created, None otherwise

Examples:
- [../basic/README.md](./basic/README.md)
- [../advanced/README.md](./advanced/README.md)
- [../vault/README.md](./vault/README.md)

### `remove_liquidity` / `withdraw`

**Purpose:** Remove liquidity from a specific position or withdraw assets from a vault slot.

**Signatures by Hook Type:**

#### Basic Hook
```move
public fun remove_liquidity(
    pool_signer: &signer,
    position_idx: u64,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

**Return Values:**
- `vector<u64>`: Amounts of each asset removed from pool
- `Option<u64>`: Position index if completely removed, None otherwise

#### Advanced Hook
```move
public fun remove_liquidity(
    pool_signer: &signer,
    position_idx: u64,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>, vector<CampaignReward>)
```

**Return Values:**
- `vector<u64>`: Amounts of each asset removed from pool
- `Option<u64>`: Position index if completely removed, None otherwise
- `vector<CampaignReward>`: Collected campaign rewards for the position

#### Vault Hook
```move
public fun withdraw(
    pool_signer: &signer,
    position_idx: u64,
    _stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

**Return Values:**
- `vector<u64>`: Amounts of each asset withdrawn (after fees)
- `Option<u64>`: Slot index of the removed slot

**Parameters:**

- `pool_signer`: Pool account signer
- `position_idx`: Position/slot index to remove from
- `stream`: BCS stream with removal parameters
- `_sender`: Liquidity provider/withdrawer address

**Key Differences:**

1. **Basic Hook**: Simple removal with position tracking
2. **Advanced Hook**: Includes campaign reward collection
3. **Vault Hook**: 
   - Function name is `withdraw` instead of `remove_liquidity`
   - Includes fee deduction
   - Has time-lock validation for time-locked vaults
   - Always removes the slot after withdrawal

Examples:
- [../basic/README.md](./basic/README.md)
- [../advanced/README.md](./advanced/README.md)
- [../vault/README.md](./vault/README.md)

### `swap`

**Purpose:** Execute asset swaps within the pool.

**Signatures by Hook Type:**

#### Basic Hook
```move
public fun swap(
    _pool_signer: &signer,
    _stream: &mut BCSStream,
    _sender: address
): (bool, u64, u64)
```

**Return Values:**
- `bool`: Whether it was an A to B swap (true) or B to A swap (false)
- `u64`: Amount in
- `u64`: Amount out

**Logic:**
- Deserializes swap direction (a2b), amount_in, and amount_out
- Currently a placeholder implementation

#### Advanced Hook
```move
public fun swap(
    pool_signer: &signer,
    _stream: &mut BCSStream,
    _sender: address
): (u64, u64, u64, u64)
```

**Return Values:**
- `u64`: Asset in index
- `u64`: Asset out index
- `u64`: Amount in
- `u64`: Amount out

**Logic:**
- Deserializes asset indices and amounts
- Distributes campaign rewards to all positions during swap
- Calculates rewards based on time elapsed and distribution rate
- Updates campaign state and position rewards

#### Vault Hook
```move
public fun swap(
    _pool_signer: &signer,
    _stream: &mut BCSStream,
    _sender: address
): vector<u64>
```

**Return Values:**
- `vector<u64>`: Swap result amounts

**Logic:**
- Currently not implemented
- Aborts with `ENOT_IMPLEMENTED` error

**Parameters:**

- `pool_signer`: Pool account signer
- `stream`: BCS stream with swap parameters
- `_sender`: Swapper address

**Key Differences:**

1. **Basic Hook**: 
   - Returns swap direction as boolean
   - Simple placeholder implementation
   - Focuses on basic swap functionality

2. **Advanced Hook**: 
   - Returns asset indices and amounts
   - Includes campaign reward distribution
   - Sophisticated reward calculation and distribution

3. **Vault Hook**: 
   - Returns vector of amounts
   - Currently not implemented
   - Designed for vault-specific swap logic

Examples:
- [../basic/README.md](./basic/README.md)
- [../advanced/README.md](./advanced/README.md)
- [../vault/README.md](./vault/README.md)

### `collect_fee` (Optional)

**Purpose:** Collect accumulated fees from the pool or vault.

**Signatures by Hook Type:**

#### Basic Hook
```move
// Not implemented - Basic hook does not have collect_fee function
```

**Logic:**
- Basic hook does not implement fee collection functionality

#### Advanced Hook
```move
public fun collect_fee(
    pool_signer: &signer,
    position_idx: u64,
    _creator: address
): vector<u64>
```

**Return Values:**
- `vector<u64>`: Collected fee amounts for each asset

**Logic:**
- Collects fees from a specific position
- Resets position fees to zero after collection
- Emits `CollectedFee` event

#### Vault Hook
```move
public fun collect_fee(
    pool_signer: &signer,
    recipient: address
): vector<u64>
```

**Return Values:**
- `vector<u64>`: Collected fee amounts for each asset

**Logic:**
- Collects fees from the entire vault (all slots)
- Resets vault fee amounts to zero after collection
- Transfers fees to recipient address
- Works for both time-locked and insurance vaults

**Parameters:**

- `pool_signer`: Pool account signer
- `position_idx`: Position index (Advanced Hook only)
- `recipient`: Address to receive fees (Vault Hook only)
- `_creator`: Fee collector address (Advanced Hook only)

**Key Differences:**

1. **Basic Hook**: 
   - Does not implement fee collection
   - No fee tracking functionality

2. **Advanced Hook**: 
   - Collects fees from specific positions
   - Position-based fee collection
   - Resets position fees after collection

3. **Vault Hook**: 
   - Collects fees from entire vault
   - Vault-wide fee collection
   - Transfers fees to recipient address
   - Works across all vault types

Examples:
- [../advanced/README.md](./advanced/README.md)
- [../vault/README.md](./vault/README.md)

### `run_pool_op` (Optional)

**Purpose:** Execute pool-specific operations.

**Signatures by Hook Type:**

#### Basic Hook
```move
// Not implemented - Basic hook does not have run_pool_op function
```

**Logic:**
- Basic hook does not implement custom pool operations

#### Advanced Hook
```move
public fun run_pool_op(
    pool_signer: &signer,
    _stream: &mut BCSStream
)
```

**Return Values:**
- No return value (void function)

**Logic:**
- Deserializes operation code from stream
- Routes to appropriate operation handler:
  - `OP_DO_STH` (0): Executes `do_sth` function
  - `OP_DO_OTHER` (1): Executes `do_other` function
- Aborts with `ENOT_IMPLEMENTED` for unknown operations
- Includes helper functions `do_sth` and `do_other` for custom logic

#### Vault Hook
```move
// Not implemented - Vault hook does not have run_pool_op function
```

**Logic:**
- Vault hook does not implement custom pool operations

**Parameters:**

- `pool_signer`: Pool account signer
- `_stream`: BCS stream containing operation parameters

**Key Differences:**

1. **Basic Hook**: 
   - Does not implement custom pool operations
   - No extensible operation framework

2. **Advanced Hook**: 
   - Implements extensible operation framework
   - Supports custom operation codes
   - Includes helper functions for custom logic
   - Provides operation routing based on op_code

3. **Vault Hook**: 
   - Does not implement custom pool operations
   - Focuses on vault-specific functionality

**Operation Codes (Advanced Hook):**
- `OP_DO_STH = 0`: Custom operation 1
- `OP_DO_OTHER = 1`: Custom operation 2

Examples:
- [../advanced/README.md](./advanced/README.md)

## State Management Patterns

### Basic Hook State

```move
struct PoolState has key {
    state: u64,
    positions: OrderedMap<u64, Position>,
    positions_count: u64,
}

struct Position has key {
    value: u64,
}
```

### Vault Hook State

```move
struct Vault<T> has key {
    supported_assets: vector<address>,
    slots: OrderedMap<u64, T>,
    slots_count: u64,
    fee: u64,
    fee_amounts: vector<u64>,
    creator: address
}

struct TimeLockedSlot has key {
    amounts: vector<u64>,
    created_at: u64,
    lock_until: u64
}

struct InsuranceSlot has key {
    amounts: vector<u64>,
    created_at: u64
}
```

### Advanced Hook State

```move
struct PoolState has key {
    state: u64,
    positions: OrderedMap<u64, Position>,
    positions_count: u64,
}

struct Position has key {
    value: u64,
}

struct CampaignReward has copy, drop, store {
    token: address,
    amount: u64
}
```

## Event Emission

```move
#[event]
struct Created has drop, store {}

#[event]
struct Added has drop, store {}

#[event]
struct Removed has drop, store {}

#[event]
struct Swapped has drop, store {}
```

## Testing Your Hook

### Unit Test Structure

```move
#[test_only]
module basic::basic_tests {
    use basic::basic;
    use tapp::router;

    #[test]
    fun test_create_pool() {
        // Test pool creation
    }

    #[test]
    fun test_add_liquidity() {
        // Test liquidity addition
    }

    #[test]
    fun test_remove_liquidity() {
        // Test liquidity removal
    }

    #[test]
    fun test_swap() {
        // Test swapping
    }
}
```
