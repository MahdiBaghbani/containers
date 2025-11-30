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

# Multi-platform build support
# See docs/guides/multi-platform-builds.md for details

use ./common.nu [deep-merge validate-platform-name-format]

export def get-service-platforms-manifest-path [service: string] {
  $"services/($service)/platforms.nuon"
}

export def check-platforms-manifest-exists [service: string] {
  let manifest_path = (get-service-platforms-manifest-path $service)
  $manifest_path | path exists
}

export def load-platforms-manifest [service: string] {
  let manifest_path = (get-service-platforms-manifest-path $service)
  
  if not ($manifest_path | path exists) {
    error make { msg: $"Platforms manifest not found: ($manifest_path)" }
  }
  
  try {
    open $manifest_path
  } catch {
    error make { msg: $"Failed to parse platforms manifest: ($manifest_path)" }
  }
}

export def get-default-platform [platforms: record] {
  try {
    $platforms.default
  } catch {
    error make { msg: "Platforms manifest missing 'default' field" }
  }
}

# Apply platform defaults to platform spec (deep-merge defaults into platform)
export def apply-platform-defaults [
  platforms_manifest: record,
  platform_spec: record
] {
  let defaults = (try { $platforms_manifest.defaults } catch { {} })
  if ($defaults | is-empty) {
    return $platform_spec
  }

  # Apply defaults to platform spec (defaults → platform)
  deep-merge $defaults $platform_spec
}

export def get-platform-spec [
  platforms: record,
  platform_name: string
] {
  let all_platforms = (try {
    $platforms.platforms
  } catch {
    error make { msg: "Platforms manifest missing 'platforms' field" }
  })
  
  let found = ($all_platforms | where name == $platform_name)
  
  if ($found | is-empty) {
    error make { msg: $"Platform '($platform_name)' not found in platforms manifest" }
  }
  
  let platform_spec = $found.0
  
  # Apply defaults before returning
  apply-platform-defaults $platforms $platform_spec
}

export def get-platform-names [platforms: record] {
  let all_platforms = (try {
    $platforms.platforms
  } catch {
    error make { msg: "Platforms manifest missing 'platforms' field" }
  })
  
  $all_platforms | each {|p| $p.name}
}

# Expand version spec to all platforms (adds 'platform' field to each)
export def expand-version-to-platforms [
  version_spec: record,
  platforms: record,
  default_platform: string
] {
  let platform_names = (get-platform-names $platforms)
  if not ($default_platform in $platform_names) {
    error make { msg: $"Default platform '($default_platform)' not found in platforms list" }
  }
  
  $platform_names | each {|platform_name|
    $version_spec | insert platform $platform_name
  }
}

# Merge platform config with base config (dockerfile is replaced, others deep-merged)
# See docs/concepts/service-configuration.md for merge order
export def merge-platform-config [
  base_config: record,
  platform_spec: record
] {
  mut merged = $base_config
  
  let platform_fields = ($platform_spec | columns | where $it != "name")
  
  for field in $platform_fields {
    let platform_val = ($platform_spec | get $field)
    
    if $field == "dockerfile" {
      $merged = ($merged | upsert dockerfile $platform_val)
    } else {
      let base_val = (try { $merged | get $field } catch { null })
      
      if $base_val == null {
        $merged = ($merged | insert $field $platform_val)
      } else {
        $merged = ($merged | upsert $field (deep-merge $base_val $platform_val))
      }
    }
  }
  
  $merged
}

# Merge version overrides with config (platform-aware)
# Merge order: global overrides first, then platform-specific (if platform specified)
export def merge-version-overrides [
  base_config: record,
  version_spec: record,
  platform: string = "",
  platforms: any = null
] {
  let overrides = (try {
    $version_spec.overrides
  } catch {
    {}
  })
  
  if ($overrides | is-empty) {
    return $base_config
  }
  
  mut merged = $base_config
  
  let has_platforms_key = ("platforms" in ($overrides | columns))
  let global_overrides = (if $has_platforms_key {
    $overrides | reject platforms
  } else {
    $overrides
  })
  
  if not ($global_overrides | is-empty) {
    for field in ($global_overrides | columns) {
      let override_val = ($global_overrides | get $field)
      
      if $field == "dockerfile" {
        $merged = ($merged | upsert dockerfile $override_val)
      } else {
        let current_val = (try { $merged | get $field } catch { null })
        
        if $current_val == null {
          $merged = ($merged | insert $field $override_val)
        } else {
          $merged = ($merged | upsert $field (deep-merge $current_val $override_val))
        }
      }
    }
  }
  
  if ($platform | str length) > 0 and $has_platforms_key {
    let platforms_overrides = (try { $overrides.platforms } catch { {} })
    
    if not ($platforms_overrides | is-empty) {
      if $platform in ($platforms_overrides | columns) {
        if $platforms != null {
          let platform_names = (get-platform-names $platforms)
          if not ($platform in $platform_names) {
            print $"Warning: Platform-specific override for '($platform)' found, but platform not in manifest. Skipping."
          } else {
            let platform_override = ($platforms_overrides | get $platform)
            
            for field in ($platform_override | columns) {
              let override_val = ($platform_override | get $field)
              
              if $field == "dockerfile" {
                $merged = ($merged | upsert dockerfile $override_val)
              } else {
                let current_val = (try { $merged | get $field } catch { null })
                
                if $current_val == null {
                  $merged = ($merged | insert $field $override_val)
                } else {
                  $merged = ($merged | upsert $field (deep-merge $current_val $override_val))
                }
              }
            }
          }
        }
      }
    }
  }
  
  $merged
}

# Strip platform suffix from version name (format: {version}-{platform})
# Returns {base_name, platform_name} - platform_name is "" if no suffix found
export def strip-platform-suffix [
  version_name: string,
  platforms: record
] {
  if ($version_name | str contains "--") {
    error make { msg: $"Invalid version name '($version_name)': contains double dash \(--\)" }
  }
  
  if ($version_name | str ends-with "-") {
    error make { msg: $"Invalid version name '($version_name)': ends with dash \(-\)" }
  }
  
  let platform_names = (get-platform-names $platforms)
  
  for platform in $platform_names {
    let suffix = $"-($platform)"
    if ($version_name | str ends-with $suffix) {
      let suffix_len = ($suffix | str length)
      let name_len = ($version_name | str length)
      let end_idx = $name_len - $suffix_len
      # str substring uses inclusive ranges, so subtract 1 to exclude the dash
      let base = ($version_name | str substring 0..($end_idx - 1))
      
      if ($base | str length) == 0 {
        error make { msg: $"Invalid version name '($version_name)': empty base name before platform suffix" }
      }
      
      if ($platform | str length) == 0 {
        error make { msg: $"Invalid version name '($version_name)': empty platform name in suffix" }
      }
      
      return {base_name: $base, platform_name: $platform}
    }
  }
  
  {base_name: $version_name, platform_name: ""}
}

export def has-platform-suffix [
  version_name: string,
  platforms: record
] {
  let result = (try {
    strip-platform-suffix $version_name $platforms
  } catch {
    return false
  })
  
  ($result.platform_name | str length) > 0
}
