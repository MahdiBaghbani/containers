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
use ../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ./lib.nu [run-test print-test-summary]

def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    mkdir ($tmp | path join "scripts")
    ^git -C $tmp init -q
    $tmp
}

def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

def dockypody-entry [] {
    "scripts/dockypody.nu" | path expand
}

def run-dockypody-in-repo [repo: string, args: list<string>] {
    let entry = (dockypody-entry)
    do -i { cd $repo; ^nu $entry ...$args } | complete
}

def seed-tracked-service [repo: string, name: string = "test-svc"] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
}

def seed-service-with-git-source [
    repo: string,
    name: string = "test-svc",
    fanout_capable: bool = false
] {
    seed-tracked-service $repo $name
    mkdir ($repo | path join $"services/($name)")
    mut version_entry = { name: "v1", overrides: {} }
    if $fanout_capable {
        $version_entry = ($version_entry | merge { latest: true, tags: ["extra"] })
    }
    {
        default: "v1"
        versions: [$version_entry]
        defaults: {
            sources: {
                my_src: {
                    url: "https://example.com/repo.git"
                    ref: "main"
                }
            }
        }
    } | save -f ($repo | path join $"services/($name)/versions.nuon")
}

def assert-routed-failure-names-contract [
    result: record,
    contract: string,
    forbidden: list<string> = []
] {
    if $result.exit_code == 0 {
        error make {msg: $"Expected routed command to fail for contract '($contract)'"}
    }
    let combined = ($result.stdout + $result.stderr)
    if not ($combined | str contains $contract) {
        error make {msg: $"Expected routed failure to name contract '($contract)', got: ($combined)"}
    }
    for needle in $forbidden {
        if ($combined | str contains $needle) {
            error make {msg: $"Contract '($contract)' failure must not mention '($needle)', got: ($combined)"}
        }
    }
    true
}

def inspect-suppressed-tag-fanout [] {
    [
        "manifest-latest"
        "cli-latest"
        "extra-tag"
        "publish"
        "dependency-tag-fanout"
        "dependency-push-fanout"
    ]
}

def assert-single-primary-tag-state [cfg: record, service: string, version: string] {
    let tag_state = $cfg.single_primary_tag_state
    if not $tag_state.active {
        error make {msg: "Expected single_primary_tag_state.active true on local plane"}
    }
    if $tag_state.policy != "single-primary-non-publish" {
        error make {msg: $"Expected single-primary policy, got: ($tag_state.policy)"}
    }
    let expected_primary = $"($service):($version)"
    if ($tag_state.primary_tag? | default "") != $expected_primary {
        error make {msg: $"Expected primary_tag ($expected_primary), got: ($tag_state.primary_tag)"}
    }
    let expected_suppressed = (inspect-suppressed-tag-fanout)
    for item in $expected_suppressed {
        if not ($item in $tag_state.suppressed) {
            error make {msg: $"Expected suppressed fan-out item '($item)' in single_primary_tag_state"}
        }
    }
    if ($tag_state.suppressed | length) != ($expected_suppressed | length) {
        error make {msg: $"Unexpected suppressed fan-out entries: ($tag_state.suppressed | to json)"}
    }
    true
}

def assert-inspect-semantic-baseline [
    cfg: record,
    repo: string,
    service: string,
    version: string,
    fragment_present: bool,
    mirror_path: string = ""
] {
    for required_key in [
        plane service version tracked_service tracked_version local_root
        local_fragment_present local_mirror_path env_only env_keys_used
        source_origin precedence_summary single_primary_tag_state
    ] {
        if not ($required_key in ($cfg | columns)) {
            error make {msg: $"Missing required inspect semantic key: ($required_key)"}
        }
    }

    if $cfg.plane != "local" {
        error make {msg: $"Expected plane 'local', got: ($cfg.plane)"}
    }
    if $cfg.service != $service {
        error make {msg: $"Expected service '($service)', got: ($cfg.service)"}
    }
    if $cfg.version != $version {
        error make {msg: $"Expected version '($version)', got: ($cfg.version)"}
    }
    if $cfg.tracked_service != $service {
        error make {msg: $"Expected tracked_service '($service)', got: ($cfg.tracked_service)"}
    }
    if $cfg.tracked_version != $version {
        error make {msg: $"Expected tracked_version '($version)', got: ($cfg.tracked_version)"}
    }

    let expected_local_root = (local-root-path $repo | path expand)
    let actual_local_root = (try { $cfg.local_root | path expand } catch { "" })
    if $actual_local_root != $expected_local_root {
        error make {msg: $"Expected local_root ($expected_local_root), got: ($actual_local_root)"}
    }

    if $cfg.local_fragment_present != $fragment_present {
        error make {msg: $"Expected local_fragment_present ($fragment_present), got: ($cfg.local_fragment_present)"}
    }

    let expected_mirror = (if ($mirror_path | str length) > 0 {
        $mirror_path | path expand
    } else {
        ""
    })
    let actual_mirror = (if ($cfg.local_mirror_path | str length) > 0 {
        $cfg.local_mirror_path | path expand
    } else {
        ""
    })
    if $actual_mirror != $expected_mirror {
        error make {msg: $"Expected local_mirror_path '($expected_mirror)', got: '($actual_mirror)'"}
    }

    assert-single-primary-tag-state $cfg $service $version
    true
}

def parse-public-suite-block [help_output: string] {
    let lines = ($help_output | lines)
    let available = ($lines | enumerate | where item == "Available suites:")
    if ($available | is-empty) {
        error make {msg: "test help missing Available suites marker"}
    }

    let block_lines = (
        $lines
            | skip (($available | first | get index) + 1)
            | take while {|line| ($line | str trim) != ""}
    )

    $block_lines | each {|line|
        let parsed = ($line | parse --regex '^\s+(?P<name>\S+)\s+(?P<desc>.+)$')
        if ($parsed | is-empty) {
            error make {msg: $"unable to parse public suite line: ($line)"}
        }
        $parsed | get 0.name
    }
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

    let test_smoke_inspect_help = (run-test "smoke: routed inspect help dispatches" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry inspect help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"inspect help exited ($out.exit_code): ($out.stderr)"}
        }
        if not ($out.stdout | str contains "inspect <subcommand>") {
            error make {msg: "inspect help missing routed usage line"}
        }
        if not ($out.stdout | str contains "effective-config") {
            error make {msg: "inspect help missing effective-config subcommand"}
        }
        if not ($out.stdout | str contains "--plane") {
            error make {msg: "inspect help missing --plane option"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_inspect_help)

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

    let test_smoke_test_help_inventory = (run-test "smoke: test help public suite block matches runnable public suites exactly" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry test help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"test help exited ($out.exit_code): ($out.stderr)"}
        }
        let expected_public = [
            "all"
            "architecture" "manifests" "services" "tls" "ssh" "tag-generation"
            "build-system" "local-plane-build" "effective-versions" "defaults" "pull"
            "validate" "registries" "ci"
            "ghcr-purge" "docs-lint" "routed-smoke" "cache-shards"
            "orchestration" "dep-contract" "service-def-hash"
        ]
        let public_block = (parse-public-suite-block $out.stdout)
        if $public_block != $expected_public {
            let expected_text = ($expected_public | str join ", ")
            let got_text = ($public_block | str join ", ")
            error make {msg: $"public suite block mismatch. Expected: [($expected_text)]. Got: [($got_text)]"}
        }
        for name in ["docker-integration" "helpers" "mocks" "lib"] {
            if ($name in $public_block) {
                error make {msg: $"public suite block must not include '($name)'"}
            }
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_test_help_inventory)

    let test_smoke_local_missing_root = (run-test "smoke: routed build --plane local missing root names presence contract" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        let result = (run-dockypody-in-repo $repo [build --plane local --show-build-order --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "requires local root directory" [
            "Unsupported local root"
            "Unknown local service mirror"
            "Incomplete local service mirror"
        ]
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_missing_root)

    let test_smoke_local_empty_topology = (run-test "smoke: routed build --plane local passes guard on empty legal topology" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let result = (run-dockypody-in-repo $repo [build --plane local --show-build-order --service test-svc])
        rm-temp-repo $repo
        if $result.exit_code != 0 {
            error make {msg: $"Expected guard pass on empty legal topology, exit ($result.exit_code): ($result.stderr)"}
        }
        let combined = ($result.stdout + $result.stderr)
        if ($combined | str contains "requires local root directory") {
            error make {msg: "Empty legal topology must not fail root presence guard"}
        }
        if ($combined | str contains "Unsupported local root") {
            error make {msg: "Empty legal topology must not fail topology audit"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_empty_topology)

    let test_smoke_local_baseline_inspect = (run-test "smoke: routed inspect effective-config baseline local-plane semantics" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo "test-svc" true
        mkdir (local-root-path $repo)
        let out = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" false ""
        if $cfg.env_only {
            error make {msg: "Baseline local inspect must not be classified as env_only"}
        }
        if ($cfg.env_keys_used | length) != 0 {
            error make {msg: $"Expected empty env_keys_used for baseline local inspect, got: ($cfg.env_keys_used | to json)"}
        }
        if ($cfg.source_origin.my_src? | default "") != "tracked-git" {
            error make {msg: $"Expected source_origin.my_src 'tracked-git', got: ($cfg.source_origin | to json)"}
        }
        if $cfg.precedence_summary != "tracked manifest" {
            error make {msg: $"Expected precedence_summary 'tracked manifest', got: ($cfg.precedence_summary)"}
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_baseline_inspect)

    let test_smoke_local_env_materialization = (run-test "smoke: routed inspect effective-config env-only path materialization" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        mkdir ($repo | path join "local-src")
        let expected_path = ($repo | path join "local-src" | path expand)
        let entry = (dockypody-entry)
        let out = (do -i {||
            cd $repo
            $env.MY_SRC_PATH = ($env.PWD | path join "local-src")
            ^nu $entry inspect effective-config --service test-svc --plane local
        } | complete)
        if $out.exit_code != 0 {
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" false ""
        let materialized = (try { $cfg.sources.my_src.path | path expand } catch { "" })
        if $materialized != $expected_path {
            error make {msg: $"Expected env-only path ($expected_path), got: ($materialized)"}
        }
        if ("url" in ($cfg.sources.my_src | columns)) or ("ref" in ($cfg.sources.my_src | columns)) {
            error make {msg: "Env-only materialization must replace git fields with path only"}
        }
        if not $cfg.env_only {
            error make {msg: "Expected env_only true for env PATH materialization"}
        }
        if not ("MY_SRC_PATH" in $cfg.env_keys_used) {
            error make {msg: $"Expected MY_SRC_PATH in env_keys_used, got: ($cfg.env_keys_used | to json)"}
        }
        if ($cfg.source_origin.my_src? | default "") != "env-only" {
            error make {msg: $"Expected source_origin.my_src 'env-only', got: ($cfg.source_origin | to json)"}
        }
        if not ($cfg.precedence_summary | str contains "env PATH materialization") {
            error make {msg: $"Expected precedence_summary to mention env PATH, got: ($cfg.precedence_summary)"}
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_env_materialization)

    let test_smoke_local_fragment_semantics = (run-test "smoke: routed inspect effective-config fragment mirror semantics" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "fragment-src")
        {
            overrides: {
                sources: {
                    my_src: { path: "fragment-src" }
                }
            }
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" true $mirror
        if $cfg.env_only {
            error make {msg: "Fragment override must not be classified as env_only"}
        }
        if ($cfg.env_keys_used | length) != 0 {
            error make {msg: $"Expected empty env_keys_used for fragment path, got: ($cfg.env_keys_used | to json)"}
        }
        if ($cfg.source_origin.my_src? | default "") != "fragment-local" {
            error make {msg: $"Expected source_origin.my_src 'fragment-local', got: ($cfg.source_origin | to json)"}
        }
        if not ($cfg.precedence_summary | str contains "local fragment overrides") {
            error make {msg: $"Expected precedence_summary to mention fragment overrides, got: ($cfg.precedence_summary)"}
        }
        if ($cfg.sources.my_src.path? | default "") != "fragment-src" {
            error make {msg: $"Expected fragment path 'fragment-src', got: ($cfg.sources.my_src.path)"}
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_fragment_semantics)

    let test_smoke_local_only_version_inspect = (run-test "smoke: routed inspect effective-config local-only version from fragment versions array" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "local-only-src")
        {
            versions: [
                {
                    name: "local-only-v"
                    overrides: {
                        sources: {
                            my_src: { path: "local-only-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version local-only-v
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success for local-only version, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "local-only-v" true $mirror
        if not ($cfg.precedence_summary | str contains "local-only version") {
            error make {msg: $"Expected precedence_summary to mention local-only version, got: ($cfg.precedence_summary)"}
        }
        if ($cfg.sources.my_src.path? | default "") != "local-only-src" {
            error make {msg: $"Expected local-only source path, got: ($cfg.sources.my_src.path)"}
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_only_version_inspect)

    let test_smoke_local_version_replace_inspect = (run-test "smoke: routed inspect effective-config local version replaces tracked same name" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "replaced-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            my_src: { path: "replaced-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version v1
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success for replaced version, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        assert-inspect-semantic-baseline $cfg $repo "test-svc" "v1" true $mirror
        if not ($cfg.precedence_summary | str contains "local version (replace)") {
            error make {msg: $"Expected precedence_summary to mention local version replace, got: ($cfg.precedence_summary)"}
        }
        if ($cfg.sources.my_src.path? | default "") != "replaced-src" {
            error make {msg: $"Expected replaced local path 'replaced-src', got: ($cfg.sources.my_src.path)"}
        }
        if ("url" in ($cfg.sources.my_src | columns)) or ("ref" in ($cfg.sources.my_src | columns)) {
            error make {msg: "Replaced local version must materialize path-only source, not git fields"}
        }
        if ($cfg.source_origin.my_src? | default "") != "fragment-local" {
            error make {msg: $"Expected source_origin.my_src 'fragment-local', got: ($cfg.source_origin | to json)"}
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_version_replace_inspect)

    let test_smoke_local_version_scoped_fragment_precedence = (run-test "smoke: routed inspect version-scoped fragment sources align precedence_summary with source_origin" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "version-scoped-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            my_src: { path: "version-scoped-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let out = (run-dockypody-in-repo $repo [
            inspect effective-config --service test-svc --plane local --version v1
        ])
        if $out.exit_code != 0 {
            rm-temp-repo $repo
            error make {msg: $"Expected inspect success, exit ($out.exit_code): ($out.stderr)"}
        }
        let cfg = (try {
            $out.stdout | from json
        } catch {
            rm-temp-repo $repo
            error make {msg: $"Expected JSON stdout, got: ($out.stdout)"}
        })
        if ($cfg.source_origin.my_src? | default "") != "fragment-local" {
            rm-temp-repo $repo
            error make {msg: $"Expected source_origin.my_src 'fragment-local', got: ($cfg.source_origin | to json)"}
        }
        if $cfg.precedence_summary == "tracked manifest" {
            rm-temp-repo $repo
            error make {
                msg: $"precedence_summary must not be plain 'tracked manifest' when source_origin is fragment-local, got: ($cfg.precedence_summary)"
            }
        }
        if not ($cfg.precedence_summary | str contains "local fragment overrides") {
            rm-temp-repo $repo
            error make {
                msg: $"Expected precedence_summary to mention version-scoped fragment overrides, got: ($cfg.precedence_summary)"
            }
        }
        rm-temp-repo $repo
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_version_scoped_fragment_precedence)

    let test_smoke_local_bad_topology = (run-test "smoke: routed validate --plane local bad topology names unknown mirror contract" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo)
        mkdir (local-services-path $repo | path join "shadow-svc")
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Unknown local service mirror" []
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_bad_topology)

    let test_smoke_local_bad_source = (run-test "smoke: routed inspect effective-config bad local source names additive id contract" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        {
            overrides: {
                sources: {
                    extra_src: { path: "local-src" }
                }
            }
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let result = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Additive source id" []
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_bad_source)

    let test_smoke_local_validate_additive_version_source = (run-test "smoke: routed validate --plane local rejects additive id in fragment versions" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        "FROM scratch" | save -f ($repo | path join "services/test-svc/Dockerfile")
        {
            name: "test-svc"
            context: "services/test-svc"
            dockerfile: "services/test-svc/Dockerfile"
        } | save -f ($repo | path join "services/test-svc.nuon")
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "local-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            extra_src: { path: "local-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Additive source id" []
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_validate_additive_version_source)

    let test_smoke_local_guard_ordering = (run-test "smoke: routed validate guard ordering manifest read before mirror audit" {
        let repo = (make-temp-repo)
        "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo)
        mkdir (local-services-path $repo | path join "test-svc")
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Unable to read tracked service manifest" [
            "Unknown local service mirror"
        ]
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_guard_ordering)

    let test_smoke_local_incomplete_mirror = (run-test "smoke: routed inspect bad topology names incomplete mirror contract before materialization" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo | path join "test-svc")
        let result = (run-dockypody-in-repo $repo [inspect effective-config --service test-svc --plane local])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Incomplete local service mirror" [
            "Additive source id"
            "Partial git source is forbidden"
        ]
    } $verbose_flag)
    $results = ($results | append $test_smoke_local_incomplete_mirror)

    let test_smoke_internal_suite_errors = (run-test "smoke: unsupported/internal suite name errors clearly" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        let out = (^nu $entry test --suite helpers | complete)
        let expected_stderr = "Unsupported test suite: 'helpers'. Run: nu scripts/dockypody.nu test help"
        if $out.exit_code == 0 {
            error make {msg: "test --suite helpers should fail but exited 0"}
        }
        if (($out.stdout | str trim) != "") {
            error make {msg: $"internal suite error should not print stdout; got: ($out.stdout | str trim)"}
        }
        if (($out.stderr | str trim) != $expected_stderr) {
            error make {msg: $"internal suite stderr mismatch. Expected: '($expected_stderr)'. Got: '($out.stderr | str trim)'"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $test_smoke_internal_suite_errors)

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
