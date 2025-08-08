# Tap Minified
Using Tap Minified to testing your new hook.

## Setup

## Create your hook
Let's start with a simple hook at [../hooks/basic/README.md](../hooks/basic/README.md)

### Add your hook
Modify `Move.toml`:
```toml
...

[dependencies]
basic = { local = "../hooks/basic" }
```

Add your hook to `hook_factory.move`:
```
public(package) fun create_pool(
        vault: &signer,
        creator: address,
        hook_type: u8,
        stream: &mut BCSStream
    ): ConstructorRef {
      ...

      if (hook_type == YOUR_HOOK_TYPE) {
          ...
      };

      ...
}
```

### Write tests under `tests` folder.
Example:
```
/tests:
    advanced_tests.move
    basic_tests.move
    vault_tests.move
    your_hook_tests.move
```