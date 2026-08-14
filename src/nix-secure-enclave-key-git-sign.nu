#!/usr/bin/env nu

const security_key_provider = "/usr/lib/ssh-keychain.dylib"
const ssh_add_path = "/usr/bin/ssh-add"
const ssh_agent_path = "/usr/bin/ssh-agent"
const ssh_keygen_path = "/usr/bin/ssh-keygen"

def require-macos [] {
    if $nu.os-info.name != "macos" {
        error make {msg: "nix-secure-enclave-key-git-sign requires macOS"}
    }
}

def public-reference-key-file [arguments: list<string>]: nothing -> string {
    let file_options = $arguments | enumerate | where {|item| $item.item == "-f"}
    if ($file_options | is-empty) {
        return ""
    }

    let file_index = $file_options.0.index + 1
    if $file_index >= ($arguments | length) {
        return ""
    }

    let key_file = $arguments | get $file_index
    if not ($key_file | path exists) {
        return ""
    }

    let first_line = (
        open --raw $key_file
        | lines
        | where {|line| not ($line | str trim | is-empty)}
        | first
        | str trim
    )
    let fields = $first_line | split row " " | where {|field| not ($field | is-empty)}
    let public_reference = (
        ($fields | length) >= 2
        and ($fields.0 | str starts-with "sk-")
        and ($"($key_file).pub" | path exists)
    )
    if not $public_reference {
        return ""
    }

    $key_file
}

def agent-variable [output: string, name: string]: nothing -> string {
    let matches = $output | lines | where {|line| $line | str starts-with $"($name)="}
    if ($matches | is-empty) {
        error make {msg: $"ssh-agent did not report ($name)"}
    }
    let fields = (
        $matches.0
        | split row ";"
        | first
        | split row "="
    )
    if ($fields | length) < 2 {
        error make {msg: $"could not parse ($name) from ssh-agent"}
    }
    $fields | skip 1 | str join "="
}

def start-ssh-agent []: nothing -> record {
    let result = (^$ssh_agent_path "-s" | complete)
    if $result.exit_code != 0 {
        let detail = $result.stderr | str trim
        let message = if ($detail | is-empty) {
            "ssh-agent could not be started"
        } else {
            $"ssh-agent could not be started: ($detail)"
        }
        error make {msg: $message}
    }
    let output = $result.stdout
    {
        socket: (agent-variable $output "SSH_AUTH_SOCK")
        pid: (agent-variable $output "SSH_AGENT_PID" | into int)
    }
}

def stop-ssh-agent [agent: record]: nothing -> nothing {
    with-env {
        SSH_AUTH_SOCK: $agent.socket
        SSH_AGENT_PID: ($agent.pid | into string)
    } {
        ^$ssh_agent_path "-k" | complete | ignore
    } | ignore
}

# ssh-keygen can sign from a public reference when the matching resident key is
# loaded in an agent; the disposable agent avoids changing the user's agent.
def run-with-public-reference-agent [arguments: list<string>]: nothing -> nothing {
    let agent = (start-ssh-agent)
    let environment = {
        SSH_AUTH_SOCK: $agent.socket
        SSH_AGENT_PID: ($agent.pid | into string)
        SSH_SK_PROVIDER: $security_key_provider
    }
    let add_result = (with-env $environment {
        ^$ssh_add_path "-K" | complete
    })
    if $add_result.exit_code != 0 {
        stop-ssh-agent $agent
        let detail = $add_result.stderr | str trim
        let message = if ($detail | is-empty) {
            "ssh-add could not load Secure Enclave identities for signing"
        } else {
            $"ssh-add could not load Secure Enclave identities for signing: ($detail)"
        }
        error make {msg: $message}
    }

    let result = (with-env $environment {
        ^$ssh_keygen_path ...$arguments | complete
    })
    stop-ssh-agent $agent
    if not ($result.stdout | is-empty) {
        print --no-newline --raw $result.stdout
    }
    if not ($result.stderr | is-empty) {
        print --no-newline --raw --stderr $result.stderr
    }
    if $result.exit_code != 0 {
        exit $result.exit_code
    }
}

def --wrapped main [...arguments: string] {
    require-macos
    let public_reference = public-reference-key-file $arguments
    if not ($public_reference | is-empty) {
        run-with-public-reference-agent $arguments
    } else {
        with-env {SSH_SK_PROVIDER: $security_key_provider} {
            ^$ssh_keygen_path ...$arguments
        }
    }
}
