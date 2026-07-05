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

# Tag generation tests

use ../lib.nu [print-test-summary]
use ./single-platform.nu [single-platform-tests]
use ./multi-platform.nu [multi-platform-tests platforms-nuon-tests]
use ./version-latest-tags.nu [empty-missing-tags-tests version-latest-tags-tests]
use ./remote-registry.nu [remote-registry-tests]
use ./tag-ordering.nu [tag-ordering-tests]
use ./local-plane.nu [local-plane-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    $results = ($results | append (single-platform-tests $verbose_flag))
    $results = ($results | append (multi-platform-tests $verbose_flag))
    $results = ($results | append (version-latest-tags-tests $verbose_flag))
    $results = ($results | append (remote-registry-tests $verbose_flag))
    $results = ($results | append (tag-ordering-tests $verbose_flag))
    $results = ($results | append (empty-missing-tags-tests $verbose_flag))
    $results = ($results | append (platforms-nuon-tests $verbose_flag))
    $results = ($results | append (local-plane-tests $verbose_flag))

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
