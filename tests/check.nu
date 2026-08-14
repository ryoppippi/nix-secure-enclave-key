#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell --command nu

def require [condition: bool, message: string] {
    if not $condition {
        error make {msg: $message}
    }
}

def source-file [root: string, relative: string]: nothing -> string {
    open --raw ($root | path join $relative)
}

def require-files [root: string, paths: list<string>] {
    $paths | each {|relative|
        let path = $root | path join $relative
        require ($path | path exists) $"required file is missing: ($relative)"
    } | ignore
}

def check-nu-source [path: string] {
    let result = (^nu --no-config-file -c $"source ($path)" | complete)
    require ($result.exit_code == 0) $"Nushell source check failed: ($path)"
}

def main [root: string] {
    let required = [
        "flake.nix"
        "dev/flake.nix"
        ".agents/release.md"
        "typos.toml"
        ".tagpr"
        "src/nix-secure-enclave-key.nu"
        "src/nix-secure-enclave-key-git-sign.nu"
        "package.nix"
        "modules/options.nix"
        ".github/tagpr-template.md"
        ".github/workflows/release.yaml"
        "modules/darwin-module.nix"
        "modules/home-manager-module.nix"
        "tests/fixtures-public-key.pub"
        "tests/e2e.nu"
        "tests/e2e-secure-enclave.nu"
        ".github/workflows/ci.yaml"
    ]
    require-files $root $required

    let cli_path = $root | path join "src/nix-secure-enclave-key.nu"
    let signer_path = $root | path join "src/nix-secure-enclave-key-git-sign.nu"
    let e2e_path = $root | path join "tests/e2e.nu"
    let secure_e2e_path = $root | path join "tests/e2e-secure-enclave.nu"
    check-nu-source $cli_path
    check-nu-source $signer_path
    check-nu-source $e2e_path
    check-nu-source $secure_e2e_path

    let cli = (source-file $root "src/nix-secure-enclave-key.nu")
    let signer = (source-file $root "src/nix-secure-enclave-key-git-sign.nu")
    let flake = (source-file $root "flake.nix")
    let dev_flake = (source-file $root "dev/flake.nix")
    let tagpr = (source-file $root ".tagpr")
    let release_workflow = (source-file $root ".github/workflows/release.yaml")
    let ci_workflow = (source-file $root ".github/workflows/ci.yaml")
    let package = (source-file $root "package.nix")
    let options_module = (source-file $root "modules/options.nix")
    let darwin_module = (source-file $root "modules/darwin-module.nix")
    let home_module = (source-file $root "modules/home-manager-module.nix")

    [
        "create-ctk-identity"
        "list-ctk-identities"
        "create-ctk-csr"
        "import-ctk-certificate"
        "SecurityKeyProvider"
        "identity-hash-for-label"
        "public-key-fingerprint"
        "select-generated-pair"
    ] | each {|token|
        require ($cli | str contains $token) $"CLI is missing required behavior: ($token)"
    } | ignore

    require ($signer | str contains "SSH_SK_PROVIDER") "Git signer wrapper is missing SSH_SK_PROVIDER"
    require ($signer | str contains "def --wrapped main") "Git signer wrapper must forward Git's short options"
    require ($cli | str contains "Secure Enclave operations require macOS") "CLI is missing its Darwin platform guard"
    require ($signer | str contains "requires macOS") "Git signer wrapper is missing its Darwin platform guard"
    require (not ($cli | str contains "skipped: Secure Enclave")) "CLI must not silently skip unsupported platforms"
    require ($cli | str contains "skips biometric protection") "CLI is missing the non-biometric protection description"
    require ($cli | str contains "requests it and may require Touch ID") "CLI is missing the biometric protection description"

    [
        "delete-ctk-identity"
        "delete-all-ctk-identities"
        "export-ctk-identity"
        "BEGIN OPENSSH PRIVATE KEY"
    ] | each {|token|
        require (not ($cli | str contains $token)) $"CLI contains forbidden identity operation or secret material: ($token)"
    } | ignore

    [
        "packages"
        "darwinModules.default"
        "homeManagerModules.default"
        "overlays.default"
    ] | each {|token|
        require ($flake | str contains $token) $"flake output is missing: ($token)"
    } | ignore

    [
        "nix-secure-enclave-key-git-sign.nu"
        "nix-secure-enclave-key-git-sign"
        "programs.ssh"
        "SecurityKeyProvider"
        "gpg.format"
        "gpg.ssh.program"
        "autoEnsure"
        "github.autoAdd"
        "github.type"
        "github.title"
        "home.activation.nix-secure-enclave-key-github-add"
        "pkgs.gh"
        "default = false"
        "none creates the identity without biometric protection"
        "bio requests biometric protection"
    ] | each {|token|
        require (($package + $options_module + $home_module) | str contains $token) $"Nix integration is missing: ($token)"
    } | ignore
    require ($home_module | str contains 'settings."*"') "SSH integration must apply to all hosts"

    [
        "programs.ssh.extraConfig"
        "SecurityKeyProvider"
        "system.requiresPrimaryUser"
        "system.activationScripts.postActivation"
        "/usr/bin/sudo --user="
        "gpg.ssh.program"
    ] | each {|token|
        require ($darwin_module | str contains $token) $"nix-darwin integration is missing: ($token)"
    } | ignore
    require ($dev_flake | str contains "programs =") "Development flake is missing formatter programs"
    require ($dev_flake | str contains "typos") "Development flake is missing typos"
    require ($dev_flake | str contains "checks.packaged-e2e") "Development flake is missing the packaged E2E check"

    [
        "versionFile = -"
        "vPrefix = true"
        "changelog = false"
        "release = false"
    ] | each {|token|
        require ($tagpr | str contains $token) $"tagpr configuration is missing: ($token)"
    } | ignore
    require ($release_workflow | str contains "Songmu/tagpr") "Release workflow is missing tagpr"
    require ($release_workflow | str contains "nix run nixpkgs#bun -- x changelogithub") "Release workflow is missing changelogithub"
    require ($ci_workflow | str contains "tests/e2e.nu") "CI workflow is missing packaged macOS E2E"
    require ($ci_workflow | str contains "tests/e2e-secure-enclave.nu") "CI workflow is missing Secure Enclave E2E probe"

    let fixture = $root | path join "tests/fixtures-public-key"
    let prompt_result = (
        ^nu --no-config-file $cli_path github add --type both --prompt-only --key-file $fixture
        | complete
    )
    if $prompt_result.exit_code != 0 {
        error make {msg: $"GitHub prompt-only check failed: ($prompt_result.stderr)"}
    }
    require ($prompt_result.stdout | str contains "gh ssh-key add") "GitHub prompt is missing the registration command"
    require ($prompt_result.stdout | str contains "--type signing") "GitHub signing prompt is missing"
    require ($prompt_result.stdout | str contains "--type authentication") "GitHub authentication prompt is missing"

    print "nix-secure-enclave-key static checks passed"
}
