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

# Expanded forbidden-pattern coverage (writing-rule parity).

use ../../lib/docs/lint.nu [lint-docs scan-docs get-prohibited-patterns]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-fixture cleanup-fixture]

export def pattern-coverage-tests [verbose: bool] {
    let prohibited = (get-prohibited-patterns)

    # {label, raw, expected-substring}
    let cases = [
        {label: "em dash", raw: $"x \u{2014} y", want: "x - y"}
        {label: "en dash", raw: $"x \u{2013} y", want: "x - y"}
        {label: "left double quote", raw: $"say \u{201C}hi", want: "say \"hi"}
        {label: "right double quote", raw: $"hi\u{201D} there", want: "hi\" there"}
        {label: "left single quote", raw: $"\u{2018}quoted", want: "'quoted"}
        {label: "right single quote/apostrophe", raw: $"it\u{2019}s", want: "it's"}
        {label: "ellipsis", raw: $"wait\u{2026}done", want: "wait...done"}
        {label: "non-breaking space", raw: $"a\u{00A0}b", want: "a b"}
        {label: "right arrow", raw: $"a \u{2192} b", want: "a -> b"}
        {label: "left arrow", raw: $"a \u{2190} b", want: "a <- b"}
        {label: "left-right arrow", raw: $"a \u{2194} b", want: "a <-> b"}
    ]

    mut results = []
    for c in $cases {
        let t = (run-test $"pattern: ($c.label) detected and fixed to ASCII" {
            let file = (make-fixture ($"($c.raw)\n"))
            # Detected before fix
            let pre = (scan-docs [$file] $prohibited)
            if ($pre | is-empty) {
                cleanup-fixture $file
                error make {msg: $"expected ($c.label) to be detected"}
            }
            # Fixed and clean after
            let ok = (lint-docs [$file] true)
            let after = (open --raw $file)
            let remaining = (scan-docs [$file] $prohibited)
            cleanup-fixture $file
            if not $ok { error make {msg: $"expected fix success for ($c.label)"} }
            if not ($after | str contains $c.want) {
                error make {msg: $"expected '($c.want)' after fixing ($c.label), got: ($after)"}
            }
            if not ($remaining | is-empty) {
                error make {msg: $"expected no remaining violations for ($c.label)"}
            }
            true
        } $verbose)
        $results = ($results | append $t)
    }
    $results
}
