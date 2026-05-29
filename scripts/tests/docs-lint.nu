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

use ../lib/docs/lint.nu [lint-docs scan-docs get-prohibited-patterns]
use ./lib.nu [run-test print-test-summary]

# Write raw content to a fresh temp .md file and return its path.
def make-fixture [content: string] {
    let dir = (mktemp -d)
    let file = ($dir | path join "doc.md")
    $content | save -f $file
    $file
}

# Remove a fixture file and its temp directory.
def cleanup-fixture [file: string] {
    let dir = ($file | path dirname)
    rm -rf $dir
}

def make-git-discovery-fixture [] {
    let dir = (mktemp -d)

    mkdir ($dir | path join "docs")
    mkdir ($dir | path join ".build-sources/vendor")
    mkdir ($dir | path join "node_modules/pkg")

    "# Repo doc\n\nclean ascii\n" | save -f ($dir | path join "README.md")
    "# Guide\n\nclean ascii\n" | save -f ($dir | path join "docs/guide.md")
    $"ignored \u{2014} generated\n" | save -f ($dir | path join ".build-sources/vendor/README.md")
    $"ignored \u{2014} vendor\n" | save -f ($dir | path join "node_modules/pkg/README.md")

    ".build-sources/\nnode_modules/\n" | save -f ($dir | path join ".gitignore")

    let init = (^git -C $dir init --quiet | complete)
    if $init.exit_code != 0 {
        rm -rf $dir
        error make {msg: $"git init failed: ($init.stderr)"}
    }

    let add = (^git -C $dir add README.md docs/guide.md .gitignore | complete)
    if $add.exit_code != 0 {
        rm -rf $dir
        error make {msg: $"git add failed: ($add.stderr)"}
    }

    $dir
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    let prohibited = (get-prohibited-patterns)

    # ------------------------------------------------------------------ #
    # Detection: clean vs dirty
    # ------------------------------------------------------------------ #

    let t_clean = (run-test "lint: clean file reports success" {
        let file = (make-fixture "# Title\n\nPlain ASCII content -> ok.\n")
        let ok = (lint-docs [$file] false)
        cleanup-fixture $file
        if not $ok { error make {msg: "expected clean file to return true"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_clean)

    let t_dirty_noscan = (run-test "lint: violation without --fix returns false and does not modify file" {
        let raw = $"intro \u{2014} outro\n"
        let file = (make-fixture $raw)
        let ok = (lint-docs [$file] false)
        let after = (open --raw $file)
        cleanup-fixture $file
        if $ok { error make {msg: "expected dirty file to return false"} }
        if $after != $raw { error make {msg: "file must be unchanged without --fix"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_dirty_noscan)

    # ------------------------------------------------------------------ #
    # Missing explicit paths: hard failure, not silently clean
    # ------------------------------------------------------------------ #

    let t_missing_only = (run-test "lint: missing explicit path fails (not treated as clean)" {
        let dir = (mktemp -d)
        let missing = ($dir | path join "does-not-exist.md")
        let ok = (lint-docs [$missing] false)
        rm -rf $dir
        if $ok { error make {msg: "expected missing explicit path to fail lint-docs"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_missing_only)

    let t_missing_with_clean = (run-test "lint: missing explicit path fails even when other files are clean" {
        let file = (make-fixture "# Title\n\nclean ascii\n")
        let missing = ($file | path dirname | path join "absent.md")
        let ok = (lint-docs [$file $missing] false)
        cleanup-fixture $file
        if $ok { error make {msg: "expected lint-docs to fail when an explicit path is missing"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_missing_with_clean)

    # ------------------------------------------------------------------ #
    # Fix: replace ALL occurrences (not just the first)
    # ------------------------------------------------------------------ #

    let t_fix_all_inline = (run-test "fix: replaces all occurrences on a single line" {
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
    } $verbose_flag)
    $results = ($results | append $t_fix_all_inline)

    let t_fix_all_multiline = (run-test "fix: replaces all occurrences across multiple lines" {
        let raw = $"line one \u{2014} x\nline two \u{2014} y\nline three \u{2014} z\n"
        let file = (make-fixture $raw)
        let ok = (lint-docs [$file] true)
        let remaining = (scan-docs [$file] $prohibited)
        cleanup-fixture $file
        if not $ok { error make {msg: "expected multi-line fix to succeed"} }
        if not ($remaining | is-empty) { error make {msg: "expected no remaining violations across lines"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_fix_all_multiline)

    # ------------------------------------------------------------------ #
    # Dedupe + rescan: many occurrences of the same pattern
    # ------------------------------------------------------------------ #

    let t_dedupe = (run-test "fix: dedupes repeated pattern and rescans clean" {
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
    } $verbose_flag)
    $results = ($results | append $t_dedupe)

    # ------------------------------------------------------------------ #
    # Expanded forbidden-pattern coverage (writing-rule parity)
    # Each case: detected as a violation, then fixed to its ASCII form.
    # ------------------------------------------------------------------ #

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
        } $verbose_flag)
        $results = ($results | append $t)
    }

    # ------------------------------------------------------------------ #
    # Banned-category coverage (writing-rule parity)
    # These codepoints are NOT in the hand-picked literal list; they must be
    # caught by the broad Unicode-range categories, reported with kind "regex",
    # then stripped so the rescan is clean and surrounding ASCII survives.
    # ------------------------------------------------------------------ #

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
        } $verbose_flag)
        $results = ($results | append $t)
    }

    # ------------------------------------------------------------------ #
    # Default discovery: repo-wide scan should respect git ignore rules,
    # while explicit file lists still lint the file asked for.
    # ------------------------------------------------------------------ #

    let t_default_discovery = (run-test "discovery: default scan skips ignored markdown" {
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
    } $verbose_flag)
    $results = ($results | append $t_default_discovery)

    let t_explicit_ignored = (run-test "discovery: explicit ignored markdown path still lints" {
        let repo = (make-git-discovery-fixture)
        let ignored = ($repo | path join ".build-sources/vendor/README.md")
        let ok = (lint-docs [$ignored] false)
        rm -rf $repo
        if $ok {
            error make {msg: "expected explicit ignored markdown file to still be linted"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_explicit_ignored)

    # ------------------------------------------------------------------ #
    # scan-docs purity: returns violation records with line numbers
    # ------------------------------------------------------------------ #

    let t_scan_lines = (run-test "scan-docs: reports correct line numbers" {
        let raw = $"clean line\nbad \u{2014} line\n"
        let file = (make-fixture $raw)
        let violations = (scan-docs [$file] $prohibited)
        let after = (open --raw $file)
        cleanup-fixture $file
        if ($violations | length) != 1 { error make {msg: $"expected 1 violation, got ($violations | length)"} }
        if $violations.0.line != 2 { error make {msg: $"expected violation on line 2, got ($violations.0.line)"} }
        if $after != $raw { error make {msg: "scan-docs must not modify the file"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_scan_lines)

    let t_scan_missing_pure = (run-test "scan-docs: missing path yields empty violations without erroring" {
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
    } $verbose_flag)
    $results = ($results | append $t_scan_missing_pure)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
