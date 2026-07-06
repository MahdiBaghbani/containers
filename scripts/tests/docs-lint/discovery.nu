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

# Default discovery: repo-wide scan and explicit ignored-path linting.

use ../../lib/docs/lint.nu [lint-docs]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-git-discovery-fixture]

export def discovery-tests [verbose: bool] {
    [
        (run-test "discovery: default scan skips ignored markdown" {
            let repo = (make-git-discovery-fixture)
            let cwd_before = ($env.PWD | default (pwd))
            cd $repo
            let ok = (lint-docs [] false)
            cd $cwd_before
            rm -rf $repo
            if not $ok {
                error make {msg: "expected default repo-wide scan to ignore ignored markdown files"}
            }
            true
        } $verbose)
        (run-test "discovery: explicit ignored markdown path still lints" {
            let repo = (make-git-discovery-fixture)
            let ignored = ($repo | path join ".build-sources/vendor/README.md")
            let ok = (lint-docs [$ignored] false)
            rm -rf $repo
            if $ok {
                error make {msg: "expected explicit ignored markdown file to still be linted"}
            }
            true
        } $verbose)
    ]
}
