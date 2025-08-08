# Vault Hook

A secure vault implementation for the Aptos blockchain leveraging the Tapp protocol. This module provides time-locked and insurance vault functionality with fee collection and multi-asset support.

## Overview

The Vault Hook module implements secure vault functionality with the following features:
- Time-locked vaults with configurable lock periods
- Insurance vaults for flexible asset storage
- Multi-asset support with fee collection
- Slot-based position management
- Secure asset storage under Tapp's vault infrastructure

## Structures

### Vault
```move
struct Vault<T> has key {
    supported_assets: vector<address>,     // List of supported asset addresses
    slots: OrderedMap<u64, T>,            // Map of slot ID to slot data
    slots_count: u64,                     // Total number of slots created
    fee: u64,                             // Fee rate for the vault
    fee_amounts: vector<u64>,             // Accumulated fees per asset
    creator: address                      // Vault creator address
}
```

### TimeLockedSlot
```move
struct TimeLockedSlot has key {
    amounts: vector<u64>,                 // Amount of each asset in the slot
    created_at: u64,                      // Slot creation timestamp
    lock_until: u64                       // Timestamp when slot becomes withdrawable
}
```

### InsuranceSlot
```move
struct InsuranceSlot has key {
    amounts: vector<u64>,                 // Amount of each asset in the slot
    created_at: u64                       // Slot creation timestamp
}
```

## Functions

### Create Pool
```move
public fun create_pool(
    pool_signer: &signer,
    assets: vector<address>,
    fee: u64,
    stream: &mut BCSStream,
    creator: address
)
```

Creates a new vault with specified type and configuration.

**Parameters:**
- `pool_signer`: The signer for the vault account
- `assets`: Vector of supported asset addresses
- `fee`: Fee rate for the vault (basis points)
- `stream`: BCS stream containing vault type and configuration
- `creator`: Address of the vault creator

**Logic:**
- Deserializes vault type from stream
- For time-locked vaults: deserializes lock duration
- Creates appropriate vault type with initialized state
- Sets up fee tracking for all supported assets

**Vault Types:**
- `T_TIMELOCKED_VAULT` (1): Time-locked vault with configurable lock period
- `T_INSURANCE_VAULT` (2): Insurance vault with immediate withdrawal capability

### Deposit
```move
public fun deposit(
    pool_signer: &signer,
    position_idx: Option<u64>,
    stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

Deposits assets into a vault slot.

**Parameters:**
- `pool_signer`: The signer for the vault account
- `position_idx`: Optional slot index (None for new slot, Some for existing)
- `stream`: BCS stream containing deposit parameters
- `_sender`: Address of the depositor

**Returns:**
- `vector<u64>`: Amount of each asset deposited
- `Option<u64>`: New slot index if a new slot was created

**Logic for Time-Locked Vaults:**
- If `position_idx` is `None`: Creates new slot with lock duration and amounts
- If `position_idx` is `Some`: Adds amounts to existing slot
- Sets creation timestamp and lock expiration

**Logic for Insurance Vaults:**
- If `position_idx` is `None`: Creates new slot with amounts
- If `position_idx` is `Some`: Adds amounts to existing slot
- Sets creation timestamp only

### Withdraw
```move
public fun withdraw(
    pool_signer: &signer,
    position_idx: u64,
    _stream: &mut BCSStream,
    _sender: address
): (vector<u64>, Option<u64>)
```

Withdraws assets from a vault slot.

**Parameters:**
- `pool_signer`: The signer for the vault account
- `position_idx`: Index of the slot to withdraw from
- `_stream`: BCS stream containing withdrawal parameters
- `_sender`: Address of the withdrawer

**Returns:**
- `vector<u64>`: Amount of each asset withdrawn (after fees)
- `Option<u64>`: Slot index of the removed slot

**Logic for Time-Locked Vaults:**
- Validates that slot exists
- Ensures current time is past lock expiration
- Calculates and deducts fees from withdrawal amounts
- Removes slot after withdrawal

**Logic for Insurance Vaults:**
- Validates that slot exists
- Calculates and deducts fees from withdrawal amounts
- Removes slot after withdrawal

### Collect Fee
```move
public fun collect_fee(
    pool_signer: &signer,
    recipient: address
): vector<u64>
```

Collects accumulated fees from the vault.

**Parameters:**
- `pool_signer`: The signer for the vault account
- `recipient`: Address to receive the collected fees

**Returns:**
- `vector<u64>`: Collected fee amounts for each asset

**Logic:**
- Retrieves accumulated fees for all assets
- Resets fee amounts to zero
- Transfers fees to recipient address

### Swap
```move
public fun swap(
    _pool_signer: &signer,
    _stream: &mut BCSStream,
    _sender: address
): vector<u64>
```

Swaps assets within the vault. Currently not implemented.

**Parameters:**
- `_pool_signer`: The signer for the vault account
- `_stream`: BCS stream containing swap parameters
- `_sender`: Address of the swapper

**Returns:**
- `vector<u64>`: Swap result amounts

**Error:** Aborts with `ENOT_IMPLEMENTED` error code

## Vault Types

### Time-Locked Vault
Time-locked vaults provide secure asset storage with a mandatory lock period:

1. **Lock Period**: Assets are locked for a specified duration
2. **Early Withdrawal Prevention**: Withdrawals are blocked until lock period expires
3. **Fee Collection**: Fees are collected on withdrawal
4. **Slot Management**: Each deposit creates or updates a slot with lock timing

### Insurance Vault
Insurance vaults provide flexible asset storage without lock periods:

1. **Immediate Withdrawal**: Assets can be withdrawn at any time
2. **Fee Collection**: Fees are collected on withdrawal
3. **Flexible Storage**: No time restrictions on asset storage
4. **Slot Management**: Each deposit creates or updates a slot

## Fee System

The vault implements a comprehensive fee collection mechanism:

1. **Fee Rate**: Configurable fee rate set during vault creation
2. **Fee Calculation**: Fees are calculated as `amount * fee_rate / FEE_DENOM`
3. **Fee Accumulation**: Fees are accumulated per asset in the vault
4. **Fee Collection**: Fees can be collected by the vault creator
5. **Fee Deduction**: Fees are automatically deducted during withdrawals

## Error Codes

- `EINVALID_VAULT_TYPE = 0`: Invalid vault type specified
- `ESLOT_NOT_FOUND = 1`: Specified slot does not exist
- `ESLOT_REDEEM_TOO_EARLY = 2`: Attempting to withdraw before lock period expires
- `ENOT_IMPLEMENTED = 3`: Function is not yet implemented

## Constants

- `T_TIMELOCKED_VAULT = 1`: Time-locked vault type identifier
- `T_INSURANCE_VAULT = 2`: Insurance vault type identifier
- `FEE_DENOM = 10000`: Fee denominator for basis point calculations

## Usage Examples

### Creating a Time-Locked Vault
```move
let assets = vector[coin_a_address, coin_b_address];
let fee = 300; // 3% fee
let lock_duration = 86400; // 24 hours in seconds
create_pool(pool_signer, assets, fee, stream, creator_address);
```

### Creating an Insurance Vault
```move
let assets = vector[coin_a_address, coin_b_address];
let fee = 100; // 1% fee
create_pool(pool_signer, assets, fee, stream, creator_address);
```

### Depositing to Time-Locked Vault
```move
// Create new slot
let (amounts, new_slot) = deposit(pool_signer, none(), stream, sender);

// Add to existing slot
let (amounts, _) = deposit(pool_signer, some(slot_idx), stream, sender);
```

### Withdrawing from Time-Locked Vault
```move
let (amounts, removed_slot) = withdraw(pool_signer, slot_idx, stream, sender);
```

### Collecting Fees
```move
let fees = collect_fee(pool_signer, recipient_address);
```

## Security Features

### Time-Locked Security
- **Mandatory Lock Period**: Assets cannot be withdrawn before lock expiration
- **Timestamp Validation**: Uses blockchain timestamp for accurate timing
- **Slot Isolation**: Each slot has independent lock timing

### Insurance Vault Security
- **Flexible Access**: Assets can be withdrawn at any time
- **Fee Protection**: Fees are collected to prevent abuse
- **Slot Management**: Proper slot tracking and cleanup

### General Security
- **Tapp Integration**: Assets are stored under Tapp's secured vault infrastructure
- **Fee Collection**: Automatic fee deduction prevents fee evasion
- **Slot Validation**: Proper slot existence and ownership validation

## Notes

- Time-locked vaults enforce mandatory lock periods for enhanced security
- Insurance vaults provide flexibility for immediate withdrawals
- Fees are automatically calculated and deducted during withdrawals
- All vault operations are secured through Tapp's infrastructure
- Slot management ensures proper asset tracking and cleanup
- Error handling should be enhanced for production deployment
