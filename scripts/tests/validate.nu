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

# Validation domain test suite

use ../lib/validate/core.nu [
  validate-local-path
  validate-version-defaults
  validate-service-complete
  validate-service-file
  validate-manifest-file
]
use ../lib/core/repo.nu [get-repo-root]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  mut results = []

  # Test: validate-local-path with valid path
  let test1 = (run-test "validate-local-path accepts valid directory" {
    let repo_root = (get-repo-root)
    let result = (validate-local-path "services" $repo_root)
    $result.valid == true
  } $verbose)
  $results = ($results | append $test1)

  # Test: validate-local-path rejects non-existent path
  let test2 = (run-test "validate-local-path rejects non-existent path" {
    let repo_root = (get-repo-root)
    let result = (validate-local-path "does-not-exist-xyz" $repo_root)
    $result.valid == false and ($result.errors | length) > 0
  } $verbose)
  $results = ($results | append $test2)

  # Test: validate-version-defaults accepts valid defaults
  let test3 = (run-test "validate-version-defaults accepts valid defaults" {
    let defaults = {
      labels: {
        "org.opencontainers.image.vendor": "Test"
      }
    }
    let result = (validate-version-defaults $defaults)
    $result.valid == true
  } $verbose)
  $results = ($results | append $test3)

  # Test: validate-service-file works for known service
  let test4 = (run-test "validate-service-file runs for common-tools" {
    let result = (validate-service-file "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose)
  $results = ($results | append $test4)

  # Test: validate-manifest-file works for known service
  let test5 = (run-test "validate-manifest-file runs for common-tools" {
    let result = (validate-manifest-file "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose)
  $results = ($results | append $test5)

  # Test: validate-service-complete works for known service
  let test6 = (run-test "validate-service-complete runs for common-tools" {
    let result = (validate-service-complete "common-tools")
    ("valid" in ($result | columns)) and ("errors" in ($result | columns))
  } $verbose)
  $results = ($results | append $test6)

  # Test: validate-service-complete returns valid:true for common-tools
  let test7 = (run-test "validate-service-complete passes for common-tools" {
    let result = (validate-service-complete "common-tools")
    $result.valid == true
  } $verbose)
  $results = ($results | append $test7)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
