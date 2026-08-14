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
        "src/nix-secure-enclave-key.nu"
        "src/nix-secure-enclave-key-git-sign.nu"
        "package.nix"
        "modules/darwin-module.nix"
        "modules/home-manager-module.nix"
        "tests/fixtures-public-key.pub"
    ]
    require-files $root $required

    let cli_path = $root | path join "src/nix-secure-enclave-key.nu"
    let signer_path = $root | path join "src/nix-secure-enclave-key-git-sign.nu"
    check-nu-source $cli_path
    check-nu-source $signer_path

    let cli = (source-file $root "src/nix-secure-enclave-key.nu")
    let signer = (source-file $root "src/nix-secure-enclave-key-git-sign.nu")
    let flake = (source-file $root "flake.nix")
    let package = (source-file $root "package.nix")
    let home_module = (source-file $root "modules/home-manager-module.nix")

    [
        "create-ctk-identity"
        "list-ctk-identities"
        "create-ctk-csr"
        "import-ctk-certificate"
        "SecurityKeyProvider"
    ] | each {|token|
        require ($cli | str contains $token) $"CLI is missing required behaviour: ($token)"
    } | ignore

    require ($signer | str contains "SSH_SK_PROVIDER") "Git signer wrapper is missing SSH_SK_PROVIDER"
    require ($cli | str contains "Secure Enclave operations require macOS") "CLI is missing its Darwin platform guard"
    require ($signer | str contains "requires macOS") "Git signer wrapper is missing its Darwin platform guard"
    require (not ($cli | str contains "skipped: Secure Enclave")) "CLI must not silently skip unsupported platforms"

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
    ] | each {|token|
        require (($package + $home_module) | str contains $token) $"Nix integration is missing: ($token)"
    } | ignore

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
