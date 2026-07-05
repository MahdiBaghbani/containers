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

# Comprehensive tests for top-level defaults feature

use ../lib.nu [print-test-summary]
use ./version-defaults.nu [
  test-apply-version-defaults-no-defaults
  test-apply-version-defaults-global-defaults-only
  test-apply-version-defaults-override-takes-precedence
  test-apply-version-defaults-platform-specific-defaults
  test-apply-version-defaults-platform-override-takes-precedence
  test-apply-version-defaults-empty-overrides-with-defaults-platforms
  test-apply-version-defaults-version-without-overrides-field
  test-deep-merge-nested-records-merge-correctly
]
use ./platform-defaults.nu [
  test-apply-platform-defaults-no-defaults
  test-apply-platform-defaults-with-defaults
  test-apply-platform-defaults-override-takes-precedence
]
use ./lookup-expand.nu [
  test-get-version-spec-applies-defaults-automatically
  test-get-platform-spec-applies-defaults-automatically
  test-expand-version-to-platforms-works-with-defaults
]
use ./validation.nu [
  test-validation-valid-defaults-structure
  test-validation-invalid-defaults-forbidden-field
  test-validation-platform-defaults-forbid-sources
  test-backward-compatibility-manifest-without-defaults
]
use ./source-replacement.nu [
  test-source-replacement-git-source-to-local-source
  test-source-preservation-omitted-sources-preserved-from-defaults
  test-empty-overrides-source-defaults-inherited
  test-other-fields-merge-dependencies-and-external-images
  test-partial-git-source-override-ref-only
  test-partial-git-source-override-url-only
  test-complete-git-source-override
  test-empty-source-override-preserves-all-fields-from-defaults
]
use ./platform-source-overrides.nu [
  test-platform-specific-source-replacement
  test-platform-specific-sources-in-defaults
  test-mixed-global-and-platform-specific-source-overrides
  test-platform-specific-partial-git-source-override
]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })

  let results = [
    (test-apply-version-defaults-no-defaults $verbose_flag)
    (test-apply-version-defaults-global-defaults-only $verbose_flag)
    (test-apply-version-defaults-override-takes-precedence $verbose_flag)
    (test-apply-version-defaults-platform-specific-defaults $verbose_flag)
    (test-apply-version-defaults-platform-override-takes-precedence $verbose_flag)
    (test-apply-version-defaults-empty-overrides-with-defaults-platforms $verbose_flag)
    (test-apply-version-defaults-version-without-overrides-field $verbose_flag)
    (test-apply-platform-defaults-no-defaults $verbose_flag)
    (test-apply-platform-defaults-with-defaults $verbose_flag)
    (test-apply-platform-defaults-override-takes-precedence $verbose_flag)
    (test-get-version-spec-applies-defaults-automatically $verbose_flag)
    (test-get-platform-spec-applies-defaults-automatically $verbose_flag)
    (test-expand-version-to-platforms-works-with-defaults $verbose_flag)
    (test-validation-valid-defaults-structure $verbose_flag)
    (test-validation-invalid-defaults-forbidden-field $verbose_flag)
    (test-validation-platform-defaults-forbid-sources $verbose_flag)
    (test-backward-compatibility-manifest-without-defaults $verbose_flag)
    (test-deep-merge-nested-records-merge-correctly $verbose_flag)
    (test-source-replacement-git-source-to-local-source $verbose_flag)
    (test-source-preservation-omitted-sources-preserved-from-defaults $verbose_flag)
    (test-empty-overrides-source-defaults-inherited $verbose_flag)
    (test-other-fields-merge-dependencies-and-external-images $verbose_flag)
    (test-platform-specific-source-replacement $verbose_flag)
    (test-platform-specific-sources-in-defaults $verbose_flag)
    (test-mixed-global-and-platform-specific-source-overrides $verbose_flag)
    (test-partial-git-source-override-ref-only $verbose_flag)
    (test-partial-git-source-override-url-only $verbose_flag)
    (test-complete-git-source-override $verbose_flag)
    (test-platform-specific-partial-git-source-override $verbose_flag)
    (test-empty-source-override-preserves-all-fields-from-defaults $verbose_flag)
  ]

  print-test-summary $results

  if ($results | all {|r| $r}) {
    exit 0
  } else {
    exit 1
  }
}
