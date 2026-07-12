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

# Tests for CI cache shard helpers (scripts/lib/ci/cache-shards.nu)

use ../lib.nu [print-test-summary]
use ./node-key.nu [node-key-tests]
use ./shard-name.nu [shard-name-tests]
use ./cache-paths.nu [cache-paths-tests]
use ./dep-cache-mode.nu [dep-cache-mode-tests]
use ./manifest-roundtrip.nu [manifest-roundtrip-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    $results = ($results | append (node-key-tests $verbose_flag))
    $results = ($results | append (shard-name-tests $verbose_flag))
    $results = ($results | append (cache-paths-tests $verbose_flag))
    $results = ($results | append (dep-cache-mode-tests $verbose_flag))
    $results = ($results | append (manifest-roundtrip-tests $verbose_flag))

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
