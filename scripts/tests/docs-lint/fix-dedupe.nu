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

# Dedupe + rescan: many occurrences of the same pattern.

use ../../lib/docs/lint.nu [lint-docs]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def fix-dedupe-tests [verbose: bool] {
    [
        (run-test "fix: dedupes repeated pattern and rescans clean" {
            let line = $"q \u{2019} w \u{2019} e\n"
            let raw = ($"($line)($line)($line)($line)")
            let file = (make-fixture $raw)
            let ok = (lint-docs [$file] true)
            let after = (open --raw $file)
            cleanup-fixture $file
            if not $ok { error make {msg: "expected dedup fix to succeed"} }
            if not ($after | str contains "q ' w ' e") {
                error make {msg: $"expected apostrophes normalized, got: ($after)"}
            }
            true
        } $verbose)
    ]
}
