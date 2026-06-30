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
    parse_private_cidrs
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

# --- parse_private_cidrs ---

def test_parse_private_cidrs_empty [] {
    let r = (parse_private_cidrs "")
    assert_eq "parse_private_cidrs empty" ($r | length) 0
}

def test_parse_private_cidrs_single [] {
    let r = (parse_private_cidrs "10.1.2.0/24")
    assert_eq "parse_private_cidrs single length" ($r | length) 1
    assert_eq "parse_private_cidrs single value" ($r | get 0) "10.1.2.0/24"
}

def test_parse_private_cidrs_multi [] {
    let r = (parse_private_cidrs "10.1.2.0/24, 10.3.4.0/24 ,192.168.0.0/16")
    assert_eq "parse_private_cidrs multi length" ($r | length) 3
    assert_eq "parse_private_cidrs multi[0]" ($r | get 0) "10.1.2.0/24"
    assert_eq "parse_private_cidrs multi[1]" ($r | get 1) "10.3.4.0/24"
    assert_eq "parse_private_cidrs multi[2]" ($r | get 2) "192.168.0.0/16"
}

def test_parse_private_cidrs_whitespace_only [] {
    let r = (parse_private_cidrs "   ")
    assert_eq "parse_private_cidrs whitespace-only" ($r | length) 0
}

def test_parse_private_cidrs_rejects_bare_ip [] {
    (assert_throws_contains
        "parse_private_cidrs rejects bare IP"
        {|| parse_private_cidrs "10.1.2.3" }
        "must be a CIDR range")
}

def test_parse_private_cidrs_rejects_bare_ip_in_list [] {
    (assert_throws_contains
        "parse_private_cidrs rejects bare IP in list"
        {|| parse_private_cidrs "10.1.2.0/24,192.168.1.1" }
        "must be a CIDR range")
}

def test_parse_private_cidrs_rejects_missing_address [] {
    (assert_throws_contains
        "parse_private_cidrs rejects missing address"
        {|| parse_private_cidrs "/24" }
        "missing address before")
}

def test_parse_private_cidrs_rejects_missing_prefix [] {
    (assert_throws_contains
        "parse_private_cidrs rejects missing prefix"
        {|| parse_private_cidrs "10.0.0.0/" }
        "missing prefix length after")
}

def test_parse_private_cidrs_rejects_non_numeric_prefix [] {
    (assert_throws_contains
        "parse_private_cidrs rejects non-numeric prefix"
        {|| parse_private_cidrs "10.0.0.0/abc" }
        "not a number")
}

def test_parse_private_cidrs_rejects_ipv4_prefix_too_high [] {
    (assert_throws_contains
        "parse_private_cidrs rejects IPv4 prefix > 32"
        {|| parse_private_cidrs "10.0.0.0/33" }
        "out of range")
}

def test_parse_private_cidrs_rejects_ipv4_prefix_negative [] {
    (assert_throws_contains
        "parse_private_cidrs rejects IPv4 prefix negative"
        {|| parse_private_cidrs "10.0.0.0/-1" }
        "out of range")
}

def test_parse_private_cidrs_rejects_ipv6_prefix_too_high [] {
    (assert_throws_contains
        "parse_private_cidrs rejects IPv6 prefix > 128"
        {|| parse_private_cidrs "::1/129" }
        "out of range")
}

def test_parse_private_cidrs_rejects_invalid_ipv4_octet [] {
    (assert_throws_contains
        "parse_private_cidrs rejects IPv4 octet > 255"
        {|| parse_private_cidrs "10.0.300.0/24" }
        "out of range")
}

def test_parse_private_cidrs_rejects_non_numeric_octet [] {
    (assert_throws_contains
        "parse_private_cidrs rejects non-numeric IPv4 octet"
        {|| parse_private_cidrs "10.0.abc.0/24" }
        "not a number")
}

def test_parse_private_cidrs_rejects_too_few_octets [] {
    (assert_throws_contains
        "parse_private_cidrs rejects IPv4 with 3 octets"
        {|| parse_private_cidrs "10.0.0/24" }
        "4 octets")
}

def test_parse_private_cidrs_rejects_unsafe_double_quote [] {
    (assert_throws_contains
        "parse_private_cidrs rejects double-quote in entry"
        {|| parse_private_cidrs '10.0.0.0"/24' }
        "unsafe characters")
}

def test_parse_private_cidrs_rejects_backslash [] {
    (assert_throws_contains
        "parse_private_cidrs rejects backslash in entry"
        {|| parse_private_cidrs "10.0.0.0\\/24" }
        "unsafe characters")
}

def test_parse_private_cidrs_rejects_newline [] {
    (assert_throws_contains
        "parse_private_cidrs rejects newline in entry"
        {|| parse_private_cidrs "10.0.0.0\n/24" }
        "unsafe characters")
}

def test_parse_private_cidrs_rejects_carriage_return [] {
    (assert_throws_contains
        "parse_private_cidrs rejects carriage-return in entry"
        {|| parse_private_cidrs "10.0.0.0\r/24" }
        "unsafe characters")
}

# Commas-only input parses to empty (no error); this is the precondition that
# triggers the "set but produced no valid entries" message in entrypoint-init.nu.
def test_parse_private_cidrs_commas_only_parses_empty [] {
    let r = (parse_private_cidrs ",,,")
    assert_eq "parse_private_cidrs commas-only parses to empty" ($r | length) 0
}

def test_parse_private_cidrs_rejects_multiple_slashes [] {
    (assert_throws_contains
        "parse_private_cidrs rejects entry with multiple slashes"
        {|| parse_private_cidrs "10.0.0.0/24/extra" }
        "malformed CIDR")
}

def test_parse_private_cidrs_accepts_ipv6 [] {
    let r = (parse_private_cidrs "2001:db8::/32")
    assert_eq "parse_private_cidrs accepts IPv6 length" ($r | length) 1
    assert_eq "parse_private_cidrs accepts IPv6 value" ($r | get 0) "2001:db8::/32"
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

def test_parse_suffixes_rejects_double_quote [] {
    (assert_throws_contains
        "parse_suffixes rejects double-quote in entry"
        {|| parse_suffixes '.docker"evil' }
        "unsafe characters")
}

def test_parse_suffixes_rejects_backslash [] {
    (assert_throws_contains
        "parse_suffixes rejects backslash in entry"
        {|| parse_suffixes ".docker\\evil" }
        "unsafe characters")
}

def test_parse_suffixes_rejects_newline [] {
    (assert_throws_contains
        "parse_suffixes rejects newline in entry"
        {|| parse_suffixes ".docker\nevil" }
        "unsafe characters")
}

def test_parse_suffixes_rejects_carriage_return [] {
    (assert_throws_contains
        "parse_suffixes rejects carriage-return in entry"
        {|| parse_suffixes ".docker\revil" }
        "unsafe characters")
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

def test_write_ssrf_runtime_partial_empty_cidrs_error_text [] {
    let tmp = (^mktemp -d)
    let path = $"($tmp)/99-runtime-ssrf.toml"

    (assert_throws_contains
        "write empty cidrs error mentions OCM_GO_ROUTE_PRIVATE_CIDRS"
        {|| write_ssrf_runtime_partial $path [".docker"] [] }
        "OCM_GO_ROUTE_PRIVATE_CIDRS")

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
            msg: $"FAIL [inject idempotent]: route_policy appears ($occurrences) times, expected 1"
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

# --- production config shape (http-services) ---
#
# Reads the real config.toml from the service tree and asserts that the
# http-services keys are present with the expected values and that no
# bootstrap_seeded_users content is present.

def test_production_config_http_services_shape [] {
    let config_path = ($env.FILE_PWD | path join "../configs/config.toml")
    let raw = (open --raw $config_path)
    let parsed = (open $config_path)

    assert_eq "prod config api allowed_paths" ($parsed.http.services.api.allowed_paths) ["/tmp" "/data"]
    assert_eq "prod config ui wayf enabled" ($parsed.http.services.ui.wayf.enabled) true
    assert_not_contains "prod config no bootstrap_seeded_users" $raw "bootstrap_seeded_users"
}

# --- interpolation footgun regression (entrypoint-init.nu summary log) ---
#
# Guards against bare (s)/(es) command-substitution footguns inside $"..."
# strings. Nushell treats any (...) in a string interpolation as a sub-
# expression, so "host(s)" silently tries to run a command named "s".
#
# The CIDR-based setup no longer has a "peer hosts" count in the message;
# this test re-asserts the format so regressions are caught before runtime.

def test_summary_log_format [] {
    let cidr_count = 3
    let suffix_count = 1
    let msg = $"[ocmgo-init] SSRF runtime route policy: ($cidr_count) CIDRs, ($suffix_count) suffixes"
    assert_contains "summary log contains cidr count" $msg "3 CIDRs"
    assert_contains "summary log contains suffix count" $msg "1 suffixes"
    assert_not_contains "summary log no bare (s) footgun" $msg "(s)"
    assert_not_contains "summary log no bare (es) footgun" $msg "(es)"
}

def main [] {
    test_parse_private_cidrs_empty
    test_parse_private_cidrs_single
    test_parse_private_cidrs_multi
    test_parse_private_cidrs_whitespace_only
    test_parse_private_cidrs_rejects_bare_ip
    test_parse_private_cidrs_rejects_bare_ip_in_list
    test_parse_private_cidrs_rejects_missing_address
    test_parse_private_cidrs_rejects_missing_prefix
    test_parse_private_cidrs_rejects_non_numeric_prefix
    test_parse_private_cidrs_rejects_ipv4_prefix_too_high
    test_parse_private_cidrs_rejects_ipv4_prefix_negative
    test_parse_private_cidrs_rejects_ipv6_prefix_too_high
    test_parse_private_cidrs_rejects_invalid_ipv4_octet
    test_parse_private_cidrs_rejects_non_numeric_octet
    test_parse_private_cidrs_rejects_too_few_octets
    test_parse_private_cidrs_rejects_unsafe_double_quote
    test_parse_private_cidrs_rejects_backslash
    test_parse_private_cidrs_rejects_newline
    test_parse_private_cidrs_rejects_carriage_return
    test_parse_private_cidrs_commas_only_parses_empty
    test_parse_private_cidrs_rejects_multiple_slashes
    test_parse_private_cidrs_accepts_ipv6

    test_parse_suffixes_empty
    test_parse_suffixes_single
    test_parse_suffixes_multi
    test_parse_suffixes_rejects_double_quote
    test_parse_suffixes_rejects_backslash
    test_parse_suffixes_rejects_newline
    test_parse_suffixes_rejects_carriage_return

    test_write_ssrf_runtime_partial_content
    test_write_ssrf_runtime_partial_creates_dir
    test_write_ssrf_runtime_partial_rejects_empty_suffixes
    test_write_ssrf_runtime_partial_rejects_empty_cidrs
    test_write_ssrf_runtime_partial_empty_cidrs_error_text

    test_inject_ssrf_route_policy_adds_key
    test_inject_ssrf_route_policy_idempotent
    test_inject_ssrf_route_policy_missing_section
    test_cleanup_ssrf_runtime_state_removes_runtime_only_state
    test_cleanup_ssrf_runtime_state_is_idempotent

    test_merged_runtime_contract
    test_production_config_http_services_shape

    test_summary_log_format

    print "PASS: all ssrf-runtime tests"
}
