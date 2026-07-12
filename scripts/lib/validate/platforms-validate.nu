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

# Platform manifest validation

use ../core/records.nu [find-duplicates]
use ../platforms/core.nu [validate-platform-name-format]
use ./ssh.nu [validate-platform-ssh]

export def validate-platform-config [
  platform_config: record,
  platform_name: string
] {
  mut errors = []
  
  if "external_images" in ($platform_config | columns) {
    let ext_images = $platform_config.external_images
    
    let ext_images_type = ($ext_images | describe)
    if not ($ext_images_type | str starts-with "record") {
      $errors = ($errors | append $"Platform '($platform_name)': external_images must be a record")
    } else {
      for img_key in ($ext_images | columns) {
        let img = ($ext_images | get $img_key)
        
        let img_type = ($img | describe)
        if not ($img_type | str starts-with "record") {
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key) must be a record")
          continue
        }
        
        if "image" in ($img | columns) {
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key).image: Field forbidden \(legacy\). Use 'name' field in platforms.nuon.")
        }
        
        if "tag" in ($img | columns) {
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key).tag: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if not ("name" in ($img | columns)) {
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key) missing required field 'name'")
        }
        
        if not ("build_arg" in ($img | columns)) {
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key) missing required field 'build_arg'")
        }
      }
    }
  }
  
  if "sources" in ($platform_config | columns) {
    $errors = ($errors | append $"Platform '($platform_name)': sources: Section forbidden. Define in versions.nuon defaults or overrides.")
  }
  
  if "dependencies" in ($platform_config | columns) {
    let deps = $platform_config.dependencies
    
    let deps_type = ($deps | describe)
    if not ($deps_type | str starts-with "record") {
      $errors = ($errors | append $"Platform '($platform_name)': dependencies must be a record")
    } else {
      for dep_key in ($deps | columns) {
        let dep = ($deps | get $dep_key)
        
        let dep_type = ($dep | describe)
        if not ($dep_type | str starts-with "record") {
          $errors = ($errors | append $"Platform '($platform_name)': dependencies.($dep_key) must be a record")
          continue
        }
        
        if "version" in ($dep | columns) {
          $errors = ($errors | append $"Platform '($platform_name)': dependencies.($dep_key).version: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if "single_platform" in ($dep | columns) {
          $errors = ($errors | append $"Platform '($platform_name)': dependencies.($dep_key).single_platform: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if not ("build_arg" in ($dep | columns)) {
          $errors = ($errors | append $"Platform '($platform_name)': dependencies.($dep_key) missing required field 'build_arg'")
        }
      }
    }
  }
  
  if "tls" in ($platform_config | columns) {
    $errors = ($errors | append $"Platform '($platform_name)': TLS configuration in platform configs is FORBIDDEN. Configure TLS in base service config only.")
  }

  # SSH is allowed in platform configs (unlike TLS); validate when present.
  let ssh_validation = (validate-platform-ssh $platform_config $platform_name)
  if not $ssh_validation.valid {
    $errors = ($errors | append $ssh_validation.errors)
  }

  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

export def validate-platform-defaults [
  defaults: record
] {
  # Call validate-platform-config directly with "defaults" as platform name for error messages
  validate-platform-config $defaults "defaults"
}

export def validate-platforms-manifest [
  manifest: record
] {
  mut errors = []
  
  if not ("default" in ($manifest | columns)) {
    $errors = ($errors | append "Missing required field: 'default'")
  }
  
  if not ("platforms" in ($manifest | columns)) {
    $errors = ($errors | append "Missing required field: 'platforms'")
    return {valid: false, errors: $errors}
  }
  
  let platforms = $manifest.platforms
  
  let platforms_type = ($platforms | describe)
  if not (($platforms_type | str starts-with "list") or ($platforms_type | str starts-with "table")) {
    $errors = ($errors | append "Field 'platforms' must be a list or table")
    return {valid: false, errors: $errors}
  }
  
  if ($platforms | is-empty) {
    $errors = ($errors | append "Field 'platforms' cannot be empty")
    return {valid: false, errors: $errors}
  }
  
  let all_names = ($platforms | each {|p| try { $p.name } catch { "" }})
  let dup_names = (find-duplicates $all_names)
  for dup in $dup_names {
    $errors = ($errors | append $"Duplicate platform name: '($dup)' appears multiple times")
  }
  
  mut platform_idx = 0
  for platform_spec in $platforms {
    if not ("name" in ($platform_spec | columns)) {
      $errors = ($errors | append $"Platform entry #($platform_idx) missing required field: 'name'")
      $platform_idx = ($platform_idx + 1)
      continue
    }
    
    let platform_name = $platform_spec.name
    
    if not ("dockerfile" in ($platform_spec | columns)) {
      $errors = ($errors | append $"Platform '($platform_name)' missing required field: 'dockerfile'")
    }
    
    let name_validation = (validate-platform-name-format $platform_name)
    if not $name_validation.valid {
      $errors = ($errors | append $name_validation.errors)
    }
    
    let platform_validation = (validate-platform-config $platform_spec $platform_name)
    if not $platform_validation.valid {
      $errors = ($errors | append $platform_validation.errors)
    }
    
    $platform_idx = ($platform_idx + 1)
  }
  
  if "default" in ($manifest | columns) {
    let default_name = $manifest.default
    let platform_names = ($platforms | each {|p| try { $p.name } catch { "" }})
    if not ($default_name in $platform_names) {
      $errors = ($errors | append $"Default platform '($default_name)' not found in platforms list")
    }
  }
  
  # Validate defaults if present
  if "defaults" in ($manifest | columns) {
    let defaults_validation = (validate-platform-defaults $manifest.defaults)
    if not $defaults_validation.valid {
      $errors = ($errors | append $defaults_validation.errors)
    }
  }
  
  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}