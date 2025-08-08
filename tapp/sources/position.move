module tapp::position {
    use std::option;
    use std::signer::address_of;
    use std::string::{String, utf8};
    use aptos_std::string_utils::{format1, to_string};
    use aptos_framework::object;
    use aptos_framework::object::{address_to_object, object_from_constructor_ref, ObjectCore, transfer};

    use aptos_token_objects::collection;
    use aptos_token_objects::token;

    #[test_only]
    use aptos_framework::object::create_object_address;
    #[test_only]
    use aptos_token_objects::token::create_token_seed;

    const TAPP_COLLECTION_DESC: vector<u8> = b"TAPP-COLLECTION";
    const TAPP_COLLECTION_NAME: vector<u8> = b"TAPP";
    const TAPP_REPO_URL: vector<u8> = b"https://github.com/Undercurrent-Technologies/tap-contract";

    const HOOK_ALIAS: u8 = 1;
    const HOOK_NFT_SPRINGBOARD: u8 = 5;

    const EUNAUTHORIZED_NFT_POSITION: u64 = 0xa10002;

    struct PositionMeta has copy, drop, key, store {
        hook_type: u8,
        pool_addr: address,
        position_idx: u64,
    }

    public fun position_meta(position_addr: address): PositionMeta acquires PositionMeta {
        *borrow_global<PositionMeta>(position_addr)
    }

    public fun hook_type(self: &PositionMeta): u8 {
        self.hook_type
    }

    public fun pool_id(self: &PositionMeta): address {
        self.pool_addr
    }

    public fun position_idx(self: &PositionMeta): u64 {
        self.position_idx
    }

    public(package) fun init_collection(sender: &signer) {
        collection::create_unlimited_collection(
            sender,
            utf8(TAPP_COLLECTION_DESC),
            utf8(TAPP_COLLECTION_NAME),
            option::none(),
            utf8(TAPP_REPO_URL),
        );
    }

    public(package) fun mint_position(
        vault: &signer,
        hook_type: u8,
        pool_addr: address,
        position_idx: u64,
        recipient: address
    ): address {
        let position_name = position_name(pool_addr, position_idx);
        let object_signer = internal_create_position(vault, position_name, recipient);
        move_to(&object_signer, PositionMeta {
            hook_type,
            pool_addr,
            position_idx,
        });
        address_of(&object_signer)
    }

    public(package) fun burn_position(owner: &signer, position_addr: address) {
        transfer(owner, address_to_object<ObjectCore>(position_addr), @0x0);
    }

    public(package) fun authorized_borrow(
        _vault: &signer,
        _owner: &signer,
        _pool_addr: address,
        position_addr: address,
    ): PositionMeta acquires PositionMeta {
        let position_meta = borrow_global<PositionMeta>(position_addr);
        *position_meta
    }

    fun position_name(pool_addr: address, position_idx: u64): String {
        let position_name = to_string(&pool_addr);
        position_name.append(format1(&b"_{}", position_idx));
        position_name
    }

    fun internal_create_position(vault: &signer, position_name: String, recipient: address): signer {
        let constructor_ref = token::create_named_token(
            vault,
            utf8(TAPP_COLLECTION_NAME),
            position_name,
            position_name,
            option::none(),
            utf8(TAPP_REPO_URL),
        );
        transfer(vault, object_from_constructor_ref<ObjectCore>(&constructor_ref), recipient);
        object::generate_signer(&constructor_ref)
    }

    #[test_only]
    public fun position_address(vault_addr: address, pool_addr: address, position_idx: u64): address {
        let position_name = position_name(pool_addr, position_idx);
        let seed = create_token_seed(&utf8(TAPP_COLLECTION_NAME), &position_name);
        create_object_address(&vault_addr, seed)
    }
}