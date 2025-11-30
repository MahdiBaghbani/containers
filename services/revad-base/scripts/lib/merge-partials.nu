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

# Partial configuration merge functions
# See services/revad-base/docs/partial-config-schema.md for schema documentation

# Parse a partial config file and extract metadata and content
# Returns record with: file (path), target (filename), order (int or null), content (string)
export def parse_partial_file [file_path: string] {
  if not ($file_path | path exists) {
    error make {msg: $"Partial file not found: ($file_path)"}
  }

  let content = (open --raw $file_path)
  let parsed = (try {
    open $file_path
  } catch {|err|
    error make {msg: $"Failed to parse TOML file ($file_path): ($err.msg)"}
  })

  # Extract [target] section
  # TOML parser converts [target] to a nested record key
  let target_section = (try {
    $parsed | get "target"
  } catch {
    error make {msg: $"Missing [target] section in partial file: ($file_path)"}
  })

  let target_file = (try {
    $target_section | get "file"
  } catch {
    error make {msg: $"Missing 'file' field in [target] section: ($file_path)"}
  })

  let order = (try {
    $target_section | get "order"
  } catch {
    null
  })

  # Extract content after [target] section
  # Remove [target] section and its content from the file
  # Strategy: Find [target] section, remove it and everything until next [section] or end of file
  let lines = ($content | split row "\n")
  mut result_lines = []
  mut in_target_section = false
  mut found_target = false

  for line in $lines {
    let trimmed = ($line | str trim)
    
    # Detect start of [target] section
    if ($trimmed == "[target]") {
      $in_target_section = true
      $found_target = true
      continue
    }
    
    # If we're in [target] section, skip lines until we hit a new section or blank line
    if $in_target_section {
      # New section starts (not [target] itself)
      if ($trimmed | str starts-with "[") {
        $in_target_section = false
        # Include this line (it's the start of the actual content)
        $result_lines = ($result_lines | append $line)
      } else if ($trimmed | is-empty) {
        # Blank line might indicate end of [target] section, but continue skipping
        # until we see actual content or new section
        continue
      } else {
        # Still in [target] section, skip this line
        continue
      }
    } else {
      # Not in [target] section, keep this line
      $result_lines = ($result_lines | append $line)
    }
  }

  # If we never found [target], that's an error (should have been caught earlier)
  if not $found_target {
    error make {msg: $"Could not find [target] section in file: ($file_path)"}
  }

  # Join lines and trim
  let partial_content = ($result_lines | str join "\n" | str trim)

  {
    file: $file_path
    target: $target_file
    order: $order
    content: $partial_content
  }
}

# Find all partial files targeting a specific config file
# Scans directories for .toml files, parses each, filters by target
# Returns list of partial records
export def find_partials_for_target [
  target_file: string
  --partials-dirs: list<string> = []  # Directories to scan (e.g., ["/etc/revad/partial", "/configs/partial"])
] {
  mut partials = []

  for dir in $partials_dirs {
    if not ($dir | path exists) {
      continue
    }

    let files = (try {
      ls $dir | where type == file | where {|f| ($f.name | str ends-with ".toml")} | get name
    } catch {
      []
    })

    for file in $files {
      let parsed = (try {
        parse_partial_file $file
      } catch {|err|
        print $"Warning: Failed to parse partial file ($file): ($err.msg)"
        continue
      })

      if $parsed.target == $target_file {
        $partials = ($partials | append $parsed)
      }
    }
  }

  $partials
}

# Sort partials by order: explicit numbers first (numeric), then alphabetical
# Auto-assigns order numbers to unnumbered partials (after highest explicit number)
export def sort_partials_by_order [partials: list<record>] {
  # Separate partials with explicit order from those without
  mut with_order = []
  mut without_order = []

  for partial in $partials {
    if $partial.order != null {
      $with_order = ($with_order | append $partial)
    } else {
      $without_order = ($without_order | append $partial)
    }
  }

  # Sort explicit orders numerically
  let sorted_with_order = ($with_order | sort-by order)

  # Find highest explicit order number
  let max_order = (if ($sorted_with_order | length) > 0 {
    $sorted_with_order | last | get order
  } else {
    0
  })

  # Sort unnumbered partials alphabetically by filename
  let sorted_without_order = ($without_order | sort-by {|p| $p.file | path basename})

  # Auto-assign order numbers starting after max_order
  mut auto_order = ($max_order + 1)
  mut numbered_without_order = []
  for partial in $sorted_without_order {
    $numbered_without_order = ($numbered_without_order | append ($partial | merge {order: $auto_order}))
    $auto_order = ($auto_order + 1)
  }

  # Combine: explicit orders first, then auto-numbered alphabetical
  ($sorted_with_order | append $numbered_without_order)
}

# Remove old merged sections from target file (identified by markers)
# Reads file, finds sections between start/end markers, removes them, writes back
export def remove_old_merged_sections [target_file: string] {
  if not ($target_file | path exists) {
    return
  }

  let content = (open --raw $target_file)
  let lines = ($content | split row "\n")
  mut new_lines = []
  mut skip_mode = false

  for line in $lines {
    # Check for start marker: # === Merged from: filename.toml (order: N) ===
    if ($line | str trim | str starts-with "# ===") and ($line | str contains "Merged from:") {
      $skip_mode = true
      continue
    }

    # Check for end marker: # === End of merge from: filename.toml ===
    if ($line | str trim | str starts-with "# ===") and ($line | str contains "End of merge from:") {
      $skip_mode = false
      continue
    }

    # Skip lines between markers
    if $skip_mode {
      continue
    }

    # Keep all other lines
    $new_lines = ($new_lines | append $line)
  }

  # Write back cleaned content
  ($new_lines | str join "\n") | save -f $target_file
}

# Merge partial content into target file with markers (runtime mode)
# Appends partial content with start/end markers for restart prevention
export def merge_partial_with_marker [
  target_file: string
  partial: record  # Record with: file, target, order, content
] {
  if not ($target_file | path exists) {
    error make {msg: $"Target file not found: ($target_file)"}
  }

  let filename = ($partial.file | path basename)
  let order = (if $partial.order != null {
    ($partial.order | into string)
  } else {
    "auto"
  })

  let marker_start = $"# === Merged from: ($filename) \(order: ($order)\) ===\n# This section was automatically merged from a partial config file.\n# DO NOT EDIT MANUALLY - changes will be lost on container restart.\n# To modify, edit the source partial file instead.\n"
  let marker_end = $"# === End of merge from: ($filename) ===\n"

  let content = (open --raw $target_file)
  let partial_content = $partial.content

  # Append with markers
  let new_content = ($content + "\n" + $marker_start + $partial_content + "\n" + $marker_end)
  $new_content | save -f $target_file
}

# Merge partial content into target file without markers (build-time mode)
# Appends partial content directly (no markers needed since it's baked into image)
export def merge_partial_without_marker [
  target_file: string
  partial: record  # Record with: file, target, order, content
] {
  if not ($target_file | path exists) {
    error make {msg: $"Target file not found: ($target_file)"}
  }

  let content = (open --raw $target_file)
  let partial_content = $partial.content

  # Append without markers
  let new_content = ($content + "\n" + $partial_content + "\n")
  $new_content | save -f $target_file
}

# Main runtime merge function
# Removes old merged sections, finds partials, sorts, and merges with markers
export def merge_partial_configs [target_file: string] {
  # Get config directory from environment (default: /etc/revad)
  let revad_config_dir = (try {
    $env.REVAD_CONFIG_DIR
  } catch {
    "/etc/revad"
  })

  let target_path = $"($revad_config_dir)/($target_file)"

  if not ($target_path | path exists) {
    error make {msg: $"Target config file not found: ($target_path)"}
  }

  # Remove old merged sections (prevents duplicates on restart)
  remove_old_merged_sections $target_path

  # Find partials from volume only (end user partials)
  # Build-time partials (maintainer partials) are already merged into /configs/revad/*.toml
  # and should NOT be available at runtime
  let partials_dirs = [
    $"($revad_config_dir)/partial"  # Volume (end user only)
  ]

  let partials = (find_partials_for_target $target_file --partials-dirs $partials_dirs)

  if ($partials | length) == 0 {
    return
  }

  # Sort partials by order
  let sorted_partials = (sort_partials_by_order $partials)

  # Merge each partial with markers
  for partial in $sorted_partials {
    merge_partial_with_marker $target_path $partial
  }

  print $"Merged (($sorted_partials | length)) partial(s) into ($target_file)"
}

# Main build-time merge function
# Finds partials in source_dir/partial, merges into source_dir/*.toml without markers
export def merge_partial_configs_build [
  source_dir: string
  partials_dir: string
] {
  if not ($source_dir | path exists) {
    error make {msg: $"Source directory not found: ($source_dir)"}
  }

  if not ($partials_dir | path exists) {
    return
  }

  # Find all .toml files in source_dir
  let target_files = (try {
    ls $source_dir | where type == file | where {|f| ($f.name | str ends-with ".toml")} | get name | path basename
  } catch {
    []
  })

  for target_file in $target_files {
    let target_path = $"($source_dir)/($target_file)"

    # Find partials for this target
    let partials = (find_partials_for_target $target_file --partials-dirs [$partials_dir])

    if ($partials | length) == 0 {
      continue
    }

    # Sort partials by order
    let sorted_partials = (sort_partials_by_order $partials)

    # Merge each partial without markers (build-time)
    for partial in $sorted_partials {
      merge_partial_without_marker $target_path $partial
    }

    print $"Merged (($sorted_partials | length)) partial\(s\) into ($target_file) at build-time"
  }
}
