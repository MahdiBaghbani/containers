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

# Missing explicit paths: alone and mixed with valid paths.

use ../../lib/docs/lint.nu [lint-docs]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def missing-paths-tests [verbose: bool] {
    [
        (run-test "lint: missing explicit path fails (not treated as clean)" {
            let dir = (mktemp -d)
            let missing = ($dir | path join "does-not-exist.md")
            let ok = (lint-docs [$missing] false)
            rm -rf $dir
            if $ok { error make {msg: "expected missing explicit path to fail lint-docs"} }
            true
        } $verbose)
        (run-test "lint: missing explicit path fails even when other files are clean" {
            let file = (make-fixture "# Title\n\nclean ascii\n")
            let missing = ($file | path dirname | path join "absent.md")
            let ok = (lint-docs [$file $missing] false)
            cleanup-fixture $file
            if $ok { error make {msg: "expected lint-docs to fail when an explicit path is missing"} }
            true
        } $verbose)
    ]
}
