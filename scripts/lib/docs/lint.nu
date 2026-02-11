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

# Documentation linting - checks for prohibited characters in markdown files

# Prohibited characters and their replacements
def get-prohibited-patterns [] {
  [
    {pattern: "⚠️", name: "Warning emoji", replacement: "WARNING:"},
    {pattern: "✓", name: "Checkmark emoji", replacement: "OK:"},
    {pattern: "❌", name: "X mark emoji", replacement: "ERROR:"},
    {pattern: "→", name: "Unicode right arrow", replacement: "->"},
    {pattern: "←", name: "Unicode left arrow", replacement: "<-"},
    {pattern: "↔", name: "Unicode left-right arrow", replacement: "<->"},
    {pattern: "ℹ️", name: "Info emoji", replacement: "INFO:"},
    {pattern: "🔍", name: "Magnifying glass emoji", replacement: ""},
    {pattern: "📝", name: "Memo emoji", replacement: ""},
    {pattern: "📚", name: "Books emoji", replacement: ""},
    {pattern: "✨", name: "Sparkles emoji", replacement: ""},
    {pattern: "⭐", name: "Star emoji", replacement: ""},
    {pattern: "🎯", name: "Target emoji", replacement: ""},
    {pattern: "—", name: "Em dash", replacement: "-"},
    {pattern: "\u{201C}", name: "Left double quotation mark", replacement: "\""},
    {pattern: "\u{201D}", name: "Right double quotation mark", replacement: "\""},
  ]
}

# Find violations in a single file
def find-violations-in-file [file: string, prohibited: list] {
  if not ($file | path exists) {
    print $"ERROR: File not found: ($file)"
    return []
  }
  
  let content = (open $file)
  let lines = ($content | lines | enumerate)
  
  # Collect violations for this file
  $lines | each {|line_data|
    let line_num = ($line_data.index + 1)
    let line = $line_data.item
    
    $prohibited | each {|prohibited_char|
      if ($line | str contains $prohibited_char.pattern) {
        {
          file: $file,
          line: $line_num,
          char: $prohibited_char.name,
          pattern: $prohibited_char.pattern,
          replacement: $prohibited_char.replacement,
          context: ($line | str substring 0..<([($line | str length), 80] | math min))
        }
      }
    }
  } | flatten | where {|v| $v != null}
}

# Lint documentation files for prohibited characters
export def lint-docs [
  files: list<string> = [],  # Files to check (empty = all .md files)
  fix: bool = false          # Attempt to fix violations automatically
] {
  let files_to_check = (if ($files | is-empty) {
    (glob "**/*.md" | where {|f| not ($f | str contains "/.git/")})
  } else {
    $files
  })
  
  let prohibited = (get-prohibited-patterns)
  
  # Collect all violations
  let violations = ($files_to_check | each {|file|
    find-violations-in-file $file $prohibited
  } | flatten)
  
  if ($violations | is-empty) {
    print "OK: No writing rule violations found"
    return true
  }
  
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
  
  if $fix {
    print "Attempting to fix violations..."
    # Group violations by file and fix each file once
    let files_with_violations = ($violations | get file | uniq)
    for file in $files_with_violations {
      let file_violations = ($violations | where {|v| $v.file == $file})
      mut content = (open $file)
      for violation in $file_violations {
        $content = ($content | str replace $violation.pattern $violation.replacement)
      }
      $content | save -f $file
      print $"  Fixed: ($file)"
    }
    print "OK: Fixes applied. Please review changes."
  } else {
    print "Run with --fix to automatically fix violations"
  }
  
  false  # Return false to indicate violations found
}
