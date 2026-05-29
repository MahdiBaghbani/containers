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

# Documentation linting - checks for prohibited characters in markdown files.
# The forbidden set mirrors the workspace writing rule: no emojis, Unicode
# arrows, en/em dashes, curly quotes and apostrophes, ellipsis, or non-breaking
# spaces.  Patterns use \u{...} / regex \x{...} escapes so this source stays
# plain ASCII.
#
# Two pattern kinds are supported:
#   - "literal": exact substring match (str contains / str replace --all).
#     Used for punctuation that maps to a meaningful ASCII replacement, plus a
#     few well-known status emojis that map to words (WARNING:, INFO:, ...).
#   - "regex": Unicode-range match (=~ / str replace --regex).  Used to ban
#     whole categories (emojis and decorative symbols) instead of hand-picked
#     codepoints; decorative glyphs are stripped (empty replacement).

# Prohibited characters/categories and their ASCII replacements.
# Records without a "kind" field default to "literal".
export def get-prohibited-patterns [] {
  [
    # --- Known status emojis with meaningful word replacements --- #
    {pattern: "\u{26A0}\u{FE0F}", name: "Warning emoji", replacement: "WARNING:"},
    {pattern: "\u{26A0}", name: "Warning sign", replacement: "WARNING:"},
    {pattern: "\u{2139}\u{FE0F}", name: "Info emoji", replacement: "INFO:"},
    {pattern: "\u{2713}", name: "Checkmark", replacement: "OK:"},
    {pattern: "\u{2714}", name: "Heavy checkmark", replacement: "OK:"},
    {pattern: "\u{274C}", name: "X mark emoji", replacement: "ERROR:"},
    # Unicode arrows
    {pattern: "\u{2194}", name: "Unicode left-right arrow", replacement: "<->"},
    {pattern: "\u{2192}", name: "Unicode right arrow", replacement: "->"},
    {pattern: "\u{2190}", name: "Unicode left arrow", replacement: "<-"},
    # Dashes (em before en is irrelevant; both are single distinct codepoints)
    {pattern: "\u{2014}", name: "Em dash", replacement: "-"},
    {pattern: "\u{2013}", name: "En dash", replacement: "-"},
    # Curly quotation marks and apostrophes
    {pattern: "\u{201C}", name: "Left double quotation mark", replacement: "\""},
    {pattern: "\u{201D}", name: "Right double quotation mark", replacement: "\""},
    {pattern: "\u{2018}", name: "Left single quotation mark", replacement: "'"},
    {pattern: "\u{2019}", name: "Right single quotation mark", replacement: "'"},
    # Ellipsis and non-breaking space
    {pattern: "\u{2026}", name: "Horizontal ellipsis", replacement: "..."},
    {pattern: "\u{00A0}", name: "Non-breaking space", replacement: " "},

    # --- Banned categories (emojis and decorative symbols) --- #
    # Range matches catch any glyph in the category, not just sampled
    # codepoints.  These run after the literals above, so known status emojis
    # keep their word replacement; everything else is stripped.
    {kind: "regex", pattern: '[\x{1F000}-\x{1FAFF}]', name: "Emoji or pictograph", replacement: ""},
    {kind: "regex", pattern: '[\x{2600}-\x{26FF}]', name: "Miscellaneous symbol", replacement: ""},
    {kind: "regex", pattern: '[\x{2700}-\x{27BF}]', name: "Dingbat symbol", replacement: ""},
    {kind: "regex", pattern: '[\x{2B00}-\x{2BFF}]', name: "Decorative symbol or arrow", replacement: ""},
    {kind: "regex", pattern: '[\x{FE00}-\x{FE0F}]', name: "Variation selector", replacement: ""},
  ]
}

# Find violations in a single file.  Returns a list of violation records
# (one per matching line per pattern); empty list when the file is clean or
# missing.  Side-effect free: missing-path reporting is the caller's job
# (lint-docs guards explicit paths before scanning).
def find-violations-in-file [file: string, prohibited: list] {
  if not ($file | path exists) {
    return []
  }

  # --raw so .md files are read as text, not parsed into a markdown table.
  let lines = (open --raw $file | lines | enumerate)

  $lines | each {|line_data|
    let line_num = ($line_data.index + 1)
    let line = $line_data.item

    $prohibited | each {|prohibited_char|
      let kind = ($prohibited_char.kind? | default "literal")
      let matched = if $kind == "regex" {
        $line =~ $prohibited_char.pattern
      } else {
        $line | str contains $prohibited_char.pattern
      }
      if $matched {
        {
          file: $file,
          line: $line_num,
          kind: $kind,
          char: $prohibited_char.name,
          pattern: $prohibited_char.pattern,
          replacement: $prohibited_char.replacement,
          context: ($line | str substring 0..<([($line | str length), 80] | math min))
        }
      }
    }
  } | flatten | where {|v| $v != null}
}

# Scan files for prohibited characters (pure: no printing, no fixing).
# Returns the full violation list across all files.
export def scan-docs [files: list<string>, prohibited: list] {
  $files | each {|file|
    find-violations-in-file $file $prohibited
  } | flatten
}

# Discover default markdown files from git so repo-wide scans respect ignore
# rules and skip generated/vendor trees such as .build-sources/ and
# node_modules/.  Fallback to glob when not inside a git repo.
def discover-default-files [] {
  let repo_root_result = (try {
    ^git rev-parse --show-toplevel | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: ""}
  })

  if $repo_root_result.exit_code != 0 {
    return (glob "**/*.md" | where {|f| not ($f | str contains "/.git/")})
  }

  let repo_root = ($repo_root_result.stdout | str trim)
  let ls_files_result = (try {
    ^git -C $repo_root ls-files --cached --others --exclude-standard -- "*.md" | complete
  } catch {
    {exit_code: 1, stdout: "", stderr: ""}
  })

  if $ls_files_result.exit_code != 0 {
    return (glob "**/*.md" | where {|f| not ($f | str contains "/.git/")})
  }

  $ls_files_result.stdout
  | lines
  | where {|line| not ($line | is-empty)}
  | each {|line| $repo_root | path join $line}
}

# Resolve the set of files to lint (explicit list, or default repo markdown).
def resolve-files [files: list<string>] {
  if ($files | is-empty) {
    discover-default-files
  } else {
    $files
  }
}

# Print a violation report block.
def print-violations [violations: list] {
  let violation_count = ($violations | length)
  print $"ERROR: Found ($violation_count) writing rule violation\(s\):"
  print ""

  for violation in $violations {
    print $"  ($violation.file):($violation.line)"
    print $"    Found: ($violation.char) '($violation.pattern)'"
    print $"    Replace with: '($violation.replacement)'"
    print $"    Context: ...($violation.context)..."
    print ""
  }
}

# Apply fixes for one file: replace ALL occurrences of every distinct pattern
# found in that file.  Patterns are deduped so each replacement runs once.
def fix-file [file: string, file_violations: list] {
  let patterns = ($file_violations | select kind pattern replacement | uniq)
  mut content = (open --raw $file)
  for p in $patterns {
    if $p.kind == "regex" {
      $content = ($content | str replace --all --regex $p.pattern $p.replacement)
    } else {
      $content = ($content | str replace --all $p.pattern $p.replacement)
    }
  }
  $content | save -f $file
}

# Lint documentation files for prohibited characters.
# Returns true only when the files are clean (no violations, or all violations
# fixed and confirmed clean by a rescan).
export def lint-docs [
  files: list<string> = [],  # Files to check (empty = all .md files)
  fix: bool = false          # Attempt to fix violations automatically
] {
  # Explicit paths must exist. A missing explicit path is a hard failure, not a
  # silently-clean result. Default discovery (empty $files) only yields files
  # that already exist, so the check is scoped to explicit lists.
  if not ($files | is-empty) {
    let missing = ($files | where {|f| not ($f | path exists)})
    if not ($missing | is-empty) {
      for f in $missing {
        print $"ERROR: File not found: ($f)"
      }
      return false
    }
  }

  let files_to_check = (resolve-files $files)
  let prohibited = (get-prohibited-patterns)

  let violations = (scan-docs $files_to_check $prohibited)

  if ($violations | is-empty) {
    print "OK: No writing rule violations found"
    return true
  }

  print-violations $violations

  if not $fix {
    print "Run with --fix to automatically fix violations"
    return false
  }

  print "Attempting to fix violations..."
  let files_with_violations = ($violations | get file | uniq)
  for file in $files_with_violations {
    let file_violations = ($violations | where {|v| $v.file == $file})
    fix-file $file $file_violations
    print $"  Fixed: ($file)"
  }

  # Rescan after fixing; success is reported only when the rescan is clean.
  let remaining = (scan-docs $files_with_violations $prohibited)
  if ($remaining | is-empty) {
    print "OK: All writing rule violations fixed"
    return true
  }

  print ""
  print $"ERROR: ($remaining | length) violation\(s\) remain after fix:"
  print-violations $remaining
  false
}
