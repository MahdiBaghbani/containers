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

# Top-level and subcommand help smoke tests.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

export def test-smoke-root-help [verbose: bool] {
    run-test "smoke: routed top-level help dispatches" {
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
    } $verbose
}

export def test-smoke-build-help [verbose: bool] {
    run-test "smoke: routed build help shows honest --disk-monitor wording" {
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
        if not ($out.stdout | str contains "any other value enables") {
            error make {msg: "build help --disk-monitor wording is not honest about non-off values"}
        }
        let expected_cache_match_line = "  --cache-match <label>  Legacy/custom-caller diagnostic label; generated workflows no longer populate it"
        if not ($out.stdout | lines | any {|l| $l == $expected_cache_match_line}) {
            error make {msg: "build help --cache-match line does not match expected wording"}
        }
        true
    } $verbose
}

export def test-smoke-tls-help [verbose: bool] {
    run-test "smoke: routed tls help dispatches" {
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
    } $verbose
}

export def test-smoke-ssh-help [verbose: bool] {
    run-test "smoke: routed ssh help dispatches" {
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
    } $verbose
}

export def test-smoke-ci-help [verbose: bool] {
    run-test "smoke: routed ci help dispatches" {
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
    } $verbose
}

export def test-smoke-ci-workflow-no-target [verbose: bool] {
    run-test "smoke: ci workflow without --target fails with error" {
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
    } $verbose
}

export def test-smoke-docs-help [verbose: bool] {
    run-test "smoke: routed docs help dispatches" {
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
    } $verbose
}

export def test-smoke-inspect-help [verbose: bool] {
    run-test "smoke: routed inspect help dispatches" {
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
    } $verbose
}
