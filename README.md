
- [TAPP Protocol](#tapp-protocol)
  - [Introduction](#introduction)
  - [Architecture Overview](#architecture-overview)
  - [Core Components](#core-components)
    - [1. Router (`tapp::router`)](#1-router-tapprouter)
    - [2. Hook Factory (`tapp::hook_factory`)](#2-hook-factory-tapphook_factory)
    - [3. Position Management (`tapp::position`)](#3-position-management-tappposition)
  - [Hook Interface Specification](#hook-interface-specification)
  - [Data Flow and Integration](#data-flow-and-integration)
    - [1. Pool Creation Flow](#1-pool-creation-flow)
    - [2. Add Liquidity Flow](#2-add-liquidity-flow)
    - [3. Remove Liquidity Flow](#3-remove-liquidity-flow)
    - [4. Swap Flow](#4-swap-flow)
    - [5. Collect Fee Flow](#5-collect-fee-flow)
    - [6. Pool Operation Flow](#6-pool-operation-flow)
    - [7. Asset Management Flow](#7-asset-management-flow)
  - [Integration Checklist](#integration-checklist)
    - [Before Deployment](#before-deployment)
    - [After Deployment](#after-deployment)

# TAPP Protocol

## Introduction
The TAPP hook interface provides a powerful and flexible framework for implementing custom liquidity pool logic. By understanding the complete architecture - from router to hook implementation - developers can create robust, secure, and efficient pool implementations that integrate seamlessly with the TAPP protocol.

The modular design allows for:
- **Separation of Concerns**: Routing, asset management, and pool logic are separate
- **Flexibility**: Custom hook implementations for different use cases
- **Security**: Centralized access control and asset management
- **Scalability**: Easy addition of new hook types
- **Composability**: Hooks can be combined and extended

Follow this guide to implement your own custom hooks and contribute to the TAPP ecosystem! 

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│     Router      │───▶│  Hook Factory    │───▶│  Hook Module    │
│                 │    │                  │    │                 │
│ • Entry Point   │    │ • Route Calls    │    │ • Pool Logic    │
│ • Asset Mgmt    │    │ • Hook Registry  │    │ • State Mgmt    │
│ • Access Control│    │ • Tx Conversion  │    │ • Events        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Position      │    │   Pool Meta      │    │   Hook State    │
│   Management    │    │   Management     │    │   (Custom)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Core Components
The `tapp` folder is a minified version of Tapp EẼchange, it serves the purpose for integrating and testing your hook.

### 1. Router (`tapp::router`)

The router is the main entry point that handles all user interactions and manages the overall protocol state.

**Key Responsibilities:**
- Entry point for all pool operations
- Asset management and transfers
- Access control and permissions
- Event emission for protocol-level events
- Position NFT management

**Main Functions:**
```move
// Pool creation
public entry fun create_pool(sender: &signer, args: vector<u8>)

// Liquidity operations
public entry fun add_liquidity(sender: &signer, args: vector<u8>)
public entry fun remove_liquidity(sender: &signer, args: vector<u8>)

// Trading
public entry fun swap(sender: &signer, args: vector<u8>)

// Fee collection
public entry fun collect_fee(sender: &signer, args: vector<u8>)
```

### 2. Hook Factory (`tapp::hook_factory`)

The hook factory acts as a registry and router for different hook implementations.

**Key Responsibilities:**
- Hook type registration and routing
- Transaction conversion between router and hooks
- Pool metadata management
- Reserve tracking

**Hook Types:**
```move
const HOOK_BASIC: u8 = 1;      // Simple AMM
const HOOK_ADVANCED: u8 = 2;   // Advanced features
const HOOK_VAULT: u8 = 3;      // Vault implementation
const YOUR_HOOK: u8 = ... 
```

**Core Functions:**
```move
// Pool creation routing
public(package) fun create_pool(
    vault: &signer,
    creator: address,
    hook_type: u8,
    stream: &mut BCSStream
): ConstructorRef

// Operation routing
public(package) fun add_liquidity(...): (vector<Tx>, Option<u64>)
public(package) fun remove_liquidity(...): (vector<Tx>, Option<u64>)
public(package) fun swap(...): vector<Tx>
```

### 3. Position Management (`tapp::position`)

Manages NFT-based position tokens that represent liquidity provider shares.

**Key Features:**
- NFT-based position representation
- Position metadata storage
- Authorization and access control
- Position lifecycle management

## Hook Interface Specification
Every hook module must implement the following interface functions. Go to here: [./hooks/hook-guide.md](./hooks/hook-guide.md)


## Data Flow and Integration

### 1. Pool Creation Flow

```
User → Router::create_pool() → HookFactory::create_pool() → Hook::create_pool()
                                                           ↓
                                                      Pool State Creation
                                                           ↓
User ← Router::PoolCreated event ← HookFactory ← Hook::Created event
```

### 2. Add Liquidity Flow

```
User → Router::add_liquidity() → HookFactory::add_liquidity() → Hook::add_liquidity()
                                                              ↓
                                                        Asset Calculation
                                                              ↓
                                                      Position Management
                                                              ↓
User ← Router::(LiquidityAdded event and do_accounting) ← HookFactory (hook_factory::Tx) ← Hook::Added event
```

### 3. Remove Liquidity Flow

```
User → Router::remove_liquidity() → HookFactory::remove_liquidity() → Hook::remove_liquidity()
                                                                   ↓
                                                            Asset Calculation
                                                                   ↓
                                                          Position Management
                                                                   ↓
User ← Router::(LiquidityRemoved event and do_accounting) ← HookFactory (hook_factory::Tx) ← Hook::Removed event
```

### 4. Swap Flow

```
User → Router::swap() → HookFactory::swap() → Hook::swap()
                                              ↓
                                         Price Calculation
                                              ↓
                                         Asset Exchange
                                              ↓
User ← Router::(Swapped event and do_accounting) ← HookFactory (hook_factory::Tx) ← Hook::Swapped event
```

### 5. Collect Fee Flow

```
User → Router::collect_fee() → HookFactory::collect_fee() → Hook::collect_fee()
                                                           ↓
                                                      Fee Calculation
                                                           ↓
                                                      Asset Distribution
                                                           ↓
User ← Router::(FeeCollected event and do_accounting) ← HookFactory (hook_factory::Tx) ← Hook::CollectedFee event
```

### 6. Pool Operation Flow

```
User → Router::run_pool_op() → HookFactory::run_pool_op() → Hook::run_pool_op()
                                                           ↓
                                                      Custom Operations
                                                           ↓
                                                      State Updates
                                                           ↓
                                                      Event Emission
```

### 7. Asset Management Flow

```
Hook (asset accounting) → HookFactory (hook_factory::Tx) → Router::do_accounting() → Asset Transfers → PoolMeta reserve updates
```

## Integration Checklist

### Before Deployment
- [ ] Implement all required interface functions
- [ ] Add proper error handling and validation
- [ ] Emit appropriate events
- [ ] Write comprehensive tests
- [ ] Test with main protocol, events and state changes: `tapp/tests/your_hook_tests.move`
- [ ] Document BCS stream parameters
- [ ] Validate state management patterns

### After Deployment
- [ ] Register hook with TAPP factory
- [ ] Test with main protocol
- [ ] Monitor events and state changes
- [ ] Verify asset accounting
- [ ] Test position management
