/**
 * @title Tapp.Exchange Prediction Market Hook
 * @author edsphinx (VeriFi Protocol)
 * @notice A custom Tapp.Exchange hook that enables AMM-based trading for prediction market outcomes.
 * @dev This hook implements the full Tapp hook interface to provide CPMM swaps for YES/NO tokens
 * from VeriFi Protocol markets. It features dynamic fees, automatic trading disablement after
 * market resolution, and seamless integration with Tapp Points rewards system.
 */
module VeriFiPublisher::tapp_prediction_hook {

    // === Imports ===
    use std::bcs::to_bytes;
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use aptos_std::bcs_stream::{Self, BCSStream};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::ordered_map::{Self, OrderedMap};
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_std::math64;
    use VeriFiPublisher::verifi_protocol::{Self, Market};

    // === Friends ===
    // Tapp protocol will call these functions

    // === Errors ===
    const E_INVALID_ASSETS: u64 = 1;
    const E_TRADING_DISABLED: u64 = 2;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 3;
    const E_SLIPPAGE_EXCEEDED: u64 = 4;
    const E_POSITION_NOT_FOUND: u64 = 5;
    const E_INVALID_AMOUNTS: u64 = 6;
    const E_ZERO_LIQUIDITY: u64 = 7;
    const E_MARKET_NOT_FOUND: u64 = 8;
    const E_INSUFFICIENT_RESERVES: u64 = 9;

    // === Constants ===
    const FEE_DENOMINATOR: u64 = 10000; // Basis points: 10000 = 100%
    const BASE_FEE: u64 = 30;           // 0.30% normal trading fee
    const VOLATILITY_FEE: u64 = 50;     // 0.50% fee near resolution (high volatility)
    const VOLATILITY_WINDOW: u64 = 3600; // 1 hour before resolution = high volatility
    const MINIMUM_LIQUIDITY: u64 = 1000; // Minimum liquidity to prevent division by zero

    // === Events ===

    #[event]
    struct PoolCreated has drop, store {
        pool_address: address,
        market_address: address,
        yes_token: address,
        no_token: address,
        creator: address,
        timestamp: u64,
    }

    #[event]
    struct LiquidityAdded has drop, store {
        pool_address: address,
        provider: address,
        position_idx: u64,
        yes_amount: u64,
        no_amount: u64,
        liquidity_tokens: u64,
        timestamp: u64,
    }

    #[event]
    struct LiquidityRemoved has drop, store {
        pool_address: address,
        provider: address,
        position_idx: u64,
        yes_amount: u64,
        no_amount: u64,
        liquidity_tokens: u64,
        timestamp: u64,
    }

    #[event]
    struct Swapped has drop, store {
        pool_address: address,
        trader: address,
        yes_to_no: bool,
        amount_in: u64,
        amount_out: u64,
        fee: u64,
        timestamp: u64,
    }

    #[event]
    struct FeeCollected has drop, store {
        pool_address: address,
        recipient: address,
        yes_fee: u64,
        no_fee: u64,
        timestamp: u64,
    }

    #[event]
    struct TradingStatusChanged has drop, store {
        pool_address: address,
        is_enabled: bool,
        reason: vector<u8>,
        timestamp: u64,
    }

    // === Data Structures ===

    /**
     * @dev Main pool state stored at the pool's object address.
     * Links to a VeriFi market and manages YES/NO token liquidity.
     */
    struct PredictionPoolState has key {
        // Link to VeriFi market
        market_object: Object<Market>,
        yes_token_metadata: Object<Metadata>,
        no_token_metadata: Object<Metadata>,

        // CPMM reserves
        reserve_yes: u64,
        reserve_no: u64,

        // Position tracking (Tapp NFT-based)
        positions: OrderedMap<u64, LiquidityPosition>,
        positions_count: u64,

        // Fee configuration
        base_fee: u64,
        volatility_fee: u64,
        fee_yes: u64,
        fee_no: u64,

        // Trading status
        is_trading_enabled: bool,
        last_status_check: u64,

        // Events
        pool_created_events: EventHandle<PoolCreated>,
        liquidity_added_events: EventHandle<LiquidityAdded>,
        liquidity_removed_events: EventHandle<LiquidityRemoved>,
        swapped_events: EventHandle<Swapped>,
        fee_collected_events: EventHandle<FeeCollected>,
        trading_status_events: EventHandle<TradingStatusChanged>,
    }

    /**
     * @dev Represents a liquidity provider's position in the pool.
     * Tracks amounts deposited and liquidity tokens earned.
     */
    struct LiquidityPosition has copy, drop, store {
        yes_amount: u64,
        no_amount: u64,
        liquidity_tokens: u64,
        entry_timestamp: u64,
    }

    // === Hook Interface Implementation ===

    /**
     * @notice Generates a deterministic seed for pool address creation.
     * @dev Required by Tapp protocol for predictable pool addresses.
     * @param assets Vector containing [YES_token, NO_token] addresses
     * @param fee Fee rate in basis points
     * @return Unique seed for this pool configuration
     */
    public fun pool_seed(assets: vector<address>, fee: u64): vector<u8> {
        let seed = vector[];
        seed.append(to_bytes(&assets));
        seed.append(to_bytes(&fee));
        seed.append(b"verifi_prediction_market_v1");
        seed
    }

    /**
     * @notice Creates a new prediction market liquidity pool.
     * @dev Validates that assets are YES/NO tokens from a valid VeriFi market.
     * Initializes pool state with empty reserves and position tracking.
     * @param pool_signer Signer capability for the pool object
     * @param assets Vector of [YES_token, NO_token] addresses
     * @param fee Fee rate in basis points (not used, defaults to dynamic fees)
     * @param sender Address of the pool creator
     */
    public fun create_pool(
        pool_signer: &signer,
        assets: vector<address>,
        _fee: u64, // Not used, dynamic fees calculated internally
        sender: address
    ) acquires PredictionPoolState {
        // Validate inputs
        assert!(vector::length(&assets) == 2, E_INVALID_ASSETS);

        let yes_token_addr = *vector::borrow(&assets, 0);
        let no_token_addr = *vector::borrow(&assets, 1);

        // Find the VeriFi market that owns these tokens
        let (market_object, yes_metadata, no_metadata) =
            find_market_from_tokens(yes_token_addr, no_token_addr);

        let pool_address = signer::address_of(pool_signer);

        // Initialize pool state
        move_to(pool_signer, PredictionPoolState {
            market_object,
            yes_token_metadata: yes_metadata,
            no_token_metadata: no_metadata,
            reserve_yes: 0,
            reserve_no: 0,
            positions: ordered_map::new(),
            positions_count: 0,
            base_fee: BASE_FEE,
            volatility_fee: VOLATILITY_FEE,
            fee_yes: 0,
            fee_no: 0,
            is_trading_enabled: true,
            last_status_check: timestamp::now_seconds(),
            pool_created_events: object::new_event_handle(pool_signer),
            liquidity_added_events: object::new_event_handle(pool_signer),
            liquidity_removed_events: object::new_event_handle(pool_signer),
            swapped_events: object::new_event_handle(pool_signer),
            fee_collected_events: object::new_event_handle(pool_signer),
            trading_status_events: object::new_event_handle(pool_signer),
        });

        // Emit creation event
        let pool_state = borrow_global_mut<PredictionPoolState>(pool_address);
        event::emit_event(
            &mut pool_state.pool_created_events,
            PoolCreated {
                pool_address,
                market_address: object::object_address(&market_object),
                yes_token: yes_token_addr,
                no_token: no_token_addr,
                creator: sender,
                timestamp: timestamp::now_seconds(),
            }
        );
    }

    /**
     * @notice Adds liquidity to the pool.
     * @dev Implements the Tapp add_liquidity interface. Calculates liquidity tokens
     * as the geometric mean of deposited amounts. Creates or updates a position NFT.
     * @param pool_signer Signer capability for the pool
     * @param position_idx Optional existing position to add to
     * @param stream BCS stream containing [yes_amount, no_amount]
     * @param sender Address providing liquidity
     * @return (amounts_to_deposit, position_nft_to_mint)
     */
    public fun add_liquidity(
        pool_signer: &signer,
        position_idx: Option<u64>,
        stream: &mut BCSStream,
        sender: address
    ): (vector<u64>, Option<u64>) acquires PredictionPoolState {
        let pool_address = signer::address_of(pool_signer);
        let pool_state = borrow_global_mut<PredictionPoolState>(pool_address);

        // Check trading status
        update_trading_status(pool_state);
        assert!(pool_state.is_trading_enabled, E_TRADING_DISABLED);

        // Deserialize amounts
        let yes_amount = bcs_stream::deserialize_u64(stream);
        let no_amount = bcs_stream::deserialize_u64(stream);

        assert!(yes_amount > 0 && no_amount > 0, E_INVALID_AMOUNTS);

        // Calculate liquidity tokens (geometric mean: sqrt(x * y))
        let liquidity = math64::sqrt(yes_amount * no_amount);
        assert!(liquidity >= MINIMUM_LIQUIDITY, E_ZERO_LIQUIDITY);

        // Update reserves
        pool_state.reserve_yes = pool_state.reserve_yes + yes_amount;
        pool_state.reserve_no = pool_state.reserve_no + no_amount;

        // Create or update position
        let mint_position = option::none();
        let actual_position_idx: u64;

        if (option::is_none(&position_idx)) {
            // Create new position
            actual_position_idx = pool_state.positions_count;
            ordered_map::add(
                &mut pool_state.positions,
                actual_position_idx,
                LiquidityPosition {
                    yes_amount,
                    no_amount,
                    liquidity_tokens: liquidity,
                    entry_timestamp: timestamp::now_seconds(),
                }
            );
            pool_state.positions_count = pool_state.positions_count + 1;
            mint_position = option::some(actual_position_idx);
        } else {
            // Update existing position
            actual_position_idx = option::destroy_some(position_idx);
            let position = ordered_map::borrow_mut(&mut pool_state.positions, &actual_position_idx);
            position.yes_amount = position.yes_amount + yes_amount;
            position.no_amount = position.no_amount + no_amount;
            position.liquidity_tokens = position.liquidity_tokens + liquidity;
        };

        // Emit event
        event::emit_event(
            &mut pool_state.liquidity_added_events,
            LiquidityAdded {
                pool_address,
                provider: sender,
                position_idx: actual_position_idx,
                yes_amount,
                no_amount,
                liquidity_tokens: liquidity,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Return amounts to deposit and position NFT to mint
        (vector[yes_amount, no_amount], mint_position)
    }

    /**
     * @notice Removes liquidity from the pool.
     * @dev Implements the Tapp remove_liquidity interface. Burns liquidity tokens
     * and returns proportional amounts of YES/NO tokens.
     * @param pool_signer Signer capability for the pool
     * @param position_idx Position NFT index to withdraw from
     * @param stream BCS stream containing [liquidity_tokens_to_burn]
     * @param sender Address removing liquidity
     * @return (amounts_to_withdraw, position_nft_to_burn)
     */
    public fun remove_liquidity(
        pool_signer: &signer,
        position_idx: u64,
        stream: &mut BCSStream,
        sender: address
    ): (vector<u64>, Option<u64>) acquires PredictionPoolState {
        let pool_address = signer::address_of(pool_signer);
        let pool_state = borrow_global_mut<PredictionPoolState>(pool_address);

        // Deserialize withdrawal amount
        let liquidity_to_burn = bcs_stream::deserialize_u64(stream);

        // Get position
        assert!(ordered_map::contains(&pool_state.positions, &position_idx), E_POSITION_NOT_FOUND);
        let position = ordered_map::borrow_mut(&mut pool_state.positions, &position_idx);

        assert!(position.liquidity_tokens >= liquidity_to_burn, E_INSUFFICIENT_LIQUIDITY);

        // Calculate total liquidity (geometric mean of reserves)
        let total_liquidity = math64::sqrt(pool_state.reserve_yes * pool_state.reserve_no);
        assert!(total_liquidity > 0, E_ZERO_LIQUIDITY);

        // Calculate proportional withdrawal amounts
        let yes_out = (pool_state.reserve_yes * liquidity_to_burn) / total_liquidity;
        let no_out = (pool_state.reserve_no * liquidity_to_burn) / total_liquidity;

        assert!(yes_out > 0 && no_out > 0, E_INSUFFICIENT_RESERVES);

        // Update reserves
        pool_state.reserve_yes = pool_state.reserve_yes - yes_out;
        pool_state.reserve_no = pool_state.reserve_no - no_out;

        // Update position
        position.yes_amount = position.yes_amount - yes_out;
        position.no_amount = position.no_amount - no_out;
        position.liquidity_tokens = position.liquidity_tokens - liquidity_to_burn;

        // Determine if position should be burned
        let burn_position = option::none();
        if (position.liquidity_tokens == 0) {
            ordered_map::remove(&mut pool_state.positions, &position_idx);
            burn_position = option::some(position_idx);
        };

        // Emit event
        event::emit_event(
            &mut pool_state.liquidity_removed_events,
            LiquidityRemoved {
                pool_address,
                provider: sender,
                position_idx,
                yes_amount: yes_out,
                no_amount: no_out,
                liquidity_tokens: liquidity_to_burn,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Return withdrawal amounts and position to burn
        (vector[yes_out, no_out], burn_position)
    }

    /**
     * @notice Executes a swap between YES and NO tokens using CPMM.
     * @dev Implements the Tapp swap interface. Uses constant product formula (x * y = k)
     * with dynamic fees based on market status. Includes slippage protection.
     * @param pool_signer Signer capability for the pool
     * @param stream BCS stream containing [amount_in, yes_to_no, min_amount_out]
     * @param sender Address executing the swap
     * @return (zero_for_one, amount_in, amount_out) - Tapp protocol format
     */
    public fun swap(
        pool_signer: &signer,
        stream: &mut BCSStream,
        sender: address
    ): (bool, u64, u64) acquires PredictionPoolState {
        let pool_address = signer::address_of(pool_signer);
        let pool_state = borrow_global_mut<PredictionPoolState>(pool_address);

        // Check trading status
        update_trading_status(pool_state);
        assert!(pool_state.is_trading_enabled, E_TRADING_DISABLED);

        // Deserialize swap parameters
        let amount_in = bcs_stream::deserialize_u64(stream);
        let yes_to_no = bcs_stream::deserialize_bool(stream);
        let min_amount_out = bcs_stream::deserialize_u64(stream);

        assert!(amount_in > 0, E_INVALID_AMOUNTS);

        // Calculate dynamic fee based on market status
        let effective_fee = calculate_dynamic_fee(pool_state);

        // Calculate fee and net input amount
        let fee_amount = (amount_in * effective_fee) / FEE_DENOMINATOR;
        let amount_in_after_fee = amount_in - fee_amount;

        // CPMM formula: amount_out = (reserve_out * amount_in_after_fee) / (reserve_in + amount_in_after_fee)
        let (reserve_in, reserve_out) = if (yes_to_no) {
            (pool_state.reserve_yes, pool_state.reserve_no)
        } else {
            (pool_state.reserve_no, pool_state.reserve_yes)
        };

        let amount_out = (reserve_out * amount_in_after_fee) / (reserve_in + amount_in_after_fee);

        // Slippage protection
        assert!(amount_out >= min_amount_out, E_SLIPPAGE_EXCEEDED);
        assert!(amount_out < reserve_out, E_INSUFFICIENT_RESERVES);

        // Update reserves and fees
        if (yes_to_no) {
            pool_state.reserve_yes = pool_state.reserve_yes + amount_in_after_fee;
            pool_state.reserve_no = pool_state.reserve_no - amount_out;
            pool_state.fee_yes = pool_state.fee_yes + fee_amount;
        } else {
            pool_state.reserve_no = pool_state.reserve_no + amount_in_after_fee;
            pool_state.reserve_yes = pool_state.reserve_yes - amount_out;
            pool_state.fee_no = pool_state.fee_no + fee_amount;
        };

        // Emit event
        event::emit_event(
            &mut pool_state.swapped_events,
            Swapped {
                pool_address,
                trader: sender,
                yes_to_no,
                amount_in,
                amount_out,
                fee: fee_amount,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Return in Tapp protocol format
        (yes_to_no, amount_in, amount_out)
    }

    /**
     * @notice Collects accumulated trading fees.
     * @dev Implements the Tapp collect_fee interface. Returns accumulated fees
     * and resets the fee counters.
     * @param pool_signer Signer capability for the pool
     * @param recipient Address to receive the fees
     * @return Vector of fee amounts [yes_fee, no_fee]
     */
    public fun collect_fee(
        pool_signer: &signer,
        recipient: address
    ): vector<u64> acquires PredictionPoolState {
        let pool_address = signer::address_of(pool_signer);
        let pool_state = borrow_global_mut<PredictionPoolState>(pool_address);

        let fees = vector[pool_state.fee_yes, pool_state.fee_no];

        // Emit event
        event::emit_event(
            &mut pool_state.fee_collected_events,
            FeeCollected {
                pool_address,
                recipient,
                yes_fee: pool_state.fee_yes,
                no_fee: pool_state.fee_no,
                timestamp: timestamp::now_seconds(),
            }
        );

        // Reset fee counters
        pool_state.fee_yes = 0;
        pool_state.fee_no = 0;

        fees
    }

    // === Helper Functions ===

    /**
     * @dev Finds the VeriFi market that owns the given YES/NO tokens.
     * @param token0_addr Address of the first token (could be YES or NO)
     * @param token1_addr Address of the second token (could be NO or YES)
     * @return (market_object, yes_metadata, no_metadata)
     */
    fun find_market_from_tokens(
        token0_addr: address,
        token1_addr: address
    ): (Object<Market>, Object<Metadata>, Object<Metadata>) {
        // Query all market addresses from VeriFi protocol factory
        let market_addresses = verifi_protocol::get_all_market_addresses();
        let len = vector::length(&market_addresses);
        let i = 0;

        while (i < len) {
            let market_addr = *vector::borrow(&market_addresses, i);
            let market_obj = object::address_to_object<Market>(market_addr);
            let (yes_meta, no_meta) = verifi_protocol::get_market_tokens(market_obj);

            let yes_addr = object::object_address(&yes_meta);
            let no_addr = object::object_address(&no_meta);

            // Tapp sorts tokens by address during pool creation (hook_factory::sort_check_assets)
            // so token0 < token1 is guaranteed. Check both possible orderings:
            // Case 1: YES < NO (YES is token0, NO is token1)
            // Case 2: NO < YES (NO is token0, YES is token1)
            if ((yes_addr == token0_addr && no_addr == token1_addr) ||
                (yes_addr == token1_addr && no_addr == token0_addr)) {
                return (market_obj, yes_meta, no_meta)
            };

            i = i + 1;
        };

        abort E_MARKET_NOT_FOUND
    }

    /**
     * @dev Calculates dynamic fee based on market status and time to resolution.
     * @param pool_state Reference to the pool state
     * @return Fee in basis points
     */
    fun calculate_dynamic_fee(pool_state: &PredictionPoolState): u64 {
        let market_status = verifi_protocol::get_market_status(pool_state.market_object);

        // If market is resolved, return maximum fee (trading should be disabled)
        if (market_status == 2 || market_status == 3) { // STATUS_RESOLVED_YES || STATUS_RESOLVED_NO
            return FEE_DENOMINATOR // 100% = trading disabled
        };

        // Get resolution timestamp
        let resolution_timestamp = verifi_protocol::get_resolution_timestamp(pool_state.market_object);
        let current_time = timestamp::now_seconds();

        // If past resolution time, return maximum fee
        if (current_time >= resolution_timestamp) {
            return FEE_DENOMINATOR
        };

        let time_remaining = resolution_timestamp - current_time;

        // Dynamic fee schedule:
        // > 1 hour to resolution: base_fee (0.3%)
        // < 1 hour to resolution: volatility_fee (0.5%)
        if (time_remaining < VOLATILITY_WINDOW) {
            pool_state.volatility_fee
        } else {
            pool_state.base_fee
        }
    }

    /**
     * @dev Updates trading status based on market resolution state.
     * @param pool_state Mutable reference to pool state
     */
    fun update_trading_status(pool_state: &mut PredictionPoolState) {
        let market_status = verifi_protocol::get_market_status(pool_state.market_object);
        let current_time = timestamp::now_seconds();

        let was_enabled = pool_state.is_trading_enabled;

        // Disable trading if market is resolved
        let (is_enabled, reason) = if (market_status == 2 || market_status == 3) { // STATUS_RESOLVED_YES || STATUS_RESOLVED_NO
            (false, b"Market resolved")
        } else {
            (true, b"Market open")
        };

        pool_state.is_trading_enabled = is_enabled;

        // Emit event if status changed
        if (was_enabled != pool_state.is_trading_enabled) {
            event::emit_event(
                &mut pool_state.trading_status_events,
                TradingStatusChanged {
                    pool_address: object::object_address(&pool_state.market_object),
                    is_enabled: pool_state.is_trading_enabled,
                    reason,
                    timestamp: current_time,
                }
            );
        };

        pool_state.last_status_check = current_time;
    }

    // === View Functions ===

    #[view]
    /**
     * @notice Gets the current pool reserves.
     * @param pool_address Address of the pool
     * @return (reserve_yes, reserve_no)
     */
    public fun get_reserves(pool_address: address): (u64, u64) acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);
        (pool_state.reserve_yes, pool_state.reserve_no)
    }

    #[view]
    /**
     * @notice Calculates the output amount for a given swap.
     * @param pool_address Address of the pool
     * @param amount_in Input amount
     * @param yes_to_no Direction of swap
     * @return Expected output amount (after fees)
     */
    public fun calculate_swap_output(
        pool_address: address,
        amount_in: u64,
        yes_to_no: bool
    ): u64 acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);

        let effective_fee = calculate_dynamic_fee(pool_state);
        let fee_amount = (amount_in * effective_fee) / FEE_DENOMINATOR;
        let amount_in_after_fee = amount_in - fee_amount;

        let (reserve_in, reserve_out) = if (yes_to_no) {
            (pool_state.reserve_yes, pool_state.reserve_no)
        } else {
            (pool_state.reserve_no, pool_state.reserve_yes)
        };

        (reserve_out * amount_in_after_fee) / (reserve_in + amount_in_after_fee)
    }

    #[view]
    /**
     * @notice Gets the current effective fee rate.
     * @param pool_address Address of the pool
     * @return Fee in basis points
     */
    public fun get_current_fee(pool_address: address): u64 acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);
        calculate_dynamic_fee(pool_state)
    }

    #[view]
    /**
     * @notice Checks if trading is currently enabled.
     * @param pool_address Address of the pool
     * @return true if trading is enabled
     */
    public fun is_trading_enabled(pool_address: address): bool acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);
        pool_state.is_trading_enabled
    }

    #[view]
    /**
     * @notice Gets position information.
     * @param pool_address Address of the pool
     * @param position_idx Position index
     * @return (yes_amount, no_amount, liquidity_tokens, entry_timestamp)
     */
    public fun get_position(
        pool_address: address,
        position_idx: u64
    ): (u64, u64, u64, u64) acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);
        assert!(ordered_map::contains(&pool_state.positions, &position_idx), E_POSITION_NOT_FOUND);

        let position = ordered_map::borrow(&pool_state.positions, &position_idx);
        (
            position.yes_amount,
            position.no_amount,
            position.liquidity_tokens,
            position.entry_timestamp
        )
    }

    #[view]
    /**
     * @notice Gets pool statistics.
     * @param pool_address Address of the pool
     * @return (reserve_yes, reserve_no, fee_yes, fee_no, position_count, is_trading)
     */
    public fun get_pool_stats(pool_address: address): (u64, u64, u64, u64, u64, bool) acquires PredictionPoolState {
        let pool_state = borrow_global<PredictionPoolState>(pool_address);
        (
            pool_state.reserve_yes,
            pool_state.reserve_no,
            pool_state.fee_yes,
            pool_state.fee_no,
            pool_state.positions_count,
            pool_state.is_trading_enabled
        )
    }
}