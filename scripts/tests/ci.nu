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

# CI domain test suite

use ../lib/ci/deps.nu [get-direct-dependency-services get-all-dependency-services]
use ../lib/services/core.nu [list-service-names]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  mut results = []

  # Test: get-direct-dependency-services returns list for known service
  let test1 = (run-test "get-direct-dependency-services returns deps for gaia" {
    let deps = (get-direct-dependency-services "gaia")
    # gaia depends on common-tools
    "common-tools" in $deps
  } $verbose)
  $results = ($results | append $test1)

  # Test: get-direct-dependency-services returns empty for common-tools (no deps)
  let test2 = (run-test "get-direct-dependency-services returns empty for common-tools" {
    let deps = (get-direct-dependency-services "common-tools")
    ($deps | length) == 0
  } $verbose)
  $results = ($results | append $test2)

  # Test: list-service-names returns non-empty list
  let test3 = (run-test "list-service-names returns services" {
    let services = (list-service-names)
    ($services | length) > 0 and ("common-tools" in $services)
  } $verbose)
  $results = ($results | append $test3)

  # Test: get-all-dependency-services includes transitive deps
  let test4 = (run-test "get-all-dependency-services returns all deps for cernbox-revad" {
    let deps = (get-all-dependency-services "cernbox-revad")
    # cernbox-revad depends on common-tools, gaia, revad-base
    ("common-tools" in $deps) and ("revad-base" in $deps)
  } $verbose)
  $results = ($results | append $test4)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
