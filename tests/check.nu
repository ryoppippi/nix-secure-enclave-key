#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell --command nu

def require [condition: bool, message: string] {
    if not $condition {
        error make {msg: $message}
    }
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

    print "nix-secure-enclave-key source checks passed"
}
