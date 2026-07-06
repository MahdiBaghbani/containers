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

# scan-docs purity: line numbers and missing-path behavior.

use ../../lib/docs/lint.nu [scan-docs get-prohibited-patterns]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def scan-docs-tests [verbose: bool] {
    let prohibited = (get-prohibited-patterns)
    [
        (run-test "scan-docs: reports correct line numbers" {
            let raw = $"clean line\nbad \u{2014} line\n"
            let file = (make-fixture $raw)
            let violations = (scan-docs [$file] $prohibited)
            let after = (open --raw $file)
            cleanup-fixture $file
            if ($violations | length) != 1 { error make {msg: $"expected 1 violation, got ($violations | length)"} }
            if $violations.0.line != 2 { error make {msg: $"expected violation on line 2, got ($violations.0.line)"} }
            if $after != $raw { error make {msg: "scan-docs must not modify the file"} }
            true
        } $verbose)
        (run-test "scan-docs: missing path yields empty violations without erroring" {
            # scan-docs is pure: a missing path returns [] (missing-path reporting
            # is lint-docs's job), so it must not throw or print an error.
            let dir = (mktemp -d)
            let missing = ($dir | path join "absent.md")
            let clean = ($dir | path join "ok.md")
            "# Title\n\nclean ascii\n" | save -f $clean
            let violations = (scan-docs [$missing $clean] $prohibited)
            rm -rf $dir
            if not ($violations | is-empty) {
                error make {msg: $"expected empty violations, got ($violations | length)"}
            }
            true
        } $verbose)
    ]
}
