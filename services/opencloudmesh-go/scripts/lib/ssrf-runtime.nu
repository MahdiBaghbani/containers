#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Runtime SSRF route policy helpers for opencloudmesh-go.
#
# TOML constraint note: [outbound_http.ssrf] is explicitly defined in the
# baked config.toml, so appending a second [outbound_http.ssrf] header is
# invalid TOML 1.0. The split strategy is:
#   - inject_ssrf_route_policy patches config.toml in-place to add the
#     route_policy key inside the existing [outbound_http.ssrf] section.
#   - write_ssrf_runtime_partial writes only the
#     [outbound_http.ssrf.route_policies.runtime] sub-table to the partial
#     file, which is appended cleanly by merge_partial_configs.

# Parse one peer host entry from OCM_GO_ROUTE_PEER_HOSTS.
# Locked contract: accept only "host" or "host:443".
def parse_peer_host_entry [entry: string] {
    let trimmed = ($entry | str trim)
    let parts = ($trimmed | split row ":")

    if ($trimmed | str length) == 0 {
        return ""
    }

    if ($parts | length) == 1 {
        return $trimmed
    }

    if ($parts | length) == 2 {
        let host = ($parts | first | str trim)
        let port = ($parts | last | str trim)

        if ($host | str length) == 0 {
            error make {
                msg: $"Invalid peer host entry '($trimmed)': expected host or host:443"
            }
        }

        if $port != "443" {
            error make {
                msg: $"Invalid peer host entry '($trimmed)': only host or host:443 is allowed"
            }
        }

        return $host
    }

    error make {
        msg: $"Invalid peer host entry '($trimmed)': expected host or host:443"
    }
}

# Parse OCM_GO_ROUTE_PEER_HOSTS value into a list of hostnames.
# Input is comma-separated; each entry may be only "host" or "host:443".
export def parse_peer_hosts [env_val: string]: nothing -> list<string> {
    if ($env_val | str trim | str length) == 0 {
        return []
    }

    let entries = ($env_val | split row ",")
    mut hosts = []

    for entry in $entries {
        let host = (parse_peer_host_entry $entry)
        if ($host | str length) > 0 {
            $hosts = ($hosts | append $host)
        }
    }

    $hosts
}

# Parse OCM_GO_ROUTE_SUFFIXES value into a list of domain suffixes.
# Input is comma-separated plain strings.
export def parse_suffixes [env_val: string]: nothing -> list<string> {
    if ($env_val | str trim | str length) == 0 {
        return []
    }

    $env_val
        | split row ","
        | each {|s| $s | str trim}
        | where {|s| ($s | str length) > 0}
}

# Resolve a single hostname to exact-host CIDRs via getent ahosts.
# Returns /32 for IPv4 addresses and /128 for IPv6 addresses.
# Fails clearly if resolution yields no addresses.
export def resolve_cidrs_for_host [hostname: string]: nothing -> list<string> {
    let result = (try {
        ^getent ahosts $hostname | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: "getent not available"}
    })

    if $result.exit_code != 0 {
        error make {
            msg: $"DNS resolution failed for '($hostname)': ($result.stderr | str trim)"
        }
    }

    let ips = ($result.stdout
        | lines
        | where {|line| ($line | str trim | str length) > 0}
        | each {|line|
            $line | str trim | split row --regex '\s+' | first
        }
        | uniq
    )

    if ($ips | is-empty) {
        error make {msg: $"DNS resolution yielded no addresses for '($hostname)'"}
    }

    $ips | each {|ip|
        if ($ip | str contains ":") {
            $"($ip)/128"
        } else {
            $"($ip)/32"
        }
    }
}

# Build the TOML text for the runtime SSRF partial (internal helper).
# Produces a [target] section plus [outbound_http.ssrf.route_policies.runtime].
def build_ssrf_partial_content [
    suffixes: list<string>
    cidrs: list<string>
]: nothing -> string {
    let s_toml = ($suffixes | each {|s| $"\"($s)\""} | str join ", ")
    let c_toml = ($cidrs | each {|c| $"\"($c)\""} | str join ", ")

    [
        "[target]"
        "file = \"config.toml\""
        ""
        "[outbound_http.ssrf.route_policies.runtime]"
        $"allow_private_host_suffixes = [($s_toml)]"
        $"allow_private_cidrs = [($c_toml)]"
        "allowed_ports = [443]"
        "allow_ip_literals = false"
        ""
    ] | str join "\n"
}

# Write the runtime SSRF partial to partial_path.
# Creates parent directories if needed.
# Fails if either list is empty (product validator requires non-empty lists
# for an active route policy under compatibility_scope=none).
export def write_ssrf_runtime_partial [
    partial_path: string
    suffixes: list<string>
    cidrs: list<string>
]: nothing -> nothing {
    if ($suffixes | is-empty) {
        error make {
            msg: "SSRF route policy requires non-empty allow_private_host_suffixes (set OCM_GO_ROUTE_SUFFIXES)"
        }
    }
    if ($cidrs | is-empty) {
        error make {
            msg: "SSRF route policy requires non-empty allow_private_cidrs (peer host DNS yielded nothing)"
        }
    }

    let dir = ($partial_path | path dirname)
    if not ($dir | path exists) {
        mkdir $dir
    }

    let content = (build_ssrf_partial_content $suffixes $cidrs)
    $content | save -f $partial_path
}

def remove_runtime_route_policy_line [config_path: string]: nothing -> nothing {
    let raw = (open --raw $config_path)
    let filtered = ($raw
        | lines
        | where {|line| ($line | str trim) != 'route_policy = "runtime"'}
        | str join "\n"
    )
    $filtered | save -f $config_path
}

def remove_runtime_route_policy_block [config_path: string]: nothing -> nothing {
    let lines = (open --raw $config_path | split row "\n")
    mut result = []
    mut in_runtime_block = false

    for line in $lines {
        let trimmed = ($line | str trim)

        if $in_runtime_block {
            if ($trimmed | str starts-with "[") {
                $in_runtime_block = false
                $result = ($result | append $line)
            }
            continue
        }

        if $trimmed == "[outbound_http.ssrf.route_policies.runtime]" {
            $in_runtime_block = true
            continue
        }

        $result = ($result | append $line)
    }

    $result | str join "\n" | save -f $config_path
}

# Remove runtime-only SSRF state from prior boots.
# This keeps later boots without route envs on the strict base config with no
# active route policy, even on a reused container filesystem.
export def cleanup_ssrf_runtime_state [
    config_path: string
    partial_path: string
]: nothing -> nothing {
    if ($config_path | path exists) {
        remove_runtime_route_policy_line $config_path
        remove_runtime_route_policy_block $config_path
    }

    if ($partial_path | path exists) {
        rm -f $partial_path
    }
}

# Inject route_policy = "runtime" into the [outbound_http.ssrf] section of
# config_path in-place. Idempotent: returns immediately if route_policy
# is already present in the file.
#
# This direct injection is required because [outbound_http.ssrf] is already
# explicitly defined in the baked config; TOML 1.0 forbids reopening it via a
# second [outbound_http.ssrf] header in an appended partial.
export def inject_ssrf_route_policy [config_path: string]: nothing -> nothing {
    if not ($config_path | path exists) {
        error make {msg: $"Config file not found: ($config_path)"}
    }

    let raw = (open --raw $config_path)

    if ($raw | str contains "route_policy") {
        return
    }

    let lines = ($raw | split row "\n")
    mut result = []
    mut injected = false

    for line in $lines {
        $result = ($result | append $line)
        if ((not $injected) and (($line | str trim) == "[outbound_http.ssrf]")) {
            $result = ($result | append "route_policy = \"runtime\"")
            $injected = true
        }
    }

    if not $injected {
        error make {
            msg: "[outbound_http.ssrf] section not found in config; cannot inject route_policy"
        }
    }

    $result | str join "\n" | save -f $config_path
}
