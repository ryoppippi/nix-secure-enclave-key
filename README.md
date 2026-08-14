# nix-secure-enclave-key

`nix-secure-enclave-key` manages macOS CryptoTokenKit identities backed by the
Secure Enclave and exposes them as SSH authentication and Git SSH signing keys. The
private key never leaves the Secure Enclave. The repository contains only the
Nushell CLI, Nix integration, and configuration examples; it does not contain a
private key or an exported identity.

The project is inspired by [Secretive](https://github.com/maxgoedjen/secretive)
and its Secure Enclave-backed SSH workflow. It talks to macOS CryptoTokenKit and
Apple's SSH provider directly, so Secretive is not a runtime dependency.

## Requirements

- macOS for `sc_auth`, Secure Enclave operations, and Apple’s SSH provider
- Nix on macOS for the packaged `nix-secure-enclave-key` binary
- `gh` is optional; it is used for GitHub key registration when available

This is a Darwin-only Nix package. Linux and other platforms are unsupported;
the project does not generate fallback SSH keys outside the Secure Enclave.

## Without nix-darwin

Install the package with Nix, then perform the first identity creation as the
logged-in user on the Mac:

```text
nix profile install github:ryoppippi/nix-secure-enclave-key
nix-secure-enclave-key doctor
nix-secure-enclave-key setup
nix-secure-enclave-key pub
```

For a one-off invocation without installing the package, pass the command to
`nix run`:

```text
nix run github:ryoppippi/nix-secure-enclave-key -- doctor
```

The defaults are:

```text
key file:   ~/.ssh/id_enclave_key
label:      nix-secure-enclave-key
protection: none
```

Use `--protection bio` to request biometric protection. macOS may require
Touch ID when that identity is used. `identity ensure` is idempotent: it
creates a missing CTK identity and SSH stub, leaves existing pairs alone, and
rejects an incomplete private/public stub pair. It never deletes an identity.

### CLI arguments

The options below apply to the commands shown in the usage examples:

| Argument | Accepted values | Default | Applies to |
| --- | --- | --- | --- |
| `--key-file` | Path to the SSH stub; its public key is `<path>.pub` | `~/.ssh/id_enclave_key` | `setup`, `identity ensure`, `ssh ensure`, `pub`, `github add`, `doctor` |
| `--label` | Any non-empty CryptoTokenKit identity label | `nix-secure-enclave-key` | `setup`, `identity ensure`, `ssh ensure` |
| `--protection` | `none` or `bio` | `none` | `setup`, `identity ensure`, `ssh ensure` |
| `--copy` | Flag; no value | Off | `pub` |
| `--type` | `signing`, `authentication`, or `both` | `both` | `github add` |
| `--title` | Any GitHub SSH key title | `nix-secure-enclave-key` | `github add` |
| `--prompt-only` | Flag; no GitHub API or write is performed | Off | `github add` |

`bio` requests biometric protection for the Secure Enclave identity and may
require Touch ID when the key is used. `--type` selects GitHub's signing-key
endpoint, authentication-key endpoint, or both. Existing GitHub keys are
matched by algorithm and key body, not by title.

The CTK commands use positional arguments: `ctk csr` takes an identity hash
from `identity list` and the output-file path for the CSR; `ctk
import-certificate` takes the certificate-file path to import.

Configure SSH and Git manually if you are not using Home Manager:

```text
Host github.com
  IdentityFile ~/.ssh/id_enclave_key
  SecurityKeyProvider /usr/lib/ssh-keychain.dylib

git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_enclave_key
git config --global gpg.ssh.program "$(command -v nix-secure-enclave-key-git-sign)"
```

## GitHub integration

Register the same public key for one or both purposes:

```text
nix-secure-enclave-key github add --type signing
nix-secure-enclave-key github add --type authentication
nix-secure-enclave-key github add --type both
```

Before calling `gh ssh-key add`, the CLI compares the key algorithm and base64
key body with the authenticated account’s existing keys. Matching keys are
skipped regardless of their title. If `gh` is unavailable, unauthenticated, or
cannot access the endpoint, the CLI prints a prompt containing only the public
key path and registration command. It never asks for, prints, or copies the
private key.

Use `--prompt-only` to print those commands without contacting GitHub.

## With nix-darwin

Use nix-darwin and Home Manager to configure the package, SSH provider, Git SSH
signing, and user-level identity ensure declaratively.

The flake exposes `packages.<system>.default`, `darwinModules.default`,
`homeManagerModules.default`, and `overlays.default`.

Add the nix-darwin module to a system configuration to install the package:

```nix
{
  inputs.nix-secure-enclave-key.url = "github:ryoppippi/nix-secure-enclave-key";

  # Inside the darwin system modules list:
  modules = [ inputs.nix-secure-enclave-key.darwinModules.default ];
}
```

The nix-darwin module only installs `nix-secure-enclave-key`; it does not run
`sc_auth`, call GitHub, or require root access to a Secure Enclave identity.

Home Manager configures the SSH provider, Git SSH signing, and optional
user-level activation:

```nix
{
  imports = [ inputs.nix-secure-enclave-key.homeManagerModules.default ];

  programs.nix-secure-enclave-key = {
    enable = true;
    keyFile = "~/.ssh/id_enclave_key";
    label = "nix-secure-enclave-key";
    protection = "none";
    autoEnsure = true;
    signByDefault = true;
  };
}
```

When `autoEnsure` is enabled, Home Manager invokes `nix-secure-enclave-key identity
ensure` during user activation. It does not run GitHub API calls or
`gh ssh-key add`.

## CTK certificate operations

The CTK identity can also be used outside SSH:

```text
nix-secure-enclave-key identity list
nix-secure-enclave-key ctk csr <public-key-hash> <output-file>
nix-secure-enclave-key ctk import-certificate <certificate-file>
```

These commands preserve the broader CryptoTokenKit identity model and do not
assume that every identity is an SSH identity.

## Secretive migration

`nix-secure-enclave-key` does not reuse Secretive keys and does not remove
Secretive identities automatically. Migrate deliberately:

1. Keep the existing Secretive key available while creating a new
   `nix-secure-enclave-key` identity.
2. Run `nix-secure-enclave-key doctor` and `nix-secure-enclave-key pub` to verify
   the new stub and public key.
3. Add the new public key to GitHub as authentication and/or signing, then
   verify `ssh -T git@github.com` and a signed test commit.
4. Update other machines or services that need the new public key.
5. Remove the old Secretive key only after all consumers have been migrated,
   using Secretive itself or an explicit user action.

No Secure Enclave material belongs in a dotfiles repository. The `.pub` file
and the SSH stub are local artifacts and should be protected with normal SSH
file permissions.

## GitHub Sponsors

<p align="center">
    <a href="https://github.com/sponsors/ryoppippi">
        <img src="https://sponsors.ryoppippi.com/sponsors.png" alt="Sponsors">
    </a>
</p>

## References

- [`sc_auth(8)`](https://keith.github.io/xcode-man-pages/sc_auth.8.html)
- [`gh ssh-key add`](https://cli.github.com/manual/gh_ssh-key_add)
- [GitHub SSH signing key API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub SSH key API](https://docs.github.com/en/rest/users/keys)
- [Git SSH signing configuration](https://git-scm.com/docs/git-config)
