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

# Detection: clean vs dirty files without --fix.

use ../../lib/docs/lint.nu [lint-docs]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def detection-tests [verbose: bool] {
    [
        (run-test "lint: clean file reports success" {
            let file = (make-fixture "# Title\n\nPlain ASCII content -> ok.\n")
            let ok = (lint-docs [$file] false)
            cleanup-fixture $file
            if not $ok { error make {msg: "expected clean file to return true"} }
            true
        } $verbose)
        (run-test "lint: violation without --fix returns false and does not modify file" {
            let raw = $"intro \u{2014} outro\n"
            let file = (make-fixture $raw)
            let ok = (lint-docs [$file] false)
            let after = (open --raw $file)
            cleanup-fixture $file
            if $ok { error make {msg: "expected dirty file to return false"} }
            if $after != $raw { error make {msg: "file must be unchanged without --fix"} }
            true
        } $verbose)
    ]
}
