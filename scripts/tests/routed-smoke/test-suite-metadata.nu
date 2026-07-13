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

# Test help, e2e-smoke daemon skip, and public suite inventory smoke tests.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]
use ./assertions.nu [parse-public-suite-block]

export def test-smoke-test-help [verbose: bool] {
    run-test "smoke: routed test help dispatches" {
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
        if not ($out.stdout | str contains "e2e-smoke") {
            error make {msg: "test help missing e2e-smoke public suite entry"}
        }
        if ($out.stdout | str contains "Opt-in suites") {
            error make {msg: "test help must not list opt-in suites section"}
        }
        true
    } $verbose
}

export def test-smoke-e2e-smoke-skipped-without-daemon [verbose: bool] {
    run-test "smoke: e2e-smoke suite is skipped without a Docker daemon" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")
        # Force a dead Docker endpoint so the bounded probe fails quickly.
        let out = (with-env {DOCKER_HOST: "unix:///tmp/dockypody-e2e-smoke-no-daemon.sock"} {
            ^nu $entry test --suite e2e-smoke | complete
        })
        if $out.exit_code != 0 {
            error make {msg: $"e2e-smoke without daemon should exit 0 but exited ($out.exit_code)"}
        }
        if not ($out.stdout | str contains "SKIPPED: e2e-smoke requires a reachable Docker daemon") {
            error make {msg: "e2e-smoke skip output missing SKIPPED marker line"}
        }
        if not ($out.stdout | str contains "Skipped: 1") {
            error make {msg: "e2e-smoke skip output missing Skipped: 1 in wrapper summary"}
        }
        if not ($out.stdout | str contains "Failed:  0") {
            error make {msg: "e2e-smoke skip output missing Failed:  0 in wrapper summary"}
        }
        if not ($out.stdout | str contains "No test suites failed; 1 suite(s) skipped") {
            error make {msg: "e2e-smoke skip output missing non-failure skipped footer"}
        }
        if ($out.stdout | str contains "All test suites passed!") {
            error make {msg: "e2e-smoke skip output must not show all-passed message when suites were skipped"}
        }
        true
    } $verbose
}

export def test-smoke-test-help-inventory [verbose: bool] {
    run-test "smoke: test help public suite block matches runnable public suites exactly" {
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
            "e2e-smoke"
        ]
        let public_block = (parse-public-suite-block $out.stdout)
        if $public_block != $expected_public {
            let expected_text = ($expected_public | str join ", ")
            let got_text = ($public_block | str join ", ")
            error make {msg: $"public suite block mismatch. Expected: [($expected_text)]. Got: [($got_text)]"}
        }
        for name in ["helpers" "mocks" "lib"] {
            if ($name in $public_block) {
                error make {msg: $"public suite block must not include '($name)'"}
            }
        }
        true
    } $verbose
}
