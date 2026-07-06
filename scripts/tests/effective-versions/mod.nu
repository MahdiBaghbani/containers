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

# Effective versions manifest tests (local-plane L1 foundation)

use ../lib.nu [print-test-summary]
use ./passthrough.nu [
  test-tracked-passthrough-null test-tracked-passthrough-plane test-local-no-fragment
]
use ./merge-behavior.nu [
  test-replace-by-name test-append-new test-default-override
]
use ./fragment-validation.nu [
  test-additive-id test-partial-source test-mixed-path-git test-empty-path
  test-empty-source-object test-ref-only-source test-fragment-missing-name
  test-fragment-empty-name test-fragment-duplicate-names
]
use ./universe-primitives.nu [
  test-merge-unit test-source-id-universe test-local-only-detector
]
use ./describe-universe.nu [
  test-describe-universe-local-only test-describe-universe-no-fragment
  test-describe-universe-overlap
]
use ./miss-errors.nu [
  test-format-miss-local-only test-format-miss-generic
  test-format-miss-fragment-generic test-format-miss-inspect-generic
]
use ./inspect-resolve.nu [
  test-resolve-inspect-generic-miss test-resolve-inspect-fragment-generic-miss
]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })

  let results = [
    (test-tracked-passthrough-null $verbose_flag)
    (test-tracked-passthrough-plane $verbose_flag)
    (test-local-no-fragment $verbose_flag)
    (test-replace-by-name $verbose_flag)
    (test-append-new $verbose_flag)
    (test-default-override $verbose_flag)
    (test-additive-id $verbose_flag)
    (test-partial-source $verbose_flag)
    (test-mixed-path-git $verbose_flag)
    (test-empty-path $verbose_flag)
    (test-empty-source-object $verbose_flag)
    (test-ref-only-source $verbose_flag)
    (test-fragment-missing-name $verbose_flag)
    (test-fragment-empty-name $verbose_flag)
    (test-fragment-duplicate-names $verbose_flag)
    (test-merge-unit $verbose_flag)
    (test-source-id-universe $verbose_flag)
    (test-describe-universe-local-only $verbose_flag)
    (test-local-only-detector $verbose_flag)
    (test-format-miss-local-only $verbose_flag)
    (test-format-miss-generic $verbose_flag)
    (test-describe-universe-no-fragment $verbose_flag)
    (test-describe-universe-overlap $verbose_flag)
    (test-format-miss-fragment-generic $verbose_flag)
    (test-format-miss-inspect-generic $verbose_flag)
    (test-resolve-inspect-generic-miss $verbose_flag)
    (test-resolve-inspect-fragment-generic-miss $verbose_flag)
  ]

  print-test-summary $results
  if ($results | where {|r| not $r} | is-empty) {
    exit 0
  } else {
    exit 1
  }
}
