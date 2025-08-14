
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
    - [3. Asset Management Flow](#3-asset-management-flow)
  - [Submission](#submission)
    - [Checklists Before Submission](#checklists-before-submission)
    - [Submission Process](#submission-process)
    - [TestNet Testing](#testnet-testing)

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

**Supported Hook Types:**
```move
const HOOK_BASIC: u8 = 1;      // Simple AMM
const HOOK_ADVANCED: u8 = 2;   // Advanced features
const HOOK_VAULT: u8 = 1;      // Vault implementations
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
User ← Router::PoolCreated event ← HookFactory ← Hook::Created event
```

### 2. Add Liquidity Flow

```
User → Router::add_liquidity() → HookFactory::add_liquidity() → Hook::add_liquidity()
                                                              ↓
User ← Router::LiquidityAdded event ← HookFactory ← Hook::Added event
```

### 3. Asset Management Flow

```
Router::do_accounting() → Asset Transfers → Reserve Updates → Hook State Updates
```

## Submission

### Checklists Before Submission

- [ ] 1. Implement all required interface functions
- [ ] 2. Add proper error handling and validation
- [ ] 3. Emit appropriate events
- [ ] 4. Write comprehensive tests
- [ ] 5. Test with main protocol, events and state changes: `tapp/tests/your_hook_tests.move`
- [ ] 6. Document BCS stream parameters
- [ ] 7. Validate state management patterns

### Submission Process

1. Submit a PR to this repository.
2. Double-check the checklists in the PR and ensure you provide all information requested in the PR.
3. Our team will monitor all PRs and review them ASAP. If you have any questions or concerns, reach us at [discord](https://discord.com/invite/UXGWaaNNr2)

### TestNet Testing

When the submission is ready, we'll schedule **TestNet** testing together. These checklists are for reference purposes and may change on a case-by-case basis depending on the project:

1. Register hook with TAPP factory
2. Test with main protocol
3. Monitor events and state changes
4. Verify asset accounting
5. Test position management

We will contact you directly to schedule the next steps.

