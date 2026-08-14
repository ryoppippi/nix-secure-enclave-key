# nix-secure-enclave-key

> macOS-only, Nix-first tooling for Secure Enclave-backed SSH authentication
> and Git SSH signing.

`nix-secure-enclave-key` manages macOS CryptoTokenKit identities backed by the
Secure Enclave and exposes them as SSH authentication and Git SSH signing keys. The
private key never leaves the Secure Enclave. The repository contains only the
Nushell CLI, Nix integration, and configuration examples; it does not contain a
private key or an exported identity.

The project is inspired by [Secretive](https://github.com/maxgoedjen/secretive)
and its Secure Enclave-backed SSH workflow. It talks to macOS CryptoTokenKit and
Apple's SSH provider directly, so Secretive is not a runtime dependency.

## Features

- 🍎 **macOS only**: Built on Apple CryptoTokenKit, Secure Enclave, and the
  Apple SSH provider; Linux and other platforms are unsupported.
- 🔐 **Secure Enclave identities**: Create and idempotently manage a macOS
  CryptoTokenKit identity and its non-secret SSH stub.
- 🔑 **SSH login**: Use the key with any SSH server where the public key is
  authorized.
- ✍️ **Git SSH signing**: Sign Git commits with the same Secure Enclave-backed
  key.
- 🐙 **GitHub registration**: Register the public key for authentication,
  signing, or both, while skipping keys that are already registered.
- 📜 **CTK certificates**: Create certificate signing requests and import CTK
  certificates.
- ❄️ **Nix first**: Use the package with nix-darwin and Home Manager
  without running Secure Enclave or GitHub operations as root during activation.

## Motivation

I used [Secretive](https://github.com/maxgoedjen/secretive) for a long time and
was happy with its Secure Enclave-backed SSH workflow. The friction was its
GUI-only control path: configuring and operating the key from shell-based
workflows, especially coding agents, was awkward. When the Mac was asleep, a
coding agent could not complete a signing request, which was especially
frustrating for an otherwise declarative and automated workflow.

`nix-secure-enclave-key` keeps the Secure Enclave protection while making the
identity, SSH stub, Git signing, and GitHub registration workflows available as
an explicit CLI and Nix configuration. Secretive remains an inspiration, not a
runtime dependency, and this project never reuses or deletes its identities.

## Requirements

- macOS for `sc_auth`, Secure Enclave operations, and Apple’s SSH provider
- Nix on macOS for the packaged `nix-secure-enclave-key` binary
- `gh` is only needed for GitHub registration; the Nix modules add it
  automatically when opt-in registration is enabled

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

`--protection none` creates the Secure Enclave identity without biometric
protection. `--protection bio` requests biometric protection; macOS may require
Touch ID when that identity is created or used. These values are passed to
[`sc_auth(8)`](https://keith.github.io/xcode-man-pages/sc_auth.8.html).
`identity ensure` is idempotent: it creates a missing CTK identity and SSH stub,
leaves existing pairs alone, and rejects an incomplete private/public stub pair.
It never deletes an identity.

The generated SSH key is not GitHub-specific. It can authenticate to any SSH
server where its public key is present in `authorized_keys`; GitHub registration
is only needed when using the key with GitHub.

Configure SSH authentication for all hosts and Git signing manually if you are
not using nix-darwin or Home Manager:

```text
Host *
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
skipped regardless of their title. If `gh` is not on PATH, unauthenticated, or
cannot access the endpoint, the CLI prints a prompt containing only the public
key path and registration command. It never asks for, prints, or copies the
private key.

Use `--prompt-only` to print those commands without contacting GitHub.

## With nix-darwin

The nix-darwin module is the primary integration and does not require Home
Manager. It installs the package, configures the system SSH client, configures
Git SSH signing, and runs local identity setup as the primary user during
activation.

The flake exposes `packages.<system>.default`, `darwinModules.default`,
`homeManagerModules.default`, and `overlays.default`.

Set `system.primaryUser`, then configure the module in the system configuration:

```nix
{
  inputs.nix-secure-enclave-key.url = "github:ryoppippi/nix-secure-enclave-key";

  modules = [
    inputs.nix-secure-enclave-key.darwinModules.default
    ({ ... }: {
      system.primaryUser = "your-macOS-user";

      programs.nix-secure-enclave-key = {
        enable = true; # Install the package and configure SSH/Git integration.
        keyFile = "~/.ssh/id_enclave_key"; # Non-secret SSH stub for login and signing.
        label = "nix-secure-enclave-key"; # CryptoTokenKit identity label.
        protection = "none"; # "bio" requests biometric protection and may require Touch ID.
        autoEnsure = true; # Create the identity and SSH stub during activation.
        signByDefault = true; # Sign Git commits with the Secure Enclave-backed key.
        github = {
          autoAdd = false; # Set true to register the public key during activation.
          type = "both"; # Register SSH authentication, Git signing, or both.
          title = "nix-secure-enclave-key"; # GitHub title for new registrations.
        };
      };
    })
  ];
}
```

`autoEnsure` invokes `identity ensure` as the configured primary user, not as
root. `github.autoAdd` is disabled by default. When enabled, nix-darwin adds
`gh` to the system package set and invokes `github add` as the primary user;
the CLI compares the public key first and skips keys already registered with
GitHub. This means `darwin-rebuild switch` can complete the local setup and,
optionally, both GitHub registrations without Home Manager.

Home Manager is optional. If you use standalone Home Manager instead of
nix-darwin, import its module and use the same `programs.nix-secure-enclave-key`
options:

```nix
{
  imports = [ inputs.nix-secure-enclave-key.homeManagerModules.default ];

  programs.nix-secure-enclave-key = {
    enable = true; # Install the package and configure SSH/Git integration.
    keyFile = "~/.ssh/id_enclave_key"; # SSH stub for login and Git signing; its public key is in the .pub file.
    label = "nix-secure-enclave-key"; # CryptoTokenKit label used for idempotent ensure.
    protection = "none"; # "none" skips biometric protection; "bio" requests it and may require Touch ID.
    autoEnsure = true; # Create the missing identity and SSH stub during user activation.
    signByDefault = true; # Make Git SSH signing the default for commits.
    github = {
      autoAdd = false; # Register the public key during activation; disabled by default because this writes to GitHub.
      type = "both"; # Register the key for SSH authentication, Git signing, or both.
      title = "nix-secure-enclave-key"; # Title used for a new GitHub SSH key.
    };
  };
}
```

When `autoEnsure` is enabled in the Home Manager module, the same operations
run during user activation. GitHub registration remains skipped unless
`github.autoAdd = true` is explicitly set.

## CTK certificate operations

The CTK identity can also be used outside SSH:

```text
nix-secure-enclave-key identity list
nix-secure-enclave-key ctk csr <public-key-hash> <output-file>
nix-secure-enclave-key ctk import-certificate <certificate-file>
```

These commands preserve the broader CryptoTokenKit identity model and do not
assume that every identity is an SSH identity.

## CLI reference

The options below apply to the commands shown above:

| Argument | Accepted values | Default | Applies to |
| --- | --- | --- | --- |
| `--key-file` | Path to the SSH stub; its public key is `<path>.pub` | `~/.ssh/id_enclave_key` | `setup`, `identity ensure`, `ssh ensure`, `pub`, `github add`, `doctor` |
| `--label` | Any non-empty CryptoTokenKit identity label | `nix-secure-enclave-key` | `setup`, `identity ensure`, `ssh ensure` |
| `--protection` | `none`: no biometric protection; `bio`: biometric protection, which may require Touch ID | `none` | `setup`, `identity ensure`, `ssh ensure` |
| `--copy` | Flag; no value | Off | `pub` |
| `--type` | `signing`, `authentication`, or `both` | `both` | `github add` |
| `--title` | Any GitHub SSH key title | `nix-secure-enclave-key` | `github add` |
| `--prompt-only` | Flag; no GitHub API or write is performed | Off | `github add` |

`none` is the non-biometric mode. `bio` requests biometric protection for the
Secure Enclave identity and may require Touch ID when the identity is created or
the key is used. `--type` selects GitHub's signing-key
endpoint, authentication-key endpoint, or both. Existing GitHub keys are
matched by algorithm and key body, not by title.

The CTK commands use positional arguments: `ctk csr` takes an identity hash
from `identity list` and the output-file path for the CSR; `ctk
import-certificate` takes the certificate-file path to import.

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
- [`ssh-keygen(1)`](https://man.openbsd.org/ssh-keygen)
- [`gh ssh-key add`](https://cli.github.com/manual/gh_ssh-key_add)
- [GitHub SSH signing key API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub SSH key API](https://docs.github.com/en/rest/users/keys)
- [Git SSH signing configuration](https://git-scm.com/docs/git-config)
- [Secure Enclave で git commit の署名鍵を管理する](https://www.mizdra.net/entry/2026/08/07/101542)
