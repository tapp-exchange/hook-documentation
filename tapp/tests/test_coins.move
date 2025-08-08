#[test_only]
module tapp::test_coins {
    use std::option;
    use std::signer::address_of;
    use std::string::utf8;
    use aptos_std::type_info::type_of;
    use aptos_framework::account::create_signer_for_test;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{
        BurnRef,
        generate_burn_ref,
        generate_mint_ref,
        generate_transfer_ref,
        Metadata,
        MintRef,
        TransferRef
    };
    use aptos_framework::object;
    use aptos_framework::object::{Object, object_address};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::primary_fungible_store::create_primary_store_enabled_fungible_asset;

    struct BTC has key {}

    struct ETH has key {}

    struct SOL has key {}

    struct XRP has key {}

    struct USDC has key {}

    struct USDT has key {}

    struct BUSD has key {}

    struct Cap<phantom T> has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef
    }

    fun init_module(signer: &signer) {
        create_coin<BTC>(signer);
        create_coin<ETH>(signer);
        create_coin<SOL>(signer);
        create_coin<XRP>(signer);
        create_coin<USDC>(signer);
        create_coin<USDT>(signer);
        create_coin<BUSD>(signer);
    }

    public entry fun quick_mint(signer: &signer, amount: u64) acquires Cap {
        mint<BTC>(signer, amount);
        mint<ETH>(signer, amount);
        mint<SOL>(signer, amount);
        mint<XRP>(signer, amount);
        mint<USDC>(signer, amount);
        mint<USDT>(signer, amount);
        mint<BUSD>(signer, amount);
    }

    public entry fun mint<T>(signer: &signer, amount: u64) acquires Cap {
        let cap = borrow_global<Cap<T>>(@tapp);
        primary_fungible_store::mint(&cap.mint_ref, address_of(signer), amount);
    }

    public entry fun create_coin<T: key>(signer: &signer) {
        let name = type_of<T>().struct_name();
        let constructor_ref = object::create_named_object(signer, name);

        create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(),
            utf8(name),
            utf8(name),
            8,
            utf8(b"http://example.com/icon"),
            utf8(b"http://example.com")
        );
        let mint_ref = generate_mint_ref(&constructor_ref);
        let burn_ref = generate_burn_ref(&constructor_ref);
        let transfer_ref = generate_transfer_ref(&constructor_ref);

        let cap = Cap<T> { mint_ref, burn_ref, transfer_ref };
        move_to(signer, cap);
    }

    #[view]
    public fun asset_address<T>(): address acquires Cap {
        object_address(&asset_meta<T>())
    }

    #[test_only]
    public fun asset_meta<T>(): Object<Metadata> acquires Cap {
        let cap = borrow_global<Cap<T>>(@tapp);
        fungible_asset::mint_ref_metadata(&cap.mint_ref)
    }

    #[test_only]
    public fun init_module_for_test() {
        init_module(&create_signer_for_test(@tapp));
    }
}
