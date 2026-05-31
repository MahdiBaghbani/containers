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

# Routed CLI smoke tests
#
# Exercises operator-facing dispatch paths through scripts/dockypody.nu and
# the Makefile. Non-Docker and CI-safe: help paths only print, the make path
# uses -n (dry run), and the forced-CA path is hermetic (stubbed git +
# openssl, temp repo) so it never writes a real CA.

use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [run-test print-test-summary]

def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let test_smoke_root_help = (run-test "smoke: routed top-level help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"top-level help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "DockyPody unified CLI") {
            error make {msg: "top-level help missing CLI banner"}
        }
        if not ($out.stdout | str contains "Commands:") {
            error make {msg: "top-level help missing Commands section"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_root_help)

    let test_smoke_build_help = (run-test "smoke: routed build help shows honest --disk-monitor wording" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry build help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"build help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "Build Options:") {
            error make {msg: "build help missing Build Options section"}
        }
        if not ($out.stdout | str contains "--disk-monitor") {
            error make {msg: "build help missing --disk-monitor option"}
        }
        # Runtime only special-cases "off"; any other value enables monitoring.
        # The help text must not imply that only a closed set is accepted.
        if not ($out.stdout | str contains "any other value enables") {
            error make {msg: "build help --disk-monitor wording is not honest about non-off values"}
        }
        let expected_cache_match_line = "  --cache-match <label>  Legacy/custom-caller diagnostic label; generated workflows no longer populate it"
        if not ($out.stdout | lines | any {|l| $l == $expected_cache_match_line}) {
            error make {msg: "build help --cache-match line does not match expected wording"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_build_help)

    let test_smoke_tls_help = (run-test "smoke: routed tls help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry tls help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"tls help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "Subcommands:") {
            error make {msg: "tls help missing Subcommands section"}
        }
        if not ($out.stdout | str contains "--force") {
            error make {msg: "tls help missing --force option"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_tls_help)

    let test_smoke_ssh_help = (run-test "smoke: routed ssh help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry ssh help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"ssh help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "ssh <subcommand>") {
            error make {msg: "ssh help missing routed usage line"}
        }
        if not ($out.stdout | str contains "Subcommands:") {
            error make {msg: "ssh help missing Subcommands section"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_ssh_help)

    let test_smoke_ci_help = (run-test "smoke: routed ci help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry ci help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"ci help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "ci <subcommand>") {
            error make {msg: "ci help missing routed usage line"}
        }
        if not ($out.stdout | str contains "Subcommands:") {
            error make {msg: "ci help missing Subcommands section"}
        }
        if not ($out.stdout | str contains "required for workflow") {
            error make {msg: "ci help --target not marked required for workflow"}
        }
        if not ($out.stdout | str contains "requires --target") {
            error make {msg: "ci help workflow subcommand missing requires --target wording"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_ci_help)

    let test_smoke_ci_workflow_no_target = (run-test "smoke: ci workflow without --target fails with error" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry ci workflow --dry-run | complete)
        if $out.exit_code == 0 {
            error make {msg: "ci workflow --dry-run without --target should exit non-zero but exited 0"}
        }
        if not ($out.stderr | str contains "--target is required") {
            error make {msg: $"ci workflow missing-target error should mention --target is required; got: ($out.stderr)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_ci_workflow_no_target)

    let test_smoke_docs_help = (run-test "smoke: routed docs help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry docs help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"docs help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "docs <subcommand>") {
            error make {msg: "docs help missing routed usage line"}
        }
        if not ($out.stdout | str contains "Subcommands:") {
            error make {msg: "docs help missing Subcommands section"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_docs_help)

    let test_smoke_make_certs_filter = (run-test "smoke: make -n certs forwards FILTER to tls certs --filter" {
        let make_ok = ((try { ^which make | complete | get exit_code } catch { 1 }) == 0)
        if not $make_ok {
            if $verbose_flag { print "    make not available; skipping passthrough assertion" }
            true
        } else {
            let root = (get-repo-root)
            let out = (^make -n -C $root certs FILTER=alpha,beta | complete)
            if $out.exit_code != 0 {
                error make {msg: $"make -n certs exited ($out.exit_code): ($out.stderr)"}
            }
            if not ($out.stdout | str contains 'tls certs --filter "alpha,beta"') {
                error make {msg: $"make -n did not forward FILTER as --filter; got: ($out.stdout)"}
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $test_smoke_make_certs_filter)

    let test_smoke_tls_ca_force_routing = (run-test "smoke: routed tls ca forwards --force (hermetic, no repo writes)" {
        # Resolve the real entrypoint before PATH is patched. The dispatch then
        # runs through scripts/dockypody.nu -> run-tls-command -> tls-cli.
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")

        # Fake repo so get-repo-root (git first) resolves into a temp tree.
        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir
        let ca_name = "dockypody"
        let crt = ($ca_dir | path join $"($ca_name).crt")
        let key = ($ca_dir | path join $"($ca_name).key")
        "SENTINEL-CRT" | save -f $crt
        "SENTINEL-KEY" | save -f $key

        # Stub bin: git always reports the fake repo root; openssl always fails so
        # a forwarded --force provably reaches generation (and errors) without
        # writing a real CA. `which` finds the stub openssl so require-openssl passes.
        let bin = (^mktemp -d | str trim)
        $"#!/bin/sh\necho '($fake_repo)'\n" | save -f ($bin | path join "git")
        "#!/bin/sh\nexit 1\n" | save -f ($bin | path join "openssl")
        ^chmod +x ($bin | path join "git")
        ^chmod +x ($bin | path join "openssl")

        let orig_path = ($env.PATH | default [])
        let patched_path = (if (($orig_path | describe) | str starts-with "list") {
            $orig_path | prepend $bin
        } else {
            [$bin $orig_path] | str join (char esep)
        })

        let outcomes = (with-env {PATH: $patched_path} {
            # force=true must bypass the "CA exists" skip and reach openssl, which
            # fails -> the routed entrypoint exits non-zero.
            let forced = (^nu $entry tls ca --force | complete)
            # force=false must take the existing-CA skip path and exit 0.
            let unforced = (^nu $entry tls ca | complete)
            {forced_errored: ($forced.exit_code != 0), unforced_ok: ($unforced.exit_code == 0)}
        })

        let crt_after = (open --raw $crt | decode utf-8)
        let key_after = (open --raw $key | decode utf-8)
        let tmp_leftover = (
            (($ca_dir | path join $"($ca_name).crt.tmp") | path exists)
                or (($ca_dir | path join $"($ca_name).key.tmp") | path exists)
        )
        rm-temp-context $fake_repo
        rm-temp-context $bin

        if not $outcomes.forced_errored {
            error make {msg: "routed 'tls ca' force=true should reach generation and error under failing openssl"}
        }
        if not $outcomes.unforced_ok {
            error make {msg: "routed 'tls ca' force=false should take the existing-CA skip path without error"}
        }
        if not ($crt_after | str contains "SENTINEL-CRT") {
            error make {msg: "existing CA cert must be preserved (no real write on failed force)"}
        }
        if not ($key_after | str contains "SENTINEL-KEY") {
            error make {msg: "existing CA key must be preserved (no real write on failed force)"}
        }
        if $tmp_leftover {
            error make {msg: "temp CA artifacts should be cleaned up after failed generation"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_tls_ca_force_routing)

    let test_smoke_test_help = (run-test "smoke: routed test help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry test help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"test help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "Usage: nu scripts/dockypody.nu test") {
            error make {msg: "test help missing Usage line"}
        }
        if not ($out.stdout | str contains "Available suites:") {
            error make {msg: "test help missing Available suites section"}
        }
        if not ($out.stdout | str contains "docker-integration") {
            error make {msg: "test help missing docker-integration opt-in entry"}
        }
        if not ($out.stdout | str contains "DOCKYPODY_DOCKER_INTEGRATION=1") {
            error make {msg: "test help missing routed docker-integration guidance"}
        }
        if not ($out.stdout | str contains "nu scripts/tests/docker-integration.nu --docker") {
            error make {msg: "test help missing direct docker-integration guidance"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_test_help)

    let test_smoke_docker_integration_skipped = (run-test "smoke: docker-integration suite is skipped without opt-in" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (with-env {DOCKYPODY_DOCKER_INTEGRATION: ""} {
            ^nu $entry test --suite docker-integration | complete
        })
        if $out.exit_code != 0 {
            error make {msg: $"docker-integration without opt-in should exit 0 but exited ($out.exit_code)"}
        }
        if not ($out.stdout | str contains "SKIPPED: docker-integration suite is opt-in only") {
            error make {msg: "docker-integration skip output missing SKIPPED marker line"}
        }
        if not ($out.stdout | str contains "DOCKYPODY_DOCKER_INTEGRATION=1 nu scripts/dockypody.nu test --suite docker-integration") {
            error make {msg: "docker-integration skip output missing routed guidance line"}
        }
        if not ($out.stdout | str contains "nu scripts/tests/docker-integration.nu --docker") {
            error make {msg: "docker-integration skip output missing direct guidance line"}
        }
        if not ($out.stdout | str contains "Skipped: 1") {
            error make {msg: "docker-integration skip output missing Skipped: 1 in wrapper summary"}
        }
        if not ($out.stdout | str contains "Failed:  0") {
            error make {msg: "docker-integration skip output missing Failed:  0 in wrapper summary"}
        }
        if not ($out.stdout | str contains "No test suites failed; 1 suite(s) skipped") {
            error make {msg: "docker-integration skip output missing non-failure skipped footer"}
        }
        if ($out.stdout | str contains "All test suites passed!") {
            error make {msg: "docker-integration skip output must not show all-passed message when suites were skipped"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_docker_integration_skipped)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
