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

# Utility functions for configuration file processing

# Replace all occurrences of a string in a file
# Performs global string replacement and saves the modified content back to the file
export def replace_in_file [file: string, from: string, to: string] {
  let content = (open --raw $file)
  $content | str replace -a $from $to | save -f $file
}

# Validate placeholder syntax: {{placeholder:name.subname:default-value}}
# Returns record with name, subname (optional), and default (optional)
export def validate_placeholder [placeholder: string] {
  # Pattern: {{placeholder:name.subname:default-value}} or {{placeholder:name:default-value}} or {{placeholder:name}}
  # Extract the content between {{placeholder: and }}
  if not ($placeholder | str starts-with "{{placeholder:") {
    return null
  }
  if not ($placeholder | str ends-with "}}") {
    return null
  }
  
  # Remove {{placeholder: (15 chars) and }} (2 chars at end)
  # Use str replace to extract content between {{placeholder: and }}
  let content = ($placeholder | str replace "{{placeholder:" "" | str replace "}}" "")
  
  # Check if there's a default value (after last colon)
  # Split on colon - if there's a colon, the part after the last colon is the default
  # Use split row and take last element as potential default
  let parts = ($content | split row ":")
  let name_part = (if ($parts | length) > 1 {
    # Join all parts except the last one (which is the default)
    ($parts | take (($parts | length) - 1) | str join ":")
  } else {
    $content
  })
  let default_value = (if ($parts | length) > 1 {
    $parts | last
  } else {
    null
  })
  
  # Split name_part by dot to get name and subname
  let parts = ($name_part | split row ".")
  let name = ($parts | get 0)
  let subname = (if ($parts | length) > 1 {
    ($parts | skip 1 | str join ".")
  } else {
    null
  })
  
  {
    name: $name
    subname: $subname
    default: $default_value
    full_name: $name_part
  }
}

# Get environment variable value with fallback to default
# Returns the environment variable value if set, otherwise returns the default value
export def get_env_or_default [var_name: string, default_value: string = ""] {
  (try { $env | get $var_name } catch { $default_value }) | default $default_value
}

# Process all placeholders in a file
# Replaces {{placeholder:name.subname:default-value}} with actual values
# Uses placeholder_map to resolve values
export def process_placeholders [file: string, placeholder_map: record] {
  let content = (open --raw $file)
  mut processed_content = $content
  
  # Find all placeholders using iterative string search and replace
  # Look for {{placeholder:...}} patterns and process them one at a time
  # Use iteration limit to prevent infinite loops from malformed placeholders
  mut remaining = true
  mut iterations = 0
  const MAX_ITERATIONS = 100
  
  mut replaced_count = 0
  mut skipped_count = 0
  mut skipped_placeholders = []
  
  while $remaining and $iterations < $MAX_ITERATIONS {
    $iterations = ($iterations + 1)
    let start_pos = ($processed_content | str index-of "{{placeholder:")
    
    if $start_pos < 0 {
      $remaining = false
      break
    }
    
    # Find the closing }}
    # Search from after "{{placeholder:" to find the matching "}}"
    let search_start = ($start_pos + 15)
    let search_region = ($processed_content | str substring $search_start..)
    let end_pos = ($search_region | str index-of "}}")
    
    if $end_pos < 0 {
      # Malformed placeholder, skip
      print "Warning: Malformed placeholder found (no closing }}), skipping"
      break
    }
    
    # Extract placeholder text: from start_pos to end of "}}" (inclusive)
    # end_pos is relative to search_region, so actual end is: start_pos + 15 + end_pos + 2
    # Note: str substring uses inclusive start, exclusive end
    # end_pos points to first '}' of '}}', so we need +2 to include both '}' characters
    # But we're getting one extra char, so subtract 1
    let actual_end = ($start_pos + 15 + $end_pos + 1)
    mut placeholder_text_raw = ($processed_content | str substring $start_pos..$actual_end)
    
    # Validate that we extracted exactly a placeholder (should end with }})
    # If not, the substring calculation was wrong - try adding 1 to include the second }
    if not ($placeholder_text_raw | str ends-with "}}") {
      # Try with one more character to include the second }
      $placeholder_text_raw = ($processed_content | str substring $start_pos..($actual_end + 1))
      if not ($placeholder_text_raw | str ends-with "}}") {
        print $"Warning: Placeholder extraction failed, got: ($placeholder_text_raw), skipping"
        break
      }
    }
    
    # Trim any trailing whitespace/newlines/quotes for validation, but keep original for replacement
    # Remove quotes and whitespace that might surround the placeholder
    # First trim whitespace, then remove quotes
    let placeholder_text_trimmed = ($placeholder_text_raw | str trim -r | str replace -a '"' "")
    let parsed = (validate_placeholder $placeholder_text_trimmed)
    
    if $parsed != null {
      # Build lookup key for placeholder map
      # For nested placeholders (name.subname), use "name.subname" as key
      # For simple placeholders (name), use "name" as key
      let lookup_key = (if $parsed.subname != null {
        $"($parsed.name).($parsed.subname)"
      } else {
        $parsed.name
      })
      
      # Get replacement value from map, or use default value, or keep placeholder as-is
      mut replacement_value_found = false
      mut replacement_value = $placeholder_text_raw
      
      if ($placeholder_map | columns | where $it == $lookup_key | length) > 0 {
        let map_value = ($placeholder_map | get $lookup_key)
        # Convert value to string if it's not already
        if ($map_value | describe) == "string" {
          $replacement_value = $map_value
        } else {
          $replacement_value = ($map_value | into string)
        }
        $replacement_value_found = true
      } else if $parsed.default != null {
        $replacement_value = $parsed.default
        $replacement_value_found = true
      } else {
        print $"Warning: Placeholder ($placeholder_text_trimmed) not found in map (lookup_key: ($lookup_key)) and no default provided, keeping as-is"
        $skipped_count = ($skipped_count + 1)
        $skipped_placeholders = ($skipped_placeholders | append $placeholder_text_trimmed)
      }
      
      let value = $replacement_value
      
      # Only replace if we got a valid value (not the original placeholder)
      if $value != $placeholder_text_raw {
        # Preserve trailing whitespace/newlines from original placeholder
        # This ensures formatting is maintained after replacement
        let trailing_ws = ($placeholder_text_raw | str replace $placeholder_text_trimmed "")
        let replacement_value = $value + $trailing_ws
        
        # Replace placeholder with value using original text for exact match
        $processed_content = ($processed_content | str replace -a $placeholder_text_raw $replacement_value)
        $replaced_count = ($replaced_count + 1)
      }
    } else {
      # Invalid placeholder format, skip it to prevent infinite loop
      print $"Warning: Invalid placeholder format: ($placeholder_text_trimmed), skipping"
      break
    }
  }
  
  if $replaced_count > 0 {
    let replaced_str = ($replaced_count | into string)
    let message = "Replaced " + $replaced_str + " placeholder(s)"
    print $message
  }
  if $skipped_count > 0 {
    let skipped_count_str = ($skipped_count | into string)
    print "Skipped " + $skipped_count_str + " placeholder(s) (not found in map)"
    print "Missing placeholders:"
    for placeholder in $skipped_placeholders {
      print "  - " + $placeholder
    }
  }
  
  $processed_content | save -f $file
}
