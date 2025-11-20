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

use ./common.nu [find-duplicates validate-platform-name-format get-tls-mode]

# Validate platform config structure (infrastructure only - no version control fields)
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
          $errors = ($errors | append $"Platform '($platform_name)': external_images.($img_key).image: Field forbidden (legacy). Use 'name' field in platforms.nuon.")
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
    $errors = ($errors | append $"Platform '($platform_name)': sources: Section forbidden. Define in versions.nuon overrides only.")
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
  
  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

# Validate platforms manifest (required fields, unique names, default exists, config structure)
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
  
  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

# Validate version manifest (two-phase: base names first, then expanded tags if platforms exist)
export def validate-version-manifest [
  manifest: record,
  platforms: any = null
] {
  mut errors = []
  
  if not ("default" in ($manifest | columns)) {
    $errors = ($errors | append "Missing required field: 'default'")
  }
  
  if not ("versions" in ($manifest | columns)) {
    $errors = ($errors | append "Missing required field: 'versions'")
    return {valid: false, errors: $errors}
  }
  
  let versions = $manifest.versions
  
  let versions_type = ($versions | describe)
  if not (($versions_type | str starts-with "list") or ($versions_type | str starts-with "table")) {
    $errors = ($errors | append "Field 'versions' must be a list or table")
    return {valid: false, errors: $errors}
  }
  
  if ($versions | is-empty) {
    $errors = ($errors | append "Field 'versions' cannot be empty")
    return {valid: false, errors: $errors}
  }
  
  if $platforms != null {
    use ./platforms.nu [get-platform-names]
    let platform_names = (get-platform-names $platforms)
    for version_spec in $versions {
      let version_name = (try { $version_spec.name } catch { "" })
      if ($version_name | str length) > 0 {
        for platform in $platform_names {
          if ($version_name | str ends-with $"-($platform)") {
            $errors = ($errors | append $"Version name '($version_name)' ends with platform suffix '-($platform)'. Version names should not include platform suffixes (they are added automatically during expansion)")
          }
        }
      }
    }
  }
  
  let all_names = ($versions | each {|v| try { $v.name } catch { "" }})
  let dup_names = (find-duplicates $all_names)
  for dup in $dup_names {
    $errors = ($errors | append $"Duplicate version name: '($dup)' appears multiple times")
  }
  
  let latest_versions = ($versions | where {|v| try { $v.latest } catch { false }} == true)
  if ($latest_versions | length) > 1 {
    let latest_names = ($latest_versions | each {|v| $v.name} | str join ", ")
    $errors = ($errors | append $"Only one version can have 'latest: true' (found: ($latest_names))")
  }
  
  mut version_idx = 0
  for version_spec in $versions {
    if not ("name" in ($version_spec | columns)) {
      $errors = ($errors | append $"Version entry #($version_idx) missing required field: 'name'")
      $version_idx = ($version_idx + 1)
      continue
    }
    
    let version_name = $version_spec.name
    let custom_tags = (try { $version_spec.tags } catch { [] })
    
    if "tags" in ($version_spec | columns) {
      let tags_type = ($custom_tags | describe)
      if not (($tags_type | str starts-with "list") or ($tags_type | str starts-with "table")) {
        $errors = ($errors | append $"Version '($version_name)': tags must be a list")
        $version_idx = ($version_idx + 1)
        continue
      }
    }
    
    if "latest" in $custom_tags {
      $errors = ($errors | append $"Version '($version_name)': tag 'latest' is forbidden in tags array \(auto-generated from 'latest' field\)")
    }
    
    if $version_name in $custom_tags {
      $errors = ($errors | append $"Version '($version_name)': tag '($version_name)' is forbidden in tags array \(auto-generated from 'name' field\)")
    }
    
    let dups = (find-duplicates $custom_tags)
    if not ($dups | is-empty) {
      let dup_tags = ($dups | str join ", ")
      $errors = ($errors | append $"Version '($version_name)': duplicate tags found: ($dup_tags)")
    }
    
    if "overrides" in ($version_spec | columns) {
      let tls_validation = (validate-version-overrides-tls $version_spec.overrides $version_name)
      if not $tls_validation.valid {
        $errors = ($errors | append $tls_validation.errors)
      }
      
      let structure_validation = (validate-version-overrides-structure $version_spec.overrides $version_name)
      if not $structure_validation.valid {
        $errors = ($errors | append $structure_validation.errors)
      }
    }
    
    $version_idx = ($version_idx + 1)
  }
  
  if "default" in ($manifest | columns) {
    let default_name = $manifest.default
    let found = ($versions | where name == $default_name)
    if ($found | is-empty) {
      $errors = ($errors | append $"Default version '($default_name)' not found in versions list")
    }
  }
  
  if not ($errors | is-empty) {
    return {valid: false, errors: $errors}
  }
  
  # Phase 2: Validate expanded tags (only if platforms exist and Phase 1 passed)
  if $platforms != null {
    use ./platforms.nu [get-platform-names get-default-platform expand-version-to-platforms]
    
    let platform_names = (get-platform-names $platforms)
    let default_platform = (get-default-platform $platforms)
    
    mut expanded_versions = []
    for version_spec in $versions {
      $expanded_versions = ($expanded_versions | append (expand-version-to-platforms $version_spec $platforms $default_platform))
    }
    
    mut seen_composites = []
    for expanded in $expanded_versions {
      let composite = $"($expanded.name)-($expanded.platform)"
      if $composite in $seen_composites {
        $errors = ($errors | append $"Composite {name: '($expanded.name)', platform: '($expanded.platform)'} appears multiple times after expansion")
      } else {
        $seen_composites = ($seen_composites | append $composite)
      }
    }
    
    # Build tag map per platform and check for collisions
    mut tag_map_per_platform = {}
    
    for expanded in $expanded_versions {
      let platform = $expanded.platform
      let version_name = $expanded.name
      let is_latest = (try { $expanded.latest } catch { false })
      let custom_tags = (try { $expanded.tags } catch { [] })
      
      mut final_tags = [$"($version_name)-($platform)"]
      
      if $is_latest {
        $final_tags = ($final_tags | append $"latest-($platform)")
        if $platform == $default_platform {
          $final_tags = ($final_tags | append "latest")
        }
      }
      
      for tag in $custom_tags {
        $final_tags = ($final_tags | append $"($tag)-($platform)")
      }
      
      if $platform in ($tag_map_per_platform | columns) {
        mut platform_tags = ($tag_map_per_platform | get $platform)
        for tag in $final_tags {
          if $tag in ($platform_tags | columns) {
            let existing = ($platform_tags | get $tag)
            $platform_tags = ($platform_tags | upsert $tag ($existing | append $version_name))
          } else {
            $platform_tags = ($platform_tags | insert $tag [$version_name])
          }
        }
        $tag_map_per_platform = ($tag_map_per_platform | upsert $platform $platform_tags)
      } else {
        mut platform_tags = {}
        for tag in $final_tags {
          $platform_tags = ($platform_tags | insert $tag [$version_name])
        }
        $tag_map_per_platform = ($tag_map_per_platform | insert $platform $platform_tags)
      }
    }
    
    for platform in ($tag_map_per_platform | columns) {
      let platform_tags = ($tag_map_per_platform | get $platform)
      let colliding_tags = ($platform_tags | columns | where {|tag|
        let users = ($platform_tags | get $tag)
        ($users | length) > 1
      })
      
      if not ($colliding_tags | is-empty) {
        for tag in $colliding_tags {
          let users = ($platform_tags | get $tag | str join ", ")
          $errors = ($errors | append $"Tag collision on platform '($platform)': '($tag)' is used by multiple versions: ($users)")
        }
      }
    }
  } else {
    mut all_final_tags = {}
    
    for version_spec in $versions {
      let version_name = $version_spec.name
      
      mut final_tags = [$version_name]
      
      let is_latest = (try { $version_spec.latest } catch { false })
      if $is_latest {
        $final_tags = ($final_tags | append "latest")
      }
      
      let custom_tags = (try { $version_spec.tags } catch { [] })
      $final_tags = ($final_tags | append $custom_tags)
      
      for tag in $final_tags {
        if $tag in ($all_final_tags | columns) {
          let existing = ($all_final_tags | get $tag)
          $all_final_tags = ($all_final_tags | upsert $tag ($existing | append $version_name))
        } else {
          $all_final_tags = ($all_final_tags | insert $tag [$version_name])
        }
      }
    }
    
    let colliding_tags = ($all_final_tags | columns | where {|tag|
      let users = ($all_final_tags | get $tag)
      ($users | length) > 1
    })
    
    if not ($colliding_tags | is-empty) {
      for tag in $colliding_tags {
        let users = ($all_final_tags | get $tag | str join ", ")
        $errors = ($errors | append $"Tag collision: '($tag)' is used by multiple versions: ($users)")
      }
    }
  }
  
  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

export def validate-tls-config [
    tls_config: any,
    service_name: string
] {
    mut errors = []
    mut warnings = []
    
    if $tls_config == null {
        return {valid: true, errors: [], warnings: []}
    }
    
    let tls_type = ($tls_config | describe)
    if not ($tls_type | str starts-with "record") {
        $errors = ($errors | append $"Service '($service_name)': tls must be a record")
        return {valid: false, errors: $errors, warnings: $warnings}
    }
    
    if not ("enabled" in ($tls_config | columns)) {
        $errors = ($errors | append $"Service '($service_name)': tls.enabled is required")
    } else {
        let enabled_type = ($tls_config.enabled | describe)
        if not ($enabled_type | str starts-with "bool") {
            $errors = ($errors | append $"Service '($service_name)': tls.enabled must be a boolean")
        }
    }
    
    let enabled = (try { $tls_config.enabled | default false } catch { false })
    if $enabled {
        if not ("mode" in ($tls_config | columns)) {
            $errors = ($errors | append $"Service '($service_name)': tls.mode is required when tls.enabled=true")
        } else {
            let mode = $tls_config.mode
            let valid_modes = ["ca-only", "ca-and-cert", "cert-only"]
            if not ($mode in $valid_modes) {
                $errors = ($errors | append $"Service '($service_name)': tls.mode='($mode)' is invalid. Must be one of: ($valid_modes | str join ', ')")
            }
            
            let cert_name = (try { $tls_config.cert_name } catch { "" })
            
            if $mode == "ca-only" and ($cert_name | str trim | is-not-empty) {
                $warnings = ($warnings | append $"Service '($service_name)': tls.mode='ca-only' but tls.cert_name='($cert_name)' is provided. cert_name will be ignored in ca-only mode.")
            }
            
            if $mode != "ca-only" {
                if ($cert_name | is-empty) {
                    $errors = ($errors | append $"Service '($service_name)': tls.cert_name is required when tls.enabled=true and tls.mode is not 'ca-only'")
                }
            }
        }
    }
    
    if not ($errors | is-empty) {
        return {valid: false, errors: $errors, warnings: $warnings}
    }
    
    {valid: true, errors: [], warnings: $warnings}
}

export def validate-version-overrides-tls [
    overrides: record,
    version_name: string
] {
    mut errors = []
    
    if "tls" in ($overrides | columns) {
        $errors = ($errors | append $"Version '($version_name)': tls: Section forbidden. Configure TLS in base service config only.")
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
    }
}

export def validate-version-overrides-structure [
    overrides: record,
    version_name: string
] {
    mut errors = []
    
    if "external_images" in ($overrides | columns) {
        let ext_images = $overrides.external_images
        
        let ext_images_type = ($ext_images | describe)
        if not ($ext_images_type | str starts-with "record") {
            $errors = ($errors | append $"Version '($version_name)': external_images must be a record")
        } else {
            for img_key in ($ext_images | columns) {
                let img = ($ext_images | get $img_key)
                
                let img_type = ($img | describe)
                if not ($img_type | str starts-with "record") {
                    $errors = ($errors | append $"Version '($version_name)': external_images.($img_key) must be a record")
                    continue
                }
                
                if "name" in ($img | columns) {
                    $errors = ($errors | append $"Version '($version_name)': external_images.($img_key).name: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if "build_arg" in ($img | columns) {
                    $errors = ($errors | append $"Version '($version_name)': external_images.($img_key).build_arg: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if "image" in ($img | columns) {
                    $errors = ($errors | append $"Version '($version_name)': external_images.($img_key).image: Field forbidden (legacy). Use 'tag' field in overrides.")
                }
            }
        }
    }
    
    # Validate dependencies in global overrides
    if "dependencies" in ($overrides | columns) {
        let deps = $overrides.dependencies
        
        let deps_type = ($deps | describe)
        if not ($deps_type | str starts-with "record") {
            $errors = ($errors | append $"Version '($version_name)': dependencies must be a record")
        } else {
            for dep_key in ($deps | columns) {
                let dep = ($deps | get $dep_key)
                
                let dep_type = ($dep | describe)
                if not ($dep_type | str starts-with "record") {
                    $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key) must be a record")
                    continue
                }
                
                # Validate single_platform field
                if "single_platform" in ($dep | columns) {
                    let single_platform_val = ($dep | get "single_platform")
                    let single_platform_type = ($single_platform_val | describe)
                    if not ($single_platform_type | str starts-with "bool") {
                        $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key).single_platform must be boolean")
                    }
                    # Note: single_platform: false is treated as not set (only true has meaning)
                    # Note: Conflicting single_platform + platform suffix handled at runtime, not here
                }
                
                # Validate forbidden fields
                if "service" in ($dep | columns) {
                    $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key).service: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if "build_arg" in ($dep | columns) {
                    $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key).build_arg: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
            }
        }
    }
    
    # Validate platform-specific overrides
    if "platforms" in ($overrides | columns) {
        let platforms_overrides = $overrides.platforms
        
        let platforms_type = ($platforms_overrides | describe)
        if not ($platforms_type | str starts-with "record") {
            $errors = ($errors | append $"Version '($version_name)': platforms must be a record")
        } else {
            for platform_name in ($platforms_overrides | columns) {
                let platform_override = ($platforms_overrides | get $platform_name)
                
                let platform_type = ($platform_override | describe)
                if not ($platform_type | str starts-with "record") {
                    $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name) must be a record")
                    continue
                }
                
                if "external_images" in ($platform_override | columns) {
                    let ext_images = $platform_override.external_images
                    
                    let ext_images_type = ($ext_images | describe)
                    if not ($ext_images_type | str starts-with "record") {
                        $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images must be a record")
                    } else {
                        for img_key in ($ext_images | columns) {
                            let img = ($ext_images | get $img_key)
                            
                            let img_type = ($img | describe)
                            if not ($img_type | str starts-with "record") {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images.($img_key) must be a record")
                                continue
                            }
                            
                            if "name" in ($img | columns) {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images.($img_key).name: Field forbidden. Define in platforms.nuon.")
                            }
                            
                            if "build_arg" in ($img | columns) {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images.($img_key).build_arg: Field forbidden. Define in platforms.nuon.")
                            }
                            
                            if "image" in ($img | columns) {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images.($img_key).image: Field forbidden (legacy). Use 'tag' field in overrides.")
                            }
                        }
                    }
                }
                
                # Validate dependencies in platform-specific overrides
                if "dependencies" in ($platform_override | columns) {
                    let deps = $platform_override.dependencies
                    
                    let deps_type = ($deps | describe)
                    if not ($deps_type | str starts-with "record") {
                        $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).dependencies must be a record")
                    } else {
                        for dep_key in ($deps | columns) {
                            let dep = ($deps | get $dep_key)
                            
                            let dep_type = ($dep | describe)
                            if not ($dep_type | str starts-with "record") {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).dependencies.($dep_key) must be a record")
                                continue
                            }
                            
                            # Validate single_platform field (same logic as global overrides)
                            if "single_platform" in ($dep | columns) {
                                let single_platform_val = ($dep | get "single_platform")
                                let single_platform_type = ($single_platform_val | describe)
                                if not ($single_platform_type | str starts-with "bool") {
                                    $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).dependencies.($dep_key).single_platform must be boolean")
                                }
                            }
                            
                            # Validate forbidden fields
                            if "service" in ($dep | columns) {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).dependencies.($dep_key).service: Field forbidden. Define in platforms.nuon.")
                            }
                            
                            if "build_arg" in ($dep | columns) {
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).dependencies.($dep_key).build_arg: Field forbidden. Define in platforms.nuon.")
                            }
                        }
                    }
                }
            }
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
    }
}

export def validate-merged-config [
    merged_config: record,
    service: string,
    has_platforms: bool,
    platform_name: string = ""
] {
    mut errors = []
    
    let context = (if ($platform_name | str length) > 0 {
        $"Merged config for platform '($platform_name)'"
    } else {
        "Merged config"
    })
    
    # Validate external_images have name, tag, build_arg
    if "external_images" in ($merged_config | columns) {
        let ext_images = $merged_config.external_images
        
        let ext_images_type = ($ext_images | describe)
        if not ($ext_images_type | str starts-with "record") {
            $errors = ($errors | append $"($context): external_images: Must be a record.")
        } else {
            for img_key in ($ext_images | columns) {
                let img = ($ext_images | get $img_key)
                
                let img_type = ($img | describe)
                if not ($img_type | str starts-with "record") {
                    $errors = ($errors | append $"($context): external_images.($img_key): Must be a record.")
                    continue
                }
                
                if not ("name" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'name'. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if not ("tag" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'tag'. Define in versions.nuon overrides.external_images.($img_key).tag.")
                }
                
                if not ("build_arg" in ($img | columns)) {
                    $errors = ($errors | append $"($context): external_images.($img_key): Missing required field 'build_arg'. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
            }
        }
    }
    
    # Validate sources have url and ref
    if "sources" in ($merged_config | columns) {
        let sources = $merged_config.sources
        
        let sources_type = ($sources | describe)
        if not ($sources_type | str starts-with "record") {
            $errors = ($errors | append $"($context): sources: Must be a record.")
        } else {
            for source_key in ($sources | columns) {
                let source = ($sources | get $source_key)
                
                let source_type = ($source | describe)
                if not ($source_type | str starts-with "record") {
                    $errors = ($errors | append $"($context): sources.($source_key): Must be a record.")
                    continue
                }
                
                if not ("url" in ($source | columns)) {
                    $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'url'. Define in base config \(single-platform\) or versions.nuon overrides \(multi-platform\).")
                }
                
                if not ("ref" in ($source | columns)) {
                    $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'ref'. Define in base config \(single-platform\) or versions.nuon overrides \(multi-platform\).")
                }
            }
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
    }
}

export def validate-tls-config-merged [
    merged_config: record,
    service_name: string
] {
    mut errors = []
    mut warnings = []
    
    if "tls" in ($merged_config | columns) {
        let tls_config = (try { $merged_config.tls } catch { null })
        if $tls_config != null {
            let tls_validation = (validate-tls-config $tls_config $service_name)
            if not $tls_validation.valid {
                $errors = ($errors | append $tls_validation.errors)
            }
            if "warnings" in ($tls_validation | columns) {
                $warnings = ($warnings | append $tls_validation.warnings)
            }
            
            let tls_enabled = (try { $tls_config.enabled | default false } catch { false })
            if $tls_enabled {
                # common-tools is the exception - it provides the CA bundle, so it doesn't need to depend on itself
                if $service_name != "common-tools" {
                    let deps = (try { $merged_config.dependencies } catch { {} })
                    let has_common_tools = ($deps | columns | any {|dep_key|
                        let dep = ($deps | get $dep_key)
                        let dep_service = (try { $dep.service } catch { $dep_key })
                        $dep_service == "common-tools"
                    })
                    
                    if not $has_common_tools {
                        $errors = ($errors | append $"Service '($service_name)': TLS is enabled but 'common-tools' dependency is missing. Services with TLS enabled MUST have a 'common-tools' dependency. This can be specified in base config, platform config, or version overrides.")
                    }
                }
            }
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors,
        warnings: $warnings
    }
}

# Validate service config (strict separation: metadata only when platforms exist)
export def validate-service-config [
  config: record,
  has_platforms: bool = false,
  service_name: string = ""
] {
  mut errors = []
  mut warnings = []
  
  let service_ctx = (if ($service_name | str length) > 0 { $"Service '($service_name)'" } else { "Service config" })
  
  if $has_platforms {
    # When platforms.nuon exists, base config can ONLY contain: name, context, tls, labels (all metadata)
    # Labels are metadata like TLS (Docker image labels), not infrastructure or version control
    let allowed_fields = ["name", "context", "tls", "labels"]
    let forbidden_fields = ["dockerfile", "external_images", "sources", "dependencies", "build_args"]
    
    for field in $forbidden_fields {
      if $field in ($config | columns) {
        let field_val = ($config | get $field)
        let is_empty = (try {
          if ($field_val | describe | str starts-with "record") {
            ($field_val | columns | is-empty)
          } else if ($field_val | describe | str starts-with "list") {
            ($field_val | is-empty)
          } else {
            false
          }
        } catch { false })
        
        if not $is_empty {
          $errors = ($errors | append $"($service_ctx): ($field): Field forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).")
        }
      }
    }
  }
  
  if not ("name" in ($config | columns)) {
    $errors = ($errors | append "Missing required field: 'name'")
  }
  if not ("context" in ($config | columns)) {
    $errors = ($errors | append "Missing required field: 'context'")
  }
  if not $has_platforms {
    if not ("dockerfile" in ($config | columns)) {
      $errors = ($errors | append "Missing required field: 'dockerfile' (required for single-platform services)")
    }
  }
  
  if "sources" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): sources: Section forbidden when platforms.nuon exists. Define in versions.nuon overrides only.")
    } else {
      let sources = $config.sources
      for source_key in ($sources | columns) {
        let source = ($sources | get $source_key)
        
        if not ($source_key =~ '^[a-z0-9_]+$') {
          $errors = ($errors | append $"Source key '($source_key)' must be lowercase alphanumeric with underscores only \(pattern: ^[a-z0-9_]+$\)")
        }
        
        if not ("url" in ($source | columns)) {
          $errors = ($errors | append $"Source '($source_key)' missing required field: 'url'")
        }
        if not ("ref" in ($source | columns)) {
          $errors = ($errors | append $"Source '($source_key)' missing required field: 'ref'")
        }
        
        if "build_arg" in ($source | columns) {
          $errors = ($errors | append $"Source '($source_key)' has FORBIDDEN 'build_arg' field. Build args are auto-generated as ($source_key | str upcase)_REF and ($source_key | str upcase)_URL")
        }
      }
    }
  } else if not $has_platforms {
    # Sources are required in base config for single-platform (versions.nuon can override, but base must have as fallback)
    $errors = ($errors | append "Missing required field: 'sources' (required for single-platform services, versions.nuon can override but base must have as fallback)")
  }
  
  if "external_images" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): external_images: Section forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).")
    } else {
      let ext_images = $config.external_images
      for img_key in ($ext_images | columns) {
        let img = ($ext_images | get $img_key)
        
        if "image" in ($img | columns) {
          $errors = ($errors | append $"($service_ctx): external_images.($img_key).image: Field forbidden (legacy). Use 'name' field in base config.")
        }
        
        if "tag" in ($img | columns) {
          $errors = ($errors | append $"($service_ctx): external_images.($img_key).tag: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if not ("name" in ($img | columns)) {
          $errors = ($errors | append $"External image '($img_key)' missing required field: 'name'")
        }
        if not ("build_arg" in ($img | columns)) {
          $errors = ($errors | append $"External image '($img_key)' missing required field: 'build_arg'")
        }
      }
    }
  }
  
  if "dependencies" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): dependencies: Section forbidden when platforms.nuon exists. Move to platforms.nuon (infrastructure) or versions.nuon (versions).")
    } else {
      let deps = $config.dependencies
      for dep_key in ($deps | columns) {
        let dep = ($deps | get $dep_key)
        
        if "version" in ($dep | columns) {
          $errors = ($errors | append $"($service_ctx): dependencies.($dep_key).version: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if "single_platform" in ($dep | columns) {
          $errors = ($errors | append $"($service_ctx): dependencies.($dep_key).single_platform: Field forbidden. Define in versions.nuon overrides.")
        }
        
        if not ("build_arg" in ($dep | columns)) {
          $errors = ($errors | append $"Dependency '($dep_key)' missing required field: 'build_arg'")
        }
      }
    }
  }
  
  if "tls" in ($config | columns) {
    let tls_config = (try { $config.tls } catch { null })
    if $tls_config != null {
      let tls_validation = (validate-tls-config $tls_config (try { $config.name } catch { "" }))
      if not $tls_validation.valid {
        $errors = ($errors | append $tls_validation.errors)
      }
      if "warnings" in ($tls_validation | columns) {
        $warnings = ($warnings | append $tls_validation.warnings)
      }
    }
  }
  
  {
    valid: ($errors | is-empty),
    errors: $errors,
    warnings: $warnings
  }
}

export def validate-service-file [
  service: string
] {
  use ./platforms.nu [check-platforms-manifest-exists]
  
  let cfg_path = $"services/($service).nuon"
  
  if not ($cfg_path | path exists) {
    return {
      valid: false,
      errors: [$"Service config not found: ($cfg_path)"]
    }
  }
  
  let config = (try {
    open $cfg_path
  } catch {
    return {
      valid: false,
      errors: [$"Failed to parse service config: ($cfg_path)"]
    }
  })
  
  let has_platforms = (check-platforms-manifest-exists $service)
  let service_name = (try { $config.name } catch { $service })
  validate-service-config $config $has_platforms $service_name
}

# Validate version manifest (two-phase: base validation, then platform expansion if platforms exist)
export def validate-manifest-file [
  service: string
] {
  use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest]
  
  let manifest_path = $"services/($service)/versions.nuon"
  
  if not ($manifest_path | path exists) {
    return {
      valid: false,
      errors: [$"Version manifest not found: ($manifest_path). All services MUST have version manifests."]
    }
  }
  
  let manifest = (try {
    open $manifest_path
  } catch {
    return {
      valid: false,
      errors: [$"Failed to parse version manifest: ($manifest_path)"]
    }
  })
  
  # Load platforms manifest if it exists for Phase 2 validation
  # Optimization: Only load if it exists (already checked in validate-service-complete)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms = (if $has_platforms {
    try {
      load-platforms-manifest $service
    } catch { |err|
      # If platforms manifest exists but can't be loaded, return error
      return {
        valid: false,
        errors: [$"Failed to load platforms manifest for service '($service)': ($err.msg)"]
      }
    }
  } else {
    null
  })
  
  # Pass platforms manifest to enable Phase 2 validation (tag collision detection after expansion)
  # Note: platforms can be null for single-platform services
  validate-version-manifest $manifest $platforms
}

# Validate that a service has both config AND manifest (complete validation)
export def validate-service-complete [
  service: string
] {
  use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest]
  
  mut all_errors = []
  mut all_warnings = []
  
  # Validate service config
  let config_result = (validate-service-file $service)
  if not $config_result.valid {
    $all_errors = ($all_errors | append $config_result.errors)
  }
  if "warnings" in ($config_result | columns) {
    $all_warnings = ($all_warnings | append $config_result.warnings)
  }
  
  # Validate platforms manifest if it exists
  let has_platforms = (check-platforms-manifest-exists $service)
  if $has_platforms {
    let platforms_result = (try {
      let platforms = (load-platforms-manifest $service)
      validate-platforms-manifest $platforms
    } catch { |err|
      {
        valid: false,
        errors: [$"Failed to validate platforms manifest: ($err.msg)"]
      }
    })
    
    if not $platforms_result.valid {
      $all_errors = ($all_errors | append $platforms_result.errors)
    }
  }
  
  # Validate manifest (REQUIRED)
  let manifest_result = (validate-manifest-file $service)
  if not $manifest_result.valid {
    $all_errors = ($all_errors | append $manifest_result.errors)
  }
  
  {
    valid: ($all_errors | is-empty),
    errors: $all_errors,
    warnings: $all_warnings
  }
}

# Print validation results
export def print-validation-results [
  results: record
] {
  if $results.valid {
    print "✓ Validation passed"
  } else {
    print "✗ Validation failed"
    print ""
    print "Errors:"
    for error in $results.errors {
      print $"  - ($error)"
    }
  }
  
  if "warnings" in ($results | columns) and (not ($results.warnings | is-empty)) {
    print ""
    print "Warnings:"
    for warning in $results.warnings {
      print $"  - ($warning)"
    }
  }
}
