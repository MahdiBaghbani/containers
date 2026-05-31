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

# Entrypoint-level SSRF contract tests for setup_ssrf_runtime_route.
# Run: nu tests/entrypoint-ssrf-test.nu
# On success prints a summary line; code under test may also emit status lines.
# Any failure prints a message and exits non-zero.
#
# Uses temp dirs and direct function invocation; no container startup needed.

use ../scripts/entrypoint-init.nu [setup_ssrf_runtime_route validate_mode]

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

# Minimal config.toml with [outbound_http.ssrf] section,
# matching the baked container config shape (no top-level mode or
# compatibility_scope; those come from the upstream preset at load time).
def make_base_config []: nothing -> string {
    [
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

def assert_eq [label: string, got: any, want: any] {
    if $got != $want {
        error make {
            msg: $"FAIL [$label]: got ($got | to nuon), want ($want | to nuon)"
        }
    }
}

# --- validate_mode contract ---

# Empty / unset OCM_GO_MODE: returns empty string (no --mode flag injected).
def test_mode_empty [] {
    let got = (with-env {OCM_GO_MODE: ""} { validate_mode })
    assert_eq "mode empty" $got ""
}

# strict, compat, dev are all accepted and returned as-is.
def test_mode_strict [] {
    let got = (with-env {OCM_GO_MODE: "strict"} { validate_mode })
    assert_eq "mode strict" $got "strict"
}

def test_mode_compat [] {
    let got = (with-env {OCM_GO_MODE: "compat"} { validate_mode })
    assert_eq "mode compat" $got "compat"
}

def test_mode_dev [] {
    let got = (with-env {OCM_GO_MODE: "dev"} { validate_mode })
    assert_eq "mode dev" $got "dev"
}

# An unrecognised token must fail with a descriptive error.
def test_mode_invalid_rejected [] {
    (assert_throws_contains
        "mode invalid rejected"
        {|| with-env {OCM_GO_MODE: "bogus"} { validate_mode }}
        "OCM_GO_MODE must be strict, compat, or dev")
}

# "interop" is a removed alias; it must be explicitly rejected so the
# no-legacy decision is enforced as a regression, not just by omission.
def test_mode_interop_rejected [] {
    (assert_throws_contains
        "mode interop rejected (removed alias)"
        {|| with-env {OCM_GO_MODE: "interop"} { validate_mode }}
        "OCM_GO_MODE must be strict, compat, or dev")
}

# --- setup_ssrf_runtime_route contract ---

# Both envs unset: no partial written, route_policy not injected.
def test_setup_both_unset [] {
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($cfg_dir)/partial"
    let cfg = $"($cfg_dir)/config.toml"
    let partial = $"($partial_dir)/99-runtime-ssrf.toml"

    let result = try {
        mkdir $cfg_dir
        mkdir $partial_dir
        make_base_config | save -f $cfg

        with-env {OCM_GO_ROUTE_PRIVATE_CIDRS: "", OCM_GO_ROUTE_SUFFIXES: ""} {
            setup_ssrf_runtime_route $cfg_dir $partial_dir
        }

        if ($partial | path exists) {
            error make {msg: "FAIL [both unset]: runtime partial must not exist when no envs set"}
        }

        let content = (open --raw $cfg)
        assert_not_contains "both unset no route_policy" $content "route_policy"

        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

# Both envs set: partial written, route_policy = "runtime" injected into config.
def test_setup_both_set [] {
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($cfg_dir)/partial"
    let cfg = $"($cfg_dir)/config.toml"
    let partial = $"($partial_dir)/99-runtime-ssrf.toml"

    let result = try {
        mkdir $cfg_dir
        mkdir $partial_dir
        make_base_config | save -f $cfg

        with-env {
            OCM_GO_ROUTE_PRIVATE_CIDRS: "10.1.2.0/24"
            OCM_GO_ROUTE_SUFFIXES: ".docker"
        } {
            setup_ssrf_runtime_route $cfg_dir $partial_dir
        }

        if not ($partial | path exists) {
            error make {msg: "FAIL [both set]: runtime partial must exist when both envs set"}
        }

        let cfg_content = (open --raw $cfg)
        assert_contains "both set route_policy injected" $cfg_content "route_policy = \"runtime\""

        let partial_content = (open --raw $partial)
        assert_contains "both set partial header" $partial_content "[outbound_http.ssrf.route_policies.runtime]"
        assert_contains "both set partial suffix" $partial_content "\".docker\""
        assert_contains "both set partial cidr" $partial_content "\"10.1.2.0/24\""

        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

# Suffixes set but cidrs unset: fails with cidrs-required error.
def test_setup_suffixes_only [] {
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($cfg_dir)/partial"
    let cfg = $"($cfg_dir)/config.toml"

    let result = try {
        mkdir $cfg_dir
        mkdir $partial_dir
        make_base_config | save -f $cfg

        (assert_throws_contains
            "suffixes only requires cidrs"
            {||
                with-env {
                    OCM_GO_ROUTE_PRIVATE_CIDRS: ""
                    OCM_GO_ROUTE_SUFFIXES: ".docker"
                } {
                    setup_ssrf_runtime_route $cfg_dir $partial_dir
                }
            }
            "OCM_GO_ROUTE_PRIVATE_CIDRS must be set")

        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

# CIDRs set but suffixes unset: fails with suffixes-required error.
def test_setup_cidrs_only [] {
    let tmp = (^mktemp -d)
    let cfg_dir = $"($tmp)/configs"
    let partial_dir = $"($cfg_dir)/partial"
    let cfg = $"($cfg_dir)/config.toml"

    let result = try {
        mkdir $cfg_dir
        mkdir $partial_dir
        make_base_config | save -f $cfg

        (assert_throws_contains
            "cidrs only requires suffixes"
            {||
                with-env {
                    OCM_GO_ROUTE_PRIVATE_CIDRS: "10.1.2.0/24"
                    OCM_GO_ROUTE_SUFFIXES: ""
                } {
                    setup_ssrf_runtime_route $cfg_dir $partial_dir
                }
            }
            "OCM_GO_ROUTE_SUFFIXES must be set")

        null
    } catch {|e| $e}

    ^rm -rf $tmp

    if $result != null {
        error make {msg: $result.msg}
    }
}

def main [] {
    test_mode_empty
    test_mode_strict
    test_mode_compat
    test_mode_dev
    test_mode_invalid_rejected
    test_mode_interop_rejected
    test_setup_both_unset
    test_setup_both_set
    test_setup_suffixes_only
    test_setup_cidrs_only

    print "PASS: all entrypoint-ssrf tests"
}
