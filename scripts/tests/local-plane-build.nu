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

# Local-plane build suppression integration tests (stubbed docker, no daemon)

use ./lib.nu [print-test-summary]
use ./local-plane-build/build-suppression.nu [test-local-plane-build-suppression]
use ./local-plane-build/inspect-alignment.nu [test-local-plane-inspect-alignment]
use ./local-plane-build/local-only-version.nu [test-local-only-version-via-build-cli]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    $results = ($results | append (test-local-plane-build-suppression $verbose_flag))
    $results = ($results | append (test-local-plane-inspect-alignment $verbose_flag))
    $results = ($results | append (test-local-only-version-via-build-cli $verbose_flag))

    print-test-summary $results

    if ($results | any {|r| not $r}) {
        exit 1
    }
}
