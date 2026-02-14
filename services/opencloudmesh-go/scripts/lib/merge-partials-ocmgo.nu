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

# Minimal partial config merge for ocm-go
# Simplified from services/revad-base/scripts/lib/merge-partials.nu

export def merge_partial_configs [config_dir: string, partials_dir: string] {
  if not ($partials_dir | path exists) {
    return
  }

  let files = (try {
    ls $partials_dir | where type == file | where {|f| ($f.name | str ends-with ".toml")} | get name
  } catch {
    []
  })

  if ($files | length) == 0 {
    return
  }

  mut merged_count = 0

  for file in $files {
    let content = (open --raw $file)

    let parsed = (try {
      open $file
    } catch {|err|
      error make {msg: $"Failed to parse TOML partial ($file): (try { $err.msg } catch { 'unknown error' })"}
    })

    let target_section = (try {
      $parsed | get "target"
    } catch {
      error make {msg: $"Missing [target] section in partial: ($file)"}
    })

    let target_file = (try {
      $target_section | get "file"
    } catch {
      error make {msg: $"Missing 'file' key in [target] section: ($file)"}
    })

    let target_path = $"($config_dir)/($target_file)"
    if not ($target_path | path exists) {
      error make {msg: $"Target config file not found: ($target_path)"}
    }

    # Strip [target] section from raw content
    let lines = ($content | split row "\n")
    mut result_lines = []
    mut in_target_section = false

    for line in $lines {
      let trimmed = ($line | str trim)

      if ($trimmed == "[target]") {
        $in_target_section = true
        continue
      }

      if $in_target_section {
        if ($trimmed | str starts-with "[") {
          $in_target_section = false
          $result_lines = ($result_lines | append $line)
        } else if ($trimmed | is-empty) {
          continue
        } else {
          continue
        }
      } else {
        $result_lines = ($result_lines | append $line)
      }
    }

    let partial_content = ($result_lines | str join "\n" | str trim)
    if ($partial_content | str length) == 0 {
      continue
    }

    let existing = (open --raw $target_path)
    let new_content = ($existing + "\n" + $partial_content + "\n")
    $new_content | save -f $target_path

    $merged_count = $merged_count + 1
  }

  if $merged_count > 0 {
    print $"Merged ($merged_count) partial config\(s\) into ($config_dir)"
  }
}
