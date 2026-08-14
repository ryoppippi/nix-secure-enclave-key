#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell --command nu

def require [condition: bool, message: string] {
    if not $condition {
        error make {msg: $message}
    }
}

def short-public-key-fingerprint [public_file: string]: nothing -> string {
    let result = (^/usr/bin/ssh-keygen "-lf" $public_file | complete)
    if $result.exit_code != 0 {
        error make {msg: $"ssh-keygen failed: ($result.stderr)"}
    }

    let fields = $result.stdout | str trim | split row " " | where {|field| not ($field | is-empty)}
    if ($fields | length) < 2 {
        error make {msg: $"ssh-keygen returned no fingerprint for: ($public_file)"}
    }

    $fields.1
    | str replace "SHA256:" ""
    | split chars
    | first 12
    | str join ""
}

def local-machine-name []: nothing -> string {
    let result = (^/usr/sbin/scutil "--get" "LocalHostName" | complete)
    if $result.exit_code != 0 {
        error make {msg: $"scutil failed: ($result.stderr)"}
    }

    $result.stdout
    | str trim
    | str replace --all " " "-"
    | str replace --all "/" "-"
    | str replace --all ":" "-"
    | str replace --all "+" "-"
    | str replace --all "=" ""
}

def run-package [root: string, package: string, arguments: list<string>]: nothing -> record {
    let result = (if ($package | is-empty) {
        do {
            cd $root
            ^nix run ".#default" "--" ...$arguments
        } | complete
    } else {
        ^$package ...$arguments | complete
    })
    if $result.exit_code != 0 {
        error make {msg: $"nix run failed: ($result.stderr)"}
    }
    $result
}

def main [root: string, --package: string = ""] {
    let fixture = $root | path join "tests/fixtures-public-key"
    let expected_public_key = open --raw $"($fixture).pub" | str trim

    let public_result = (run-package $root $package [
        "pub"
        "--key-file"
        $fixture
    ])
    require ($public_result.stdout | str contains $expected_public_key) "Packaged pub command did not print the fixture public key"

    let prompt_result = (run-package $root $package [
        "github"
        "add"
        "--type"
        "both"
        "--prompt-only"
        "--key-file"
        $fixture
    ])
    require ($prompt_result.stdout | str contains "gh ssh-key add") "Packaged GitHub prompt is missing the registration command"
    require ($prompt_result.stdout | str contains "--type signing") "Packaged GitHub prompt is missing signing registration"
    require ($prompt_result.stdout | str contains "--type authentication") "Packaged GitHub prompt is missing authentication registration"
    let expected_fingerprint = short-public-key-fingerprint $"($fixture).pub"
    let expected_machine_name = local-machine-name
    require ($prompt_result.stdout | str contains $expected_fingerprint) "Packaged GitHub prompt is missing the public-key fingerprint in its title"
    require ($prompt_result.stdout | str contains $expected_machine_name) "Packaged GitHub prompt is missing the macOS machine name in its title"
    require (
        not ($prompt_result.stdout | str contains "--title 'nix-secure-enclave-key'")
    ) "Packaged GitHub prompt still uses the static default title"

    let explicit_title_result = (run-package $root $package [
        "github"
        "add"
        "--type"
        "signing"
        "--prompt-only"
        "--title"
        "custom-title"
        "--key-file"
        $fixture
    ])
    require ($explicit_title_result.stdout | str contains "--title 'custom-title'") "Packaged GitHub prompt does not preserve an explicit title"

    let prefixed_title_result = (run-package $root $package [
        "github"
        "add"
        "--type"
        "signing"
        "--prompt-only"
        "--title-prefix"
        "git-signing"
        "--key-file"
        $fixture
    ])
    require ($prefixed_title_result.stdout | str contains "git-signing-") "Packaged GitHub prompt does not include the title prefix"
    require ($prefixed_title_result.stdout | str contains "-nix-secure-enclave-key'") "Packaged GitHub prompt does not include the package title suffix"

    let doctor_result = (run-package $root $package [
        "doctor"
        "--key-file"
        $fixture
    ])
    require ($doctor_result.stdout | str contains "SecurityKeyProvider") "Packaged doctor command did not inspect the SSH provider"

    print "Packaged macOS E2E tests passed"
}
