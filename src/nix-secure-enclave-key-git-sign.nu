#!/usr/bin/env nu

const security_key_provider = "/usr/lib/ssh-keychain.dylib"
const ssh_keygen_path = "/usr/bin/ssh-keygen"

def require-macos [] {
    if $nu.os-info.name != "macos" {
        error make {msg: "nix-secure-enclave-key-git-sign requires macOS"}
    }
}

def --wrapped main [...arguments: string] {
    require-macos
    with-env {SSH_SK_PROVIDER: $security_key_provider} {
        ^$ssh_keygen_path ...$arguments
    }
}
