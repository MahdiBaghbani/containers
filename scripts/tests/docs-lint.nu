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

# Docs lint offline unit tests.
# Uses temp-file fixtures; forbidden characters are built from \u{...} escapes
# so this test source stays plain ASCII.  No network or disk scanning of the
# repo: every test passes explicit file paths to lint-docs / scan-docs.

use ./lib.nu [print-test-summary]
use ./docs-lint/detection.nu [detection-tests]
use ./docs-lint/missing-paths.nu [missing-paths-tests]
use ./docs-lint/fix-replace.nu [fix-replace-tests]
use ./docs-lint/fix-dedupe.nu [fix-dedupe-tests]
use ./docs-lint/pattern-coverage.nu [pattern-coverage-tests]
use ./docs-lint/category-coverage.nu [category-coverage-tests]
use ./docs-lint/discovery.nu [discovery-tests]
use ./docs-lint/scan-docs.nu [scan-docs-tests]

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    $results = ($results | append (detection-tests $verbose_flag))
    $results = ($results | append (missing-paths-tests $verbose_flag))
    $results = ($results | append (fix-replace-tests $verbose_flag))
    $results = ($results | append (fix-dedupe-tests $verbose_flag))
    $results = ($results | append (pattern-coverage-tests $verbose_flag))
    $results = ($results | append (category-coverage-tests $verbose_flag))
    $results = ($results | append (discovery-tests $verbose_flag))
    $results = ($results | append (scan-docs-tests $verbose_flag))

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
