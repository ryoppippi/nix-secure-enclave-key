#!/usr/bin/env nu

const security_key_provider = "/usr/lib/ssh-keychain.dylib"
const ssh_keygen_path = "/usr/bin/ssh-keygen"

def main [...arguments: string] {
    with-env {SSH_SK_PROVIDER: $security_key_provider} {
        ^$ssh_keygen_path ...$arguments
    }
}
