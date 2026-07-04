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

# Orchestration tests: non-Docker metadata-only build command paths
#
# Exercises operator-facing dispatch through scripts/dockypody.nu for
# --matrix-json and --show-build-order paths.
# Non-Docker and CI-safe: no docker build/pull/push, no image inspection,
# no registry-dependent checks.

use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [run-test print-test-summary]
use ./orchestration/matrix-json.nu [
    test-all-services-matrix-json test-all-services-version-matrix-json
    test-matrix-json-multi-platform test-matrix-json-tracked-only-isolation
    test-platform-production-matrix-json
]
use ./orchestration/show-build-order.nu [
    test-all-versions-show-build-order test-show-build-order-kasm-base
    test-show-build-order-synthetic
]
use ./orchestration/cli-guards.nu [
    test-matrix-json-plane-local-rejected test-matrix-json-plane-local-with-fragment
]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    let root = (get-repo-root)
    let entry = ($root | path join "scripts" "dockypody.nu")

    let results = [
        (test-matrix-json-multi-platform $entry $verbose_flag)
        (test-all-services-matrix-json $entry $verbose_flag)
        (test-show-build-order-synthetic $entry $verbose_flag)
        (test-all-versions-show-build-order $entry $verbose_flag)
        (test-platform-production-matrix-json $entry $verbose_flag)
        (test-all-services-version-matrix-json $entry $verbose_flag)
        (test-matrix-json-plane-local-rejected $entry $verbose_flag)
        (test-matrix-json-tracked-only-isolation $entry $verbose_flag)
        (test-matrix-json-plane-local-with-fragment $entry $verbose_flag)
        (test-show-build-order-kasm-base $entry $verbose_flag)
    ]

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
