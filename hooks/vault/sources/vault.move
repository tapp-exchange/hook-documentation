module vault::vault {
    use std::bcs::to_bytes;
    use std::option::{some, none, Option};
    use std::signer::address_of;
    use aptos_std::bcs_stream::{BCSStream, deserialize_u64, deserialize_vector, deserialize_u8};
    use aptos_std::debug::print;
    use aptos_framework::timestamp;
    use aptos_framework::ordered_map::{Self, OrderedMap};

    const T_TIMELOCKED_VAULT: u8 = 1;
    const T_INSURANCE_VAULT: u8 = 2;
    const FEE_DENOM: u64 = 10000;

    const EINVALID_VAULT_TYPE: u64 = 0;
    const ESLOT_NOT_FOUND: u64 = 1;
    const ESLOT_REDEEM_TOO_EARLY: u64 = 2;
    const ENOT_IMPLEMENTED: u64 = 3;

    struct Vault<T> has key {
        supported_assets: vector<address>,
        slots: OrderedMap<u64, T>,
        slots_count: u64,
        fee: u64,
        fee_amounts: vector<u64>,
        creator: address
    }

    struct TimeLockedSlot has copy, drop, store {
        amounts: vector<u64>,
        created_at: u64,
        lock_until: u64
    }

    struct InsuranceSlot has copy, drop, store {
        amounts: vector<u64>,
        created_at: u64
    }

    public fun pool_seed(vault_type: u8, assets: vector<address>): vector<u8> {
        let seed = vector[];
        seed.append(to_bytes(&vault_type));
        seed.append(to_bytes(&assets));
        seed
    }

    /// Creates new vault type for a given set of assets
    public fun create_pool(
        pool_signer: &signer,
        assets: vector<address>,
        fee: u64,
        stream: &mut BCSStream,
        creator: address
    ) {
        let vault_type = deserialize_u8(stream);

        if (vault_type == T_TIMELOCKED_VAULT) {
            move_to(
                pool_signer,
                Vault<TimeLockedSlot> {
                    supported_assets: assets,
                    slots: ordered_map::new(),
                    slots_count: 0,
                    fee,
                    fee_amounts: assets.map(|_| 0),
                    creator
                }
            );
        } else if (vault_type == T_INSURANCE_VAULT) {
            move_to(
                pool_signer,
                Vault<InsuranceSlot> {
                    supported_assets: assets,
                    slots: ordered_map::new(),
                    slots_count: 0,
                    fee,
                    fee_amounts: assets.map(|_| 0),
                    creator
                }
            );
        } else {
            abort EINVALID_VAULT_TYPE
        };
    }

    /// deposit to slot of a vault.
    public fun deposit(
        pool_signer: &signer,
        position_idx: Option<u64>,
        stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, Option<u64>) acquires Vault {
        if (exists<Vault<TimeLockedSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<TimeLockedSlot>[address_of(pool_signer)];
            if (position_idx.is_none()) {
                let lock_duration = deserialize_u64(stream);
                let amounts = deserialize_vector(stream, |s| deserialize_u64(s));
                let new_slot_idx = vault.slots_count;
                vault.slots.add(new_slot_idx, TimeLockedSlot {
                    amounts,
                    created_at: timestamp::now_seconds(),
                    lock_until: timestamp::now_seconds() + lock_duration
                });
                vault.slots_count += 1;
                return (amounts, some(new_slot_idx))
            } else {
                // existing slots
                let position_idx = position_idx.destroy_some();
                assert!(vault.slots.contains(&position_idx), ESLOT_NOT_FOUND);

                let amounts = deserialize_vector(stream, |s| deserialize_u64(s));
                let slot = vault.slots.borrow_mut(&position_idx);
                slot.amounts = slot.amounts.zip_map(amounts, |prev_amount, new_amount| prev_amount + new_amount);
                return (amounts, none())
            }
        } else if (exists<Vault<InsuranceSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<InsuranceSlot>[address_of(pool_signer)];
            let amounts = deserialize_vector(stream, |s| deserialize_u64(s));
            if (position_idx.is_none()) {
                let new_slot_idx = vault.slots_count;
                vault.slots.add(new_slot_idx, InsuranceSlot {
                    amounts,
                    created_at: timestamp::now_seconds()
                });
                vault.slots_count += 1;
                return (amounts, some(new_slot_idx))
            } else {
                // existing slots
                let position_idx = position_idx.destroy_some();
                assert!(vault.slots.contains(&position_idx), ESLOT_NOT_FOUND);

                let slot = vault.slots.borrow_mut(&position_idx);
                slot.amounts = slot.amounts.zip_map(amounts, |prev_amount, new_amount| prev_amount + new_amount);
                return (amounts, none())
            }
        } else {
            abort EINVALID_VAULT_TYPE
        }
    }

    /// redeem slot of a vault.
    public fun withdraw(
        pool_signer: &signer,
        position_idx: u64,
        _stream: &mut BCSStream,
        _sender: address
    ): (vector<u64>, Option<u64>) acquires Vault {
        if (exists<Vault<TimeLockedSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<TimeLockedSlot>[address_of(pool_signer)];
            assert!(vault.slots.contains(&position_idx), ESLOT_NOT_FOUND);

            let slot = vault.slots.borrow(&position_idx);
            assert!(
                timestamp::now_seconds() >= slot.lock_until,
                ESLOT_REDEEM_TOO_EARLY
            );
            let amounts = slot.amounts;
            vault.fee_amounts.zip_mut(
                &mut amounts,
                |fee_amount, amount| *fee_amount += *amount * vault.fee / FEE_DENOM
            );
            vault.slots.remove(&position_idx);
            return (amounts, some(position_idx))
        } else if (exists<Vault<InsuranceSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<InsuranceSlot>[address_of(pool_signer)];
            assert!(vault.slots.contains(&position_idx), ESLOT_NOT_FOUND);

            let slot = vault.slots.borrow(&position_idx);
            let amounts = slot.amounts;
            vault.fee_amounts.zip_mut(
                &mut amounts,
                |fee_amount, amount| *fee_amount += *amount * vault.fee / FEE_DENOM
            );
            vault.slots.remove(&position_idx);
            return (amounts, some(position_idx))
        } else {
            abort EINVALID_VAULT_TYPE
        }
    }

    public fun swap(
        _pool_signer: &signer,
        _stream: &mut BCSStream,
        _sender: address
    ): vector<u64> {
        abort ENOT_IMPLEMENTED
    }

    public fun collect_fee(
        pool_signer: &signer,
        _recipient: address
    ): vector<u64> acquires Vault {
        if (exists<Vault<TimeLockedSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<TimeLockedSlot>[address_of(pool_signer)];
            let amounts = vault.fee_amounts;
            vault.fee_amounts = vector[];
            return amounts
        } else if (exists<Vault<InsuranceSlot>>(address_of(pool_signer))) {
            let vault = &mut Vault<InsuranceSlot>[address_of(pool_signer)];
            let amounts = vault.fee_amounts;
            vault.fee_amounts = vector[];
            return amounts
        } else {
            abort EINVALID_VAULT_TYPE
        }
    }
}

