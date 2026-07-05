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

# Fix: replace all occurrences on one line and across multiple lines.

use ../../lib/docs/lint.nu [lint-docs scan-docs get-prohibited-patterns]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def fix-replace-tests [verbose: bool] {
    let prohibited = (get-prohibited-patterns)
    [
        (run-test "fix: replaces all occurrences on a single line" {
            # Three em dashes on one line; the old first-only behavior would leave two.
            let raw = $"a \u{2014} b \u{2014} c \u{2014} d\n"
            let file = (make-fixture $raw)
            let ok = (lint-docs [$file] true)
            let after = (open --raw $file)
            let remaining = (scan-docs [$file] $prohibited)
            cleanup-fixture $file
            if not $ok { error make {msg: "expected fix to succeed and rescan clean"} }
            if not ($after | str contains "a - b - c - d") {
                error make {msg: $"expected all em dashes replaced, got: ($after)"}
            }
            if not ($remaining | is-empty) { error make {msg: "rescan should find no remaining violations"} }
            true
        } $verbose)
        (run-test "fix: replaces all occurrences across multiple lines" {
            let raw = $"line one \u{2014} x\nline two \u{2014} y\nline three \u{2014} z\n"
            let file = (make-fixture $raw)
            let ok = (lint-docs [$file] true)
            let remaining = (scan-docs [$file] $prohibited)
            cleanup-fixture $file
            if not $ok { error make {msg: "expected multi-line fix to succeed"} }
            if not ($remaining | is-empty) { error make {msg: "expected no remaining violations across lines"} }
            true
        } $verbose)
    ]
}
