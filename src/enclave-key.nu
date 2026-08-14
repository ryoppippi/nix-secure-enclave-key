#!/usr/bin/env nu

const default_key_file = "~/.ssh/id_enclave_key"
const default_label = "enclave-key"
const default_protection = "none"
const security_key_provider = "/usr/lib/ssh-keychain.dylib"
const sc_auth_path = "/usr/sbin/sc_auth"
const ssh_keygen_path = "/usr/bin/ssh-keygen"
const pbcopy_path = "/usr/bin/pbcopy"

def is-macos []: nothing -> bool {
    $nu.os-info.name == "macos"
}

def require-macos [] {
    if not (is-macos) {
        error make {msg: "Secure Enclave operations require macOS; no changes were made"}
    }
}

def require-protection [protection: string] {
    if $protection != "none" and $protection != "bio" {
        error make {msg: $"protection must be either 'none' or 'bio', got '($protection)'"}
    }
}

def require-label [label: string] {
    if ($label | str trim | is-empty) {
        error make {msg: "label must not be empty"}
    }
}

def run-sc-auth [arguments: list<string>]: nothing -> record {
    ^$sc_auth_path ...$arguments | complete
}

def checked-output [result: record, operation: string]: nothing -> string {
    if $result.exit_code != 0 {
        let detail = $result.stderr | str trim
        let message = if ($detail | is-empty) {
            $"($operation) failed with exit code ($result.exit_code)"
        } else {
            $"($operation) failed: ($detail)"
        }
        error make {msg: $message}
    }

    $result.stdout
}

def list-ssh-identities []: nothing -> string {
    let result = (run-sc-auth ["list-ctk-identities", "-t", "ssh", "-e", "b64"])
    checked-output $result "sc_auth list-ctk-identities"
}

def identity-has-label [identities: string, label: string]: nothing -> bool {
    $identities | str contains $label
}

def create-identity [label: string, protection: string] {
    let result = (run-sc-auth [
        "create-ctk-identity"
        "-l"
        $label
        "-k"
        "p-256-ne"
        "-t"
        $protection
    ])
    checked-output $result "sc_auth create-ctk-identity" | ignore
}

def key-state [key_file: string]: nothing -> record {
    let expanded = $key_file | path expand
    {
        key_file: $expanded
        public_file: $"($expanded).pub"
        private_exists: ($expanded | path exists)
        public_exists: ($"($expanded).pub" | path exists)
    }
}

def require-complete-key-pair [state: record] {
    if $state.private_exists != $state.public_exists {
        error make {msg: $"incomplete SSH stub pair: ($state.key_file) and ($state.public_file) must either both exist or both be absent"}
    }
}

def ensure-parent-directory [file_path: string] {
    let parent = $file_path | path expand | path dirname
    if not ($parent | path exists) {
        mkdir $parent | ignore
    }
}

def temporary-directory []: nothing -> string {
    let result = (^mktemp -d | complete)
    let directory = (checked-output $result "mktemp")
    let expanded = $directory | str trim
    if ($expanded | is-empty) {
        error make {msg: "mktemp returned an empty directory path"}
    }
    $expanded
}

def generated-pairs [directory: string]: nothing -> list<record> {
    let files = ls -a $directory | where type == file
    let public_files = ($files | where {|file|
        $file.name | path basename | str ends-with ".pub"
    })

    $public_files | each {|public_file|
        let private_name = (
            $public_file.name
            | path basename
            | str replace --regex '\.pub$' ""
        )
        let private_files = ($files | where {|file|
            ($file.name | path basename) == $private_name
        })
        if ($private_files | is-empty) {
            null
        } else {
            {
                private_file: ($private_files | first | get name)
                public_file: $public_file.name
            }
        }
    } | where {|pair| $pair != null}
}

def remove-temporary-directory [directory: string] {
    if ($directory | path exists) {
        rm -r $directory | ignore
    }
}

def generate-ssh-stub [key_file: string] {
    let state = (key-state $key_file)
    require-complete-key-pair $state
    if $state.private_exists {
        return
    }

    ensure-parent-directory $state.key_file
    let temporary = (temporary-directory)
    let result = (do {
        cd $temporary
        ^$ssh_keygen_path -w $security_key_provider -K -N "" | complete
    })

    if $result.exit_code != 0 {
        let detail = $result.stderr | str trim
        remove-temporary-directory $temporary
        let message = if ($detail | is-empty) {
            "ssh-keygen could not download a Secure Enclave SSH stub"
        } else {
            $"ssh-keygen could not download a Secure Enclave SSH stub: ($detail)"
        }
        error make {msg: $message}
    }

    let pairs = (generated-pairs $temporary)
    if ($pairs | length) != 1 {
        remove-temporary-directory $temporary
        error make {msg: $"ssh-keygen returned ($pairs | length) SSH stub pairs; exactly one was required"}
    }

    let pair = $pairs | first
    mv $pair.private_file $state.key_file
    mv $pair.public_file $state.public_file
    chmod 600 $state.key_file
    chmod 644 $state.public_file
    remove-temporary-directory $temporary
}

def ensure-configuration [key_file: string, label: string, protection: string]: nothing -> record {
    require-macos
    require-label $label
    require-protection $protection

    let state = (key-state $key_file)
    require-complete-key-pair $state

    let identities = (list-ssh-identities)
    let identity_created = if (identity-has-label $identities $label) {
        false
    } else {
        create-identity $label $protection
        true
    }

    let ssh_created = if $state.private_exists {
        false
    } else {
        generate-ssh-stub $state.key_file
        true
    }

    {
        key_file: $state.key_file
        public_file: $state.public_file
        label: $label
        identity_created: $identity_created
        ssh_created: $ssh_created
        protection: $protection
    }
}

def parse-public-key [contents: string]: nothing -> record {
    let line = (
        $contents
        | lines
        | where {|item| not ($item | str trim | is-empty)}
        | first
        | str trim
    )
    let fields = $line | split row " " | where {|item| not ($item | is-empty)}
    if ($fields | length) < 2 {
        error make {msg: "public key file does not contain an SSH algorithm and key body"}
    }

    {
        line: $line
        algorithm: ($fields | get 0)
        key_data: ($fields | get 1)
    }
}

def read-public-key [key_file: string]: nothing -> record {
    let state = (key-state $key_file)
    if not $state.public_exists {
        error make {msg: $"public key not found: ($state.public_file); run 'enclave-key setup' first"}
    }
    parse-public-key (open --raw $state.public_file)
}

def print-setup-result [result: record] {
    if $result.identity_created {
        print $"Created Secure Enclave identity '($result.label)'"
    } else {
        print "Secure Enclave identity already exists"
    }

    if $result.ssh_created {
        print $"Created SSH stub at ($result.key_file)"
    } else {
        print $"SSH stub already exists at ($result.key_file)"
    }

    if $result.protection == "bio" {
        print "The bio protection mode may require Touch ID when the key is used."
    }
    print $"Public key: ($result.public_file)"
}

def print-doctor-check [name: string, status: string, detail: string] {
    print $"[($status)] ($name): ($detail)"
}

def "main setup" [--key-file: string = "~/.ssh/id_enclave_key", --label: string = "enclave-key", --protection: string = "none"] {
    if not (is-macos) {
        print "enclave-key setup skipped: Secure Enclave operations require macOS"
        return
    }
    let result = (ensure-configuration $key_file $label $protection)
    print-setup-result $result
}

def "main identity ensure" [--key-file: string = "~/.ssh/id_enclave_key", --label: string = "enclave-key", --protection: string = "none"] {
    if not (is-macos) {
        print "enclave-key identity ensure skipped: Secure Enclave operations require macOS"
        return
    }
    let result = (ensure-configuration $key_file $label $protection)
    print-setup-result $result
}

def "main identity list" [] {
    if not (is-macos) {
        print "enclave-key identity list skipped: Secure Enclave operations require macOS"
        return
    }
    print (
        checked-output (run-sc-auth ["list-ctk-identities", "-e", "b64"]) "sc_auth list-ctk-identities"
    )
}

def "main ssh ensure" [--key-file: string = "~/.ssh/id_enclave_key", --label: string = "enclave-key", --protection: string = "none"] {
    if not (is-macos) {
        print "enclave-key ssh ensure skipped: Secure Enclave operations require macOS"
        return
    }
    let result = (ensure-configuration $key_file $label $protection)
    print-setup-result $result
}

def "main pub" [--key-file: string = "~/.ssh/id_enclave_key", --copy] {
    let public_key = (read-public-key $key_file)
    if $copy {
        if not (is-macos) or not ($pbcopy_path | path exists) {
            error make {msg: "--copy requires macOS pbcopy"}
        }
        ($public_key.line + "\n") | ^$pbcopy_path | complete | ignore
        print "Copied the public key to the clipboard."
    } else {
        print $public_key.line
    }
}

def "main ctk csr" [identity_hash: string, output_file: string] {
    require-macos
    let result = (run-sc-auth [
        "create-ctk-csr"
        "-h"
        $identity_hash
        "-f"
        ($output_file | path expand)
    ])
    checked-output $result "sc_auth create-ctk-csr" | print
}

def "main ctk import-certificate" [certificate_file: string] {
    require-macos
    let result = (run-sc-auth [
        "import-ctk-certificate"
        "-f"
        ($certificate_file | path expand)
    ])
    checked-output $result "sc_auth import-ctk-certificate" | print
}

def shell-quote [value: string]: nothing -> string {
    let escaped = $value | str replace --all "'" "'\\''"
    $"'($escaped)'"
}

def github-endpoint [key_type: string]: nothing -> string {
    match $key_type {
        signing => "/user/ssh_signing_keys"
        authentication => "/user/keys"
        _ => (error make {msg: $"unsupported GitHub key type: ($key_type)"})
    }
}

def is-list-value [value]: nothing -> bool {
    ($value | describe) | str starts-with "list"
}

def flatten-github-pages [payload]: nothing -> list<any> {
    if not (is-list-value $payload) {
        return []
    }

    $payload | flatten
}

def github-key-list [endpoint: string]: nothing -> record {
    if (which gh | is-empty) {
        return {
            available: false
            keys: []
        }
    }

    let response = (^gh api $endpoint --paginate --slurp | complete)
    if $response.exit_code != 0 {
        return {
            available: false
            keys: []
        }
    }

    let payload = (try {
        $response.stdout | from json
    } catch {
        null
    })
    if $payload == null {
        return {
            available: false
            keys: []
        }
    }

    {
        available: true
        keys: (flatten-github-pages $payload)
    }
}

def github-key-matches [entry: record, expected: record]: nothing -> bool {
    let remote_key = (try {
        $entry.key
    } catch {
        ""
    })
    let remote_text = $remote_key | default "" | str trim
    if $remote_text == $expected.key_data {
        return true
    }

    let fields = $remote_text | split row " " | where {|item| not ($item | is-empty)}
    if ($fields | length) < 2 {
        false
    } else {
        ($fields | get 0) == $expected.algorithm and ($fields | get 1) == $expected.key_data
    }
}

def registration-prompt [public_file: string, key_type: string, title: string] {
    let quoted_file = (shell-quote $public_file)
    let quoted_title = (shell-quote $title)
    print "この公開鍵をGitHubへ登録してください。"
    print "秘密鍵はSecure Enclave内にあり、取得・コピーしてはいけません。"
    print $"gh ssh-key add ($quoted_file) --type ($key_type) --title ($quoted_title)"
}

def register-github-key [
    public_file: string
    public_key: record
    key_type: string
    title: string
]: nothing -> string {
    let endpoint = (github-endpoint $key_type)
    let result = (github-key-list $endpoint)
    if not $result.available {
        registration-prompt $public_file $key_type $title
        return "prompted"
    }

    let exists = ($result.keys | any {|entry|
        github-key-matches $entry $public_key
    })
    if $exists {
        print $"GitHub already has this ($key_type) key; skipped."
        return "skipped"
    }

    let response = (^gh ssh-key add $public_file --type $key_type --title $title | complete)
    if $response.exit_code != 0 {
        registration-prompt $public_file $key_type $title
        return "prompted"
    }

    print $"Registered the public key as a GitHub ($key_type) key."
    "added"
}

def require-github-type [key_type: string] {
    if $key_type != "signing" and $key_type != "authentication" and $key_type != "both" {
        error make {msg: "type must be signing, authentication, or both"}
    }
}

def "main github add" [
    --type: string = "both"
    --title: string = "enclave-key"
    --key-file: string = "~/.ssh/id_enclave_key"
    --prompt-only
] {
    require-github-type $type
    let public_state = (key-state $key_file)
    let public_key = (read-public-key $key_file)
    let key_types = if $type == "both" {
        ["signing", "authentication"]
    } else {
        [$type]
    }

    $key_types | each {|key_type|
        if $prompt_only {
            registration-prompt $public_state.public_file $key_type $title
            "prompted"
        } else {
            register-github-key $public_state.public_file $public_key $key_type $title
        }
    } | ignore
}

def "main doctor" [--key-file: string = "~/.ssh/id_enclave_key"] {
    if not (is-macos) {
        print "[skip] Secure Enclave: macOS is required"
        return
    }

    let sc_auth_available = $sc_auth_path | path exists
    let ssh_keygen_available = $ssh_keygen_path | path exists
    let provider_available = $security_key_provider | path exists
    let state = (key-state $key_file)

    (print-doctor-check
        "sc_auth"
        (if $sc_auth_available { "ok" } else { "missing" })
        $sc_auth_path
    )
    (print-doctor-check
        "ssh-keygen"
        (if $ssh_keygen_available { "ok" } else { "missing" })
        $ssh_keygen_path
    )
    (print-doctor-check
        "SecurityKeyProvider"
        (if $provider_available { "ok" } else { "missing" })
        $security_key_provider
    )
    (print-doctor-check
        "SSH private stub"
        (if $state.private_exists { "ok" } else { "missing" })
        $state.key_file
    )
    (print-doctor-check
        "SSH public key"
        (if $state.public_exists { "ok" } else { "missing" })
        $state.public_file
    )

    if $sc_auth_available {
        let result = (run-sc-auth ["list-ctk-identities", "-t", "ssh", "-e", "b64"])
        if $result.exit_code == 0 {
            let identity_lines = $result.stdout | lines | length
            (print-doctor-check
                "CTK SSH identities"
                "ok"
                $"($identity_lines) output lines"
            )
        } else {
            (print-doctor-check
                "CTK SSH identities"
                "error"
                "sc_auth could not list identities"
            )
        }
    }

    if $state.private_exists != $state.public_exists {
        (print-doctor-check
            "SSH stub pair"
            "error"
            "private and public files are incomplete"
        )
    } else if $state.private_exists {
        (print-doctor-check
            "SSH stub pair"
            "ok"
            "private and public files are present"
        )
    } else {
        print-doctor-check "SSH stub pair" "missing" "run enclave-key setup"
    }
}

def main [] {
    print "Usage: enclave-key <setup|identity|ssh|pub|github|ctk|doctor>"
    print "Run 'enclave-key <command> --help' for command details."
}
