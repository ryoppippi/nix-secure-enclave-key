# enclave-key

`enclave-key` manages macOS CryptoTokenKit identities backed by the Secure
Enclave and exposes them as SSH authentication and Git SSH signing keys. The
private key never leaves the Secure Enclave. The repository contains only the
Nushell CLI, Nix integration, and configuration examples; it does not contain a
private key or an exported identity.

## Requirements

- macOS for `sc_auth`, Secure Enclave operations, and Apple’s SSH provider
- Nushell 0.114 or a packaged `enclave-key` binary
- `gh` is optional; it is used for GitHub key registration when available

All commands that create or change a Secure Enclave identity safely skip on
non-macOS systems. `enclave-key pub` can still read an existing public key on
any system.

## Local setup

Install the package with Nix, then perform the first identity creation as the
logged-in user on the Mac:

```text
nix run github:ryoppippi/enclave-key
enclave-key doctor
enclave-key setup
enclave-key pub
```

The defaults are:

```text
key file:   ~/.ssh/id_enclave_key
label:      enclave-key
protection: none
```

Use `--protection bio` to request biometric protection. macOS may require
Touch ID when that identity is used. `identity ensure` is idempotent: it
creates a missing CTK identity and SSH stub, leaves existing pairs alone, and
rejects an incomplete private/public stub pair. It never deletes an identity.

Configure SSH and Git manually if you are not using Home Manager:

```text
Host github.com
  IdentityFile ~/.ssh/id_enclave_key
  SecurityKeyProvider /usr/lib/ssh-keychain.dylib

git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_enclave_key
git config --global gpg.ssh.program "$(command -v enclave-key-git-sign)"
```

## Nix integration

The flake exposes `packages.<system>.default`, `darwinModules.default`,
`homeManagerModules.default`, and `overlays.default`.

Add the nix-darwin module to a system configuration to install the package:

```nix
{
  inputs.enclave-key.url = "github:ryoppippi/enclave-key";

  # Inside the darwin system modules list:
  modules = [ inputs.enclave-key.darwinModules.default ];
}
```

The nix-darwin module only installs `enclave-key`; it does not run
`sc_auth`, call GitHub, or require root access to a Secure Enclave identity.

Home Manager configures the SSH provider, Git SSH signing, and optional
user-level activation:

```nix
{
  imports = [ inputs.enclave-key.homeManagerModules.default ];

  programs.enclave-key = {
    enable = true;
    keyFile = "~/.ssh/id_enclave_key";
    label = "enclave-key";
    protection = "none";
    autoEnsure = true;
    signByDefault = true;
  };
}
```

When `autoEnsure` is enabled, Home Manager invokes `enclave-key identity
ensure` during user activation. It does not run GitHub API calls or
`gh ssh-key add`.

## GitHub registration

Register the same public key for one or both purposes:

```text
enclave-key github add --type signing
enclave-key github add --type authentication
enclave-key github add --type both
```

Before calling `gh ssh-key add`, the CLI compares the key algorithm and base64
key body with the authenticated account’s existing keys. Matching keys are
skipped regardless of their title. If `gh` is unavailable, unauthenticated, or
cannot access the endpoint, the CLI prints a prompt containing only the public
key path and registration command. It never asks for, prints, or copies the
private key.

Use `--prompt-only` to print those commands without contacting GitHub.

## CTK certificate operations

The CTK identity can also be used outside SSH:

```text
enclave-key identity list
enclave-key ctk csr <public-key-hash> <output-file>
enclave-key ctk import-certificate <certificate-file>
```

These commands preserve the broader CryptoTokenKit identity model and do not
assume that every identity is an SSH identity.

## Secretive migration

`enclave-key` does not reuse Secretive keys and does not remove Secretive
identities automatically. Migrate deliberately:

1. Keep the existing Secretive key available while creating a new
   `enclave-key` identity.
2. Run `enclave-key doctor` and `enclave-key pub` to verify the new stub and
   public key.
3. Add the new public key to GitHub as authentication and/or signing, then
   verify `ssh -T git@github.com` and a signed test commit.
4. Update other machines or services that need the new public key.
5. Remove the old Secretive key only after all consumers have been migrated,
   using Secretive itself or an explicit user action.

No Secure Enclave material belongs in a dotfiles repository. The `.pub` file
and the SSH stub are local artifacts and should be protected with normal SSH
file permissions.

## Development checks

The repository uses Nushell for both the CLI and Git signer wrapper. Useful
checks are:

```text
nu-check --debug nix/enclave-key.nu
nu-check --debug nix/enclave-key-git-sign.nu
nix fmt
nix flake check
nix build .#default
git diff --check
```

Secure Enclave creation, GitHub registration, and signed commits are manual
macOS checks. They are intentionally not part of CI or Nix activation.

## References

- [`sc_auth(8)`](https://keith.github.io/xcode-man-pages/sc_auth.8.html)
- [`gh ssh-key add`](https://cli.github.com/manual/gh_ssh-key_add)
- [GitHub SSH signing key API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub SSH key API](https://docs.github.com/en/rest/users/keys)
- [Git SSH signing configuration](https://git-scm.com/docs/git-config)
