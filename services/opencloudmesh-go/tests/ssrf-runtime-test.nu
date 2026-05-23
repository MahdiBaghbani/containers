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

# Unit tests for ssrf-runtime.nu helpers.
# Run: nu tests/ssrf-runtime-test.nu
# All tests pass silently; any failure prints a message and exits non-zero.

use ../scripts/lib/ssrf-runtime.nu [
    parse_peer_hosts
    parse_suffixes
    write_ssrf_runtime_partial
    inject_ssrf_route_policy
    cleanup_ssrf_runtime_state
]
use ../scripts/lib/merge-partials-ocmgo.nu [merge_partial_configs]

def assert_eq [label: string, got: any, want: any] {
    if $got != $want {
        error make {
            msg: $"FAIL [$label]: got ($got | to nuon), want ($want | to nuon)"
        }
    }
}

def assert_contains [label: string, haystack: string, needle: string] {
    if not ($haystack | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected to find ($needle | to nuon) in:\n($haystack)"
        }
    }
}

def assert_not_contains [label: string, haystack: string, needle: string] {
    if ($haystack | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected NOT to find ($needle | to nuon) in:\n($haystack)"
        }
    }
}

def assert_throws_contains [label: string, thunk: closure, needle: string] {
    let err = (try {
        do $thunk
        null
    } catch {|caught|
        $caught
    })

    if $err == null {
        error make {
            msg: $"FAIL [$label]: expected error containing ($needle | to nuon), got none"
        }
    }

    let msg = (try { $err.msg } catch { $err | into string })
    if not ($msg | str contains $needle) {
        error make {
            msg: $"FAIL [$label]: expected error containing ($needle | to nuon), got ($msg | to nuon)"
        }
    }
}

# --- parse_peer_hosts ---

def test_parse_peer_hosts_empty [] {
    let r = (parse_peer_hosts "")
    assert_eq "parse_peer_hosts empty" ($r | length) 0
}

def test_parse_peer_hosts_single [] {
    let r = (parse_peer_hosts "nextcloud.docker")
    assert_eq "parse_peer_hosts single length" ($r | length) 1
    assert_eq "parse_peer_hosts single value" ($r | get 0) "nextcloud.docker"
}

def test_parse_peer_hosts_with_port [] {
    let r = (parse_peer_hosts "nextcloud.docker:443")
    assert_eq "parse_peer_hosts port-strip length" ($r | length) 1
    assert_eq "parse_peer_hosts port stripped" ($r | get 0) "nextcloud.docker"
}

def test_parse_peer_hosts_rejects_non_443_port [] {
    (assert_throws_contains
        "parse_peer_hosts rejects non-443 port"
        {|| parse_peer_hosts "nextcloud.docker:8443" }
        "only host or host:443 is allowed")
}

def test_parse_peer_hosts_multi [] {
    let r = (parse_peer_hosts "host1.docker,host2.docker:443, host3.docker ")
    assert_eq "parse_peer_hosts multi length" ($r | length) 3
    assert_eq "parse_peer_hosts multi[0]" ($r | get 0) "host1.docker"
    assert_eq "parse_peer_hosts multi[1]" ($r | get 1) "host2.docker"
    assert_eq "parse_peer_hosts multi[2] trimmed" ($r | get 2) "host3.docker"
}

def test_parse_peer_hosts_whitespace_only [] {
    let r = (parse_peer_hosts "   ")
    assert_eq "parse_peer_hosts whitespace-only" ($r | length) 0
}

# --- parse_suffixes ---

def test_parse_suffixes_empty [] {
    let r = (parse_suffixes "")
    assert_eq "parse_suffixes empty" ($r | length) 0
}

def test_parse_suffixes_single [] {
    let r = (parse_suffixes ".docker")
    assert_eq "parse_suffixes single length" ($r | length) 1
    assert_eq "parse_suffixes single value" ($r | get 0) ".docker"
}

def test_parse_suffixes_multi [] {
    let r = (parse_suffixes ".docker, .local ,example.com")
    assert_eq "parse_suffixes multi length" ($r | length) 3
    assert_eq "parse_suffixes multi[0]" ($r | get 0) ".docker"
    assert_eq "parse_suffixes multi[1]" ($r | get 1) ".local"
    assert_eq "parse_suffixes multi[2]" ($r | get 2) "example.com"
}

# --- write_ssrf_runtime_partial ---

def test_write_ssrf_runtime_partial_content [] {
    let tmp = (^mktemp -d)
    let path = $"($tmp)/99-runtime-ssrf.toml"

    write_ssrf_runtime_partial $path [".docker" ".local"] ["1.2.3.4/32" "::1/128"]

    let content = (open --raw $path)

    assert_contains "partial has target section" $content "[target]"
    assert_contains "partial target file" $content "file = \"config.toml\""
    assert_contains "partial route_policies header" $content "[outbound_http.ssrf.route_policies.runtime]"
    assert_contains "partial suffixes" $content "allow_private_host_suffixes"
    assert_contains "partial .docker suffix" $content "\".docker\""
    assert_contains "partial .local suffix" $content "\".local\""
    assert_contains "partial cidrs" $content "allow_private_cidrs"
    assert_contains "partial ipv4 cidr" $content "\"1.2.3.4/32\""
    assert_contains "partial ipv6 cidr" $content "\"::1/128\""
    assert_contains "partial allowed_ports" $content "allowed_ports = [443]"
    assert_contains "partial allow_ip_literals" $content "allow_ip_literals = false"

    # Must NOT redefine the parent table
    assert_not_contains "partial no ssrf table header" $content "[outbound_http.ssrf]\n"

    ^rm -rf $tmp
}

def test_write_ssrf_runtime_partial_creates_dir [] {
    let tmp = (^mktemp -d)
    let nested = $"($tmp)/a/b/partial"
    let path = $"($nested)/99-runtime-ssrf.toml"

    write_ssrf_runtime_partial $path [".docker"] ["1.2.3.4/32"]

    if not ($path | path exists) {
        error make {msg: "FAIL [write creates nested dir]: file not found after write"}
    }

    ^rm -rf $tmp
}

def test_write_ssrf_runtime_partial_rejects_empty_suffixes [] {
    let tmp = (^mktemp -d)
    let path = $"($tmp)/99-runtime-ssrf.toml"

    let caught = (try {
        write_ssrf_runtime_partial $path [] ["1.2.3.4/32"]
        false
    } catch {
        true
    })

    if not $caught {
        error make {msg: "FAIL [write empty suffixes]: expected error, got none"}
    }

    ^rm -rf $tmp
}

def test_write_ssrf_runtime_partial_rejects_empty_cidrs [] {
    let tmp = (^mktemp -d)
    let path = $"($tmp)/99-runtime-ssrf.toml"

    let caught = (try {
        write_ssrf_runtime_partial $path [".docker"] []
        false
    } catch {
        true
    })

    if not $caught {
        error make {msg: "FAIL [write empty cidrs]: expected error, got none"}
    }

    ^rm -rf $tmp
}

# --- runtime cleanup and route policy injection ---

def make_sample_config []: nothing -> string {
    [
        "mode = \"strict\""
        "compatibility_scope = \"none\""
        "listen_addr = \":443\""
        ""
        "[outbound_http.ssrf]"
        "mode = \"strict\""
        "redirect_mode = \"same-host\""
        "dns_resolution = \"all-records\""
        ""
        "[tls]"
        "mode = \"static\""
        "cert_file = \"/tls/ocmgo.crt\""
        "key_file = \"/tls/ocmgo.key\""
    ] | str join "\n"
}

def test_inject_ssrf_route_policy_adds_key [] {
    let tmp = (^mktemp -d)
    let cfg = $"($tmp)/config.toml"

    make_sample_config | save -f $cfg

    inject_ssrf_route_policy $cfg

    let content = (open --raw $cfg)
    assert_contains "inject adds route_policy" $content "route_policy = \"runtime\""

    # The key must appear inside the [outbound_http.ssrf] section,
    # i.e. before the [tls] header.
    let ssrf_idx = ($content | str index-of "[outbound_http.ssrf]")
    let tls_idx = ($content | str index-of "[tls]")
    let rp_idx = ($content | str index-of "route_policy")

    if ($rp_idx <= $ssrf_idx) {
        error make {msg: "FAIL [inject position]: route_policy appears before [outbound_http.ssrf]"}
    }
    if ($rp_idx >= $tls_idx) {
        error make {msg: "FAIL [inject position]: route_policy appears after [tls], not inside [outbound_http.ssrf]"}
    }

    ^rm -rf $tmp
}

def test_inject_ssrf_route_policy_idempotent [] {
    let tmp = (^mktemp -d)
    let cfg = $"($tmp)/config.toml"

    make_sample_config | save -f $cfg

    inject_ssrf_route_policy $cfg
    inject_ssrf_route_policy $cfg  # second call must not duplicate

    let content = (open --raw $cfg)

    # Count occurrences: split on the key and subtract 1
    let occurrences = ($content | split row "route_policy" | length) - 1
    if $occurrences != 1 {
        error make {
            msg: $"FAIL [inject idempotent]: route_policy appears ($occurrences) time(s), expected 1"
        }
    }

    ^rm -rf $tmp
}

def test_inject_ssrf_route_policy_missing_section [] {
    let tmp = (^mktemp -d)
    let cfg = $"($tmp)/config.toml"

    "mode = \"strict\"\n" | save -f $cfg

    let caught = (try {
        inject_ssrf_route_policy $cfg
        false
    } catch {
        true
    })

    if not $caught {
        error make {msg: "FAIL [inject missing section]: expected error for missing [outbound_http.ssrf]"}
    }

    ^rm -rf $tmp
}

def make_config_with_runtime_state []: nothing -> string {
    [
        'mode = "strict"'
        'compatibility_scope = "none"'
        'listen_addr = ":443"'
        ""
        "[outbound_http.ssrf]"
        'route_policy = "runtime"'
        'mode = "strict"'
        'redirect_mode = "same-host"'
        'dns_resolution = "all-records"'
        ""
        "[tls]"
        'mode = "static"'
        'cert_file = "/tls/ocmgo.crt"'
        'key_file = "/tls/ocmgo.key"'
        ""
        "[outbound_http.ssrf.route_policies.runtime]"
        'allow_private_host_suffixes = [".docker"]'
        'allow_private_cidrs = ["127.0.0.1/32"]'
        "allowed_ports = [443]"
        "allow_ip_literals = false"
        ""
    ] | str join "\n"
}

def test_cleanup_ssrf_runtime_state_removes_runtime_only_state [] {
    let tmp = (^mktemp -d)
    let cfg = $"($tmp)/config.toml"
    let partial = $"($tmp)/partial/99-runtime-ssrf.toml"

    make_config_with_runtime_state | save -f $cfg
    mkdir ($partial | path dirname)
    "stale runtime partial" | save -f $partial

    cleanup_ssrf_runtime_state $cfg $partial

    let content = (open --raw $cfg)
    assert_not_contains "cleanup removes route_policy line" $content 'route_policy = "runtime"'
    assert_not_contains "cleanup removes runtime block" $content "[outbound_http.ssrf.route_policies.runtime]"
    assert_contains "cleanup preserves strict mode" $content 'mode = "strict"'
    assert_contains "cleanup preserves tls section" $content "[tls]"

    if ($partial | path exists) {
        error make {msg: "FAIL [cleanup removes partial]: stale runtime partial still exists"}
    }

    ^rm -rf $tmp
}

def test_cleanup_ssrf_runtime_state_is_idempotent [] {
    let tmp = (^mktemp -d)
    let cfg = $"($tmp)/config.toml"
    let partial = $"($tmp)/partial/99-runtime-ssrf.toml"

    make_config_with_runtime_state | save -f $cfg
    mkdir ($partial | path dirname)
    "stale runtime partial" | save -f $partial

    cleanup_ssrf_runtime_state $cfg $partial
    cleanup_ssrf_runtime_state $cfg $partial

    let content = (open --raw $cfg)
    assert_not_contains "cleanup idempotent route_policy line" $content 'route_policy = "runtime"'
    assert_not_contains "cleanup idempotent runtime block" $content "[outbound_http.ssrf.route_policies.runtime]"

    ^rm -rf $tmp
}

# --- merged runtime contract (T5) ---
#
# Verifies that baked config + inject_ssrf_route_policy + write_ssrf_runtime_partial
# + merge_partial_configs produces a TOML document with the expected runtime fields.

def test_merged_runtime_contract [] {
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($tmp)/configs/partial"
    let cfg = $"($cfg_dir)/config.toml"
    let partial = $"($partial_dir)/99-runtime-ssrf.toml"

    mkdir $cfg_dir
    mkdir $partial_dir

    make_sample_config | save -f $cfg

    inject_ssrf_route_policy $cfg
    write_ssrf_runtime_partial $partial [".docker" ".local"] ["1.2.3.4/32" "::1/128"]
    merge_partial_configs $cfg_dir $partial_dir

    # Must parse as valid TOML without error.
    let parsed = (try {
        open $cfg
    } catch {|err|
        error make {
            msg: $"FAIL [merge valid toml]: failed to parse merged config: (try { $err.msg } catch { $err | into string })"
        }
    })

    # [outbound_http.ssrf] must expose route_policy = "runtime".
    assert_eq "merged route_policy" ($parsed.outbound_http.ssrf.route_policy) "runtime"

    # [outbound_http.ssrf.route_policies.runtime] must be present and correct.
    let rt = $parsed.outbound_http.ssrf.route_policies.runtime

    assert_eq "merged suffixes length" ($rt.allow_private_host_suffixes | length) 2
    assert_eq "merged suffix[0]" ($rt.allow_private_host_suffixes | get 0) ".docker"
    assert_eq "merged suffix[1]" ($rt.allow_private_host_suffixes | get 1) ".local"

    assert_eq "merged cidrs length" ($rt.allow_private_cidrs | length) 2
    assert_eq "merged cidr[0]" ($rt.allow_private_cidrs | get 0) "1.2.3.4/32"
    assert_eq "merged cidr[1]" ($rt.allow_private_cidrs | get 1) "::1/128"

    # Locked values from the partial template.
    assert_eq "merged allowed_ports" ($rt.allowed_ports) [443]
    assert_eq "merged allow_ip_literals" ($rt.allow_ip_literals) false

    ^rm -rf $tmp
}

def main [] {
    test_parse_peer_hosts_empty
    test_parse_peer_hosts_single
    test_parse_peer_hosts_with_port
    test_parse_peer_hosts_rejects_non_443_port
    test_parse_peer_hosts_multi
    test_parse_peer_hosts_whitespace_only

    test_parse_suffixes_empty
    test_parse_suffixes_single
    test_parse_suffixes_multi

    test_write_ssrf_runtime_partial_content
    test_write_ssrf_runtime_partial_creates_dir
    test_write_ssrf_runtime_partial_rejects_empty_suffixes
    test_write_ssrf_runtime_partial_rejects_empty_cidrs

    test_inject_ssrf_route_policy_adds_key
    test_inject_ssrf_route_policy_idempotent
    test_inject_ssrf_route_policy_missing_section
    test_cleanup_ssrf_runtime_state_removes_runtime_only_state
    test_cleanup_ssrf_runtime_state_is_idempotent

    test_merged_runtime_contract

    print "PASS: all ssrf-runtime tests"
}
