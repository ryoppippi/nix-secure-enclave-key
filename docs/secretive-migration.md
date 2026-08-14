# Secretive migration checklist

`nix-secure-enclave-key` creates a new CryptoTokenKit identity through macOS and does not
attempt to discover, import, delete, or reuse Secretive identities. This keeps
the migration explicit and avoids treating two different key stores as if they
were interchangeable.

## Before changing SSH configuration

1. Leave the working Secretive key in place.
2. Install `nix-secure-enclave-key` and run `nix-secure-enclave-key setup` as the logged-in user.
3. Check `nix-secure-enclave-key doctor` and save the output of `nix-secure-enclave-key pub` only as
   the public-key record needed for registration.
4. Do not copy the private stub into a repository or attempt to export a
   Secure Enclave key.

## Verify the replacement

Register the new public key with the intended GitHub key type:

```text
nix-secure-enclave-key github add --type both
```

Then test both flows that matter for the machine:

```text
ssh -T git@github.com
git commit -S -m "test: verify ssh signing"
```

If GitHub registration cannot be performed through `gh`, use the printed
prompt and register the public key through an already authenticated workflow.
The prompt never contains private key material.

## Retire Secretive only after verification

Update every machine, repository, CI credential, and signing configuration that
still depends on the Secretive public key. Once the replacement has been
verified everywhere, remove the old key through an explicit Secretive action.
`nix-secure-enclave-key` intentionally has no deletion command for existing identities.
