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

# format-purge-summary tests

use ../../lib/ci/ghcr/cli.nu [format-purge-summary]
use ../lib.nu [run-test]

export def test-format-summary [verbose: bool] {
    run-test "format-purge-summary: emits summary, permission-denied, and failed lines" {
        let agg = {
            planned: 5, attempted: 4, deleted: 3, failed: 1, skipped: 0, charged: 4,
            failed_services: ["svc-fail"], permission_denied_services: ["svc-perm"]
        }
        let lines = (format-purge-summary $agg)
        if ($lines | length) != 3 { error make {msg: $"expected 3 summary lines, got ($lines | length)"} }
        if not ($lines.0 | str contains "Purge complete: planned=5") {
            error make {msg: $"expected summary line, got: ($lines.0)"}
        }
        if not ($lines.0 | str contains "failed_services=1") {
            error make {msg: $"expected failed_services count in summary, got: ($lines.0)"}
        }
        if not ($lines.1 | str contains "Permission-denied versions") {
            error make {msg: $"expected permission-denied line, got: ($lines.1)"}
        }
        if not ($lines.2 | str contains "Failed services: svc-fail") {
            error make {msg: $"expected failed-services line, got: ($lines.2)"}
        }
        true
    } $verbose
}

export def test-format-summary-clean [verbose: bool] {
    run-test "format-purge-summary: clean run emits only the summary line" {
        let agg = {
            planned: 0, attempted: 0, deleted: 0, failed: 0, skipped: 0, charged: 0,
            failed_services: [], permission_denied_services: []
        }
        let lines = (format-purge-summary $agg)
        if ($lines | length) != 1 { error make {msg: $"expected 1 line for clean run, got ($lines | length)"} }
        if not ($lines.0 | str contains "failed_services=0") {
            error make {msg: $"expected failed_services=0, got: ($lines.0)"}
        }
        true
    } $verbose
}
