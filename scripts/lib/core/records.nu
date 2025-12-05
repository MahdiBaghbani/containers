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

# Generic record and data structure utilities
# Part of scripts/lib/core/ - cross-cutting helpers with no domain knowledge

# Deep merge two records (records merge recursively, other values override)
export def deep-merge [
  base: record,
  override: record
] {
  mut result = $base
  
  for key in ($override | columns) {
    let override_val = ($override | get $key)
    let base_val = (try { $base | get $key } catch { null })
    
    # If both are records, merge recursively
    if ($override_val | describe | str starts-with "record") and ($base_val | describe | str starts-with "record") {
      $result = ($result | upsert $key (deep-merge $base_val $override_val))
    } else {
      # Otherwise, override wins
      $result = ($result | upsert $key $override_val)
    }
  }
  
  $result
}

# Get value from record with default fallback
export def get-or-default [record: record, key: string, default: any] {
  try {
    $record | get $key
  } catch {
    $default
  }
}

# Require field in record or error with context
export def require-field [record: record, field: string, context: string] {
  if not ($field in ($record | columns)) {
    error make {msg: $"($context): missing required field '($field)'"}
  }
  $record | get $field
}

# Find duplicate items in a list
export def find-duplicates [items: list] {
  let unique = ($items | uniq)
  if ($items | length) == ($unique | length) {
    []
  } else {
    mut seen = []
    mut dups = []
    for item in $items {
      if $item in $seen {
        if not ($item in $dups) {
          $dups = ($dups | append $item)
        }
      } else {
        $seen = ($seen | append $item)
      }
    }
    $dups
  }
}
