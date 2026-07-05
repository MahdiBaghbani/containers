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

# Dependency tag/key contract regression tests
#
# Proves that the three modules (dependencies.nu, order.nu, hash.nu) all
# consume the same node key format for the same dependency edge, and that
# the tag/ref path and the node-key path derive from the same
# resolve-dep-version-platform core rather than being reconstructed
# independently.
#
# Node key format: service:version:platform (colon-separated)
# Tag/ref format:  version-platform (dash-separated)
# Both share the same {version, platform} pair from resolve-dep-version-platform.
#
# These tests use real service manifests for filesystem-backed checks and the
# mock graph for dependency-graph propagation checks.

use ../lib.nu [print-test-summary]

use ./node-key.nu [node-key-tests]
use ./downstream-contracts.nu [downstream-contracts-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    $results = ($results | append (node-key-tests $verbose_flag))
    $results = ($results | append (downstream-contracts-tests $verbose_flag))

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
