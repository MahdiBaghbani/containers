#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Service-local OAuth handoff wait for JupyterHub.
#
# The sender Nextcloud provisions the hub's OAuth client and writes it to a
# shared file. This preflight blocks the hub boot until that file is present so
# jupyterhub_config.py can resolve NEXTCLOUD_CLIENT_ID/SECRET without crash-loop.

# Env value when set and non-whitespace; otherwise null (treated as unset).
def env-nonempty-value [name: string] {
    try {
        let val = ($env | get $name)
        if ($val | str trim | is-empty) {
            null
        } else {
            $val
        }
    } catch {
        null
    }
}

# True when both client id and secret are already provided directly via env
# (standalone deployments), so no file handoff is needed.
export def oauth-env-creds-present [] {
    let id = (env-nonempty-value "NEXTCLOUD_CLIENT_ID")
    let secret = (env-nonempty-value "NEXTCLOUD_CLIENT_SECRET")
    ($id != null) and ($secret != null)
}

# The configured handoff file path, or null when unset.
export def oauth-handoff-file [] {
    env-nonempty-value "NEXTCLOUD_OAUTH_ENV_FILE"
}

# Parse a simple KEY=VALUE env file into a record. Blank lines and comments are
# ignored; the first '=' splits key from value (values may contain '='); both
# sides are trimmed. Mirrors jupyterhub_helpers.parse_env_file so the Nushell
# readiness gate and the Python resolver agree on what "present" means.
def parse-env-file [path: string] {
    open --raw $path
    | lines
    | each {|raw| $raw | str trim }
    | where {|line| (not ($line | is-empty)) and (not ($line | str starts-with "#")) and ($line | str contains "=") }
    | reduce --fold {} {|line, acc|
        let parts = ($line | split row "=")
        let key = ($parts | first | str trim)
        let val = ($parts | skip 1 | str join "=" | str trim)
        $acc | upsert $key $val
    }
}

# Trimmed value for a key in a parsed env record, or "" when absent.
def env-file-value [values: record, key: string] {
    if ($key in $values) { $values | get $key | str trim } else { "" }
}

# True when the handoff file exists and carries both credential keys with
# non-empty values. Key presence alone is not enough: the Python resolver
# (resolve_oauth_client) rejects blank values, so a name-only match would let
# the hub "pass" preflight and then crash-loop in jupyterhub_config.py.
export def oauth-handoff-ready [oauth_file: string] {
    if not ($oauth_file | path exists) {
        return false
    }
    let values = (parse-env-file $oauth_file)
    let id = (env-file-value $values "INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_ID")
    let secret = (env-file-value $values "INTEGRATION_JUPYTERHUB_OAUTH_CLIENT_SECRET")
    (not ($id | is-empty)) and (not ($secret | is-empty))
}

# Poll for the handoff file until ready or the timeout elapses. Returns bool.
export def wait-for-oauth-handoff [
    oauth_file: string,
    timeout_sec: int,
    interval_sec: int = 2,
] {
    mut waited = 0
    loop {
        if (oauth-handoff-ready $oauth_file) {
            return true
        }
        if $waited >= $timeout_sec {
            return false
        }
        sleep ($interval_sec * 1sec)
        $waited = $waited + $interval_sec
    }
}
