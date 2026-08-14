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

def main [root: string] {
    let fixture = $root | path join "tests/fixtures-public-key"
    let expected_public_key = open --raw $"($fixture).pub" | str trim

    let public_result = (run-package $root [
        "pub"
        "--key-file"
        $fixture
    ])
    require ($public_result.stdout | str contains $expected_public_key) "Packaged pub command did not print the fixture public key"

    let prompt_result = (run-package $root [
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

    let doctor_result = (run-package $root [
        "doctor"
        "--key-file"
        $fixture
    ])
    require ($doctor_result.stdout | str contains "SecurityKeyProvider") "Packaged doctor command did not inspect the SSH provider"

    print "Packaged macOS E2E smoke tests passed"
}
