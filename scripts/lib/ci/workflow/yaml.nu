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

# YAML generation utilities for GitHub Actions workflows

# Indent text by a given level (2 spaces per level)
export def indent [text: string, level: int] {
    let prefix = (1..$level | each {|_| "  " } | str join "")
    $text | lines | each {|line|
        if ($line | str trim | str length) > 0 {
            $"($prefix)($line)"
        } else {
            ""
        }
    } | str join "\n"
}

# Convert a step record to YAML string
export def yaml-step [step: record] {
    mut lines = []
    
    $lines = ($lines | append $"- name: ($step.name)")
    
    if "id" in ($step | columns) {
        $lines = ($lines | append $"  id: ($step.id)")
    }
    
    if "if" in ($step | columns) {
        $lines = ($lines | append $"  if: ($step.if)")
    }
    
    if "uses" in ($step | columns) {
        $lines = ($lines | append $"  uses: ($step.uses)")
    }
    
    if "with" in ($step | columns) {
        $lines = ($lines | append "  with:")
        for kv in ($step.with | transpose key value) {
            let val = $kv.value
            if ($val | describe | str starts-with "string") and ($val | str contains "\n") {
                $lines = ($lines | append $"    ($kv.key): |")
                for vline in ($val | lines) {
                    $lines = ($lines | append $"      ($vline)")
                }
            } else {
                $lines = ($lines | append $"    ($kv.key): ($val)")
            }
        }
    }
    
    if "env" in ($step | columns) {
        $lines = ($lines | append "  env:")
        for kv in ($step.env | transpose key value) {
            $lines = ($lines | append $"    ($kv.key): ($kv.value)")
        }
    }
    
    if "run" in ($step | columns) {
        let run_lines = ($step.run | lines)
        if ($run_lines | length) == 1 {
            $lines = ($lines | append $"  run: ($step.run)")
        } else {
            $lines = ($lines | append "  run: |")
            for rline in $run_lines {
                $lines = ($lines | append $"    ($rline)")
            }
        }
    }
    
    $lines | str join "\n"
}

# Convert a list of step records to YAML string
export def yaml-steps [steps: list] {
    $steps | each {|s| yaml-step $s } | str join "\n\n"
}
