#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell --command nu

def require [condition: bool, message: string] {
    if not $condition {
        error make {msg: $message}
    }
}

def run-package [root: string, arguments: list<string>]: nothing -> record {
    let result = (do {
        cd $root
        ^nix run ".#default" "--" ...$arguments
    } | complete)
    if $result.exit_code != 0 {
        error make {msg: $"nix run failed: ($result.stderr)"}
    }
    $result
}

def build-package [root: string]: nothing -> string {
    let result = (do {
        cd $root
        ^nix build ".#default" "--no-link" "--print-build-logs" "--print-out-paths"
    } | complete)
    if $result.exit_code != 0 {
        error make {msg: $"nix build failed: ($result.stderr)"}
    }

    let output_path = $result.stdout | lines | last | str trim
    if ($output_path | is-empty) {
        error make {msg: "nix build returned no package path"}
    }
    $output_path
}

def main [root: string] {
    let runner_temp = $env.RUNNER_TEMP? | default (mktemp -d)
    let run_id = $env.GITHUB_RUN_ID? | default "local"
    let run_attempt = $env.GITHUB_RUN_ATTEMPT? | default "1"
    let key_file = $runner_temp | path join "nix-secure-enclave-key-e2e"
    let label = $"nix-secure-enclave-key-ci-($run_id)-($run_attempt)"

    let setup_result = (run-package $root [
        "setup"
        "--key-file"
        $key_file
        "--label"
        $label
        "--protection"
        "none"
    ])
    print $setup_result.stdout
    require ($key_file | path exists) "Secure Enclave E2E did not create an SSH stub"
    require ($"($key_file).pub" | path exists) "Secure Enclave E2E did not create a public key"

    let package_path = build-package $root
    let signer = $package_path | path join "bin/nix-secure-enclave-key-git-sign"
    let input_file = $runner_temp | path join "nix-secure-enclave-key-e2e-input"
    "Secure Enclave signing E2E" | save $input_file

    let sign_result = (with-env {SSH_SK_PROVIDER: "/usr/lib/ssh-keychain.dylib"} {
        ^$signer "-Y" "sign" "-n" "git" "-f" $key_file $input_file
    } | complete)
    if $sign_result.exit_code != 0 {
        error make {msg: $"Secure Enclave SSH signing failed: ($sign_result.stderr)"}
    }
    require ($"($input_file).sig" | path exists) "Secure Enclave E2E did not create an SSH signature"

    print "Secure Enclave E2E passed"
}
