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

# validate-force-flags gate tests

use ../../lib/ci/ghcr/cli.nu [validate-force-flags]
use ../lib.nu [run-test]

export def test-force-gate-no-service [verbose: bool] {
    run-test "force-gate: force without service -> rejected" {
        let result = (validate-force-flags "" false true)
        if $result.ok { error make {msg: "expected gate to reject force without service"} }
        if not ($result.reason | str contains "--service") {
            error make {msg: $"expected reason to mention --service, got: ($result.reason)"}
        }
        true
    } $verbose
}

export def test-force-gate-dry-run [verbose: bool] {
    run-test "force-gate: force with dry_run=true -> rejected" {
        let result = (validate-force-flags "my-service" true true)
        if $result.ok { error make {msg: "expected gate to reject force+dry_run"} }
        if not ($result.reason | str contains "--dry-run") {
            error make {msg: $"expected reason to mention --dry-run, got: ($result.reason)"}
        }
        true
    } $verbose
}

export def test-force-gate-allowed [verbose: bool] {
    run-test "force-gate: force with service and dry_run=false -> allowed" {
        let result = (validate-force-flags "my-service" false true)
        if not $result.ok { error make {msg: $"expected gate to pass, got: ($result.reason)"} }
        true
    } $verbose
}

export def test-force-gate-no-force-always-allowed [verbose: bool] {
    run-test "force-gate: no force, any combination -> always allowed" {
        let r1 = (validate-force-flags "" false false)
        let r2 = (validate-force-flags "" true false)
        let r3 = (validate-force-flags "svc" true false)
        if not $r1.ok { error make {msg: "no-force + no-service should be allowed"} }
        if not $r2.ok { error make {msg: "no-force + dry_run should be allowed"} }
        if not $r3.ok { error make {msg: "no-force + service + dry_run should be allowed"} }
        true
    } $verbose
}
