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

# Banned-category coverage (writing-rule parity).

use ../../lib/docs/lint.nu [lint-docs scan-docs get-prohibited-patterns]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def category-coverage-tests [verbose: bool] {
    let prohibited = (get-prohibited-patterns)

    # {label, raw, anchors-that-must-survive}
    let category_cases = [
        {label: "emoticon (astral block)", raw: $"alpha \u{1F600} omega", anchors: ["alpha" "omega"]}
        {label: "rocket pictograph (astral block)", raw: $"ship \u{1F680} now", anchors: ["ship" "now"]}
        {label: "fire pictograph (astral block)", raw: $"very \u{1F525} hot", anchors: ["very" "hot"]}
        {label: "miscellaneous symbol (hot beverage)", raw: $"take a \u{2615} break", anchors: ["take a" "break"]}
        {label: "dingbat (white heavy check)", raw: $"all \u{2705} done", anchors: ["all" "done"]}
        {label: "symbols-and-arrows (heavy large circle)", raw: $"mark \u{2B55} spot", anchors: ["mark" "spot"]}
        {label: "variation selector", raw: $"x\u{FE0F}y", anchors: ["x" "y"]}
    ]

    mut results = []
    for c in $category_cases {
        let t = (run-test $"category: ($c.label) detected via regex and stripped" {
            let file = (make-fixture ($"($c.raw)\n"))
            # Detected, and specifically by a regex-kind category rule.
            let pre = (scan-docs [$file] $prohibited)
            if ($pre | where kind == "regex" | is-empty) {
                cleanup-fixture $file
                error make {msg: $"expected ($c.label) caught by a regex category"}
            }
            # Fixed; rescan clean and ASCII anchors preserved.
            let ok = (lint-docs [$file] true)
            let after = (open --raw $file)
            let remaining = (scan-docs [$file] $prohibited)
            cleanup-fixture $file
            if not $ok { error make {msg: $"expected fix success for ($c.label)"} }
            if not ($remaining | is-empty) {
                error make {msg: $"expected no remaining violations for ($c.label)"}
            }
            for anchor in $c.anchors {
                if not ($after | str contains $anchor) {
                    error make {msg: $"expected '($anchor)' to survive fixing ($c.label), got: ($after)"}
                }
            }
            true
        } $verbose)
        $results = ($results | append $t)
    }
    $results
}
