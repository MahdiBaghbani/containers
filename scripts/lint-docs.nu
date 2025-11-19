#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Lint documentation files for writing rule violations
# Checks for prohibited emojis and Unicode characters in markdown files

def main [
    ...files: string  # Files to check (default: all .md files in docs/ and root)
    --fix  # Attempt to fix violations automatically
] {
    let fix_mode = $fix
    let files_to_check = (if ($files | length) > 0 {
        $files
    } else {
        (glob "**/*.md" | where {|f| not ($f | str contains "/.git/")})
    })
    
    mut violations = []
    mut total_violations = 0
    
    # Prohibited characters and their replacements
    let prohibited = [
        {pattern: "⚠️", name: "Warning emoji", replacement: "WARNING:"},
        {pattern: "✓", name: "Checkmark emoji", replacement: "OK:"},
        {pattern: "❌", name: "X mark emoji", replacement: "ERROR:"},
        {pattern: "→", name: "Unicode right arrow", replacement: "->"},
        {pattern: "←", name: "Unicode left arrow", replacement: "<-"},
        {pattern: "ℹ️", name: "Info emoji", replacement: "INFO:"},
        {pattern: "🔍", name: "Magnifying glass emoji", replacement: ""},
        {pattern: "📝", name: "Memo emoji", replacement: ""},
        {pattern: "📚", name: "Books emoji", replacement: ""},
        {pattern: "✨", name: "Sparkles emoji", replacement: ""},
        {pattern: "⭐", name: "Star emoji", replacement: ""},
        {pattern: "🎯", name: "Target emoji", replacement: ""},
    ]
    
    for file in $files_to_check {
        if not ($file | path exists) {
            print $"ERROR: File not found: ($file)"
            continue
        }
        
        let content = (open $file)
        let lines = ($content | lines | enumerate)
        
        for line_data in $lines {
            let line_num = ($line_data.index + 1)
            let line = $line_data.item
            
            for prohibited_char in $prohibited {
                if ($line | str contains $prohibited_char.pattern) {
                    $violations = ($violations | append {
                        file: $file,
                        line: $line_num,
                        char: $prohibited_char.name,
                        pattern: $prohibited_char.pattern,
                        replacement: $prohibited_char.replacement,
                        context: ($line | str substring 0..<([($line | str length), 80] | math min))
                    })
                    $total_violations = ($total_violations + 1)
                }
            }
        }
    }
    
    if ($violations | is-empty) {
        print "OK: No writing rule violations found"
        return
    }
    
    let violation_count = ($total_violations | into string)
    print $"ERROR: Found ($violation_count) writing rule violation\(s\):"
    print ""
    
    for violation in $violations {
        print $"  ($violation.file):($violation.line)"
        print $"    Found: ($violation.char) '($violation.pattern)'"
        print $"    Replace with: '($violation.replacement)'"
        print $"    Context: ...($violation.context)..."
        print ""
    }
    
    if $fix_mode {
        print "Attempting to fix violations..."
        for violation in $violations {
            let file_content = (open $violation.file)
            let fixed_content = ($file_content | str replace $violation.pattern $violation.replacement)
            $fixed_content | save -f $violation.file
            print $"  Fixed: ($violation.file):($violation.line)"
        }
        print "OK: Fixes applied. Please review changes."
    } else {
        print "Run with --fix to automatically fix violations"
    }
    
    exit 1
}
