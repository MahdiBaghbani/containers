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

# Service definition hash stability tests

use ./lib.nu [print-test-summary]

use ./service-def-hash/hash-basics.nu [hash-basics-tests]
use ./service-def-hash/hash-graph.nu [hash-graph-tests]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []

  $results = ($results | append (hash-basics-tests $verbose_flag))
  $results = ($results | append (hash-graph-tests $verbose_flag))

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
