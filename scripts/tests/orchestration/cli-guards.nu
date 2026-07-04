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

# CLI guard tests: --plane local rejection and related flag guards

use ../lib.nu [run-test]
use ./fixtures.nu [
    ISOLATION_SVC ORCH_MATRIX_SVC run-dockypody-in-repo
    seed-orchestration-matrix-fixture seed-tracked-plane-isolation-fixture with-temp-repo
]

export def test-matrix-json-plane-local-rejected [entry: string, verbose: bool] {
    run-test "build --matrix-json --plane local: rejected as tracked-only surface" {
        with-temp-repo {|repo|
            seed-orchestration-matrix-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [
                build --service $ORCH_MATRIX_SVC --matrix-json --plane local
            ])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --matrix-json with --plane local"}
            }
            if not ($out.stderr | str contains "--plane local is not supported") {
                error make {msg: $"Expected tracked-only rejection in stderr, got: ($out.stderr)"}
            }
            true
        }
    } $verbose
}

export def test-matrix-json-plane-local-with-fragment [entry: string, verbose: bool] {
    run-test "build --matrix-json --plane local: rejected when local fragment is present" {
        with-temp-repo {|repo|
            seed-tracked-plane-isolation-fixture $repo
            let out = (run-dockypody-in-repo $repo $entry [
                build --service $ISOLATION_SVC --matrix-json --plane local
            ])
            if $out.exit_code == 0 {
                error make {msg: "Expected non-zero exit for --matrix-json with --plane local"}
            }
            if not ($out.stderr | str contains "--plane local is not supported") {
                error make {msg: $"Expected tracked-only rejection in stderr, got: ($out.stderr)"}
            }
            true
        }
    } $verbose
}
