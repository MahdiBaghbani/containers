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

# Version manifest validation

use ../core/records.nu [find-duplicates]
use ./tls.nu [validate-version-overrides-tls]
use ./ssh.nu [validate-ssh-config validate-version-overrides-ssh]
use ./_shared.nu [validate-source-entries]

export def validate-version-defaults [
  defaults: record,
  platforms: any = null
] {
  # Extract global defaults (exclude platforms if present)
  let global_defaults = (if "platforms" in ($defaults | columns) {
    $defaults | reject platforms
  } else {
    $defaults
  })
  
  # Validate global defaults structure (infrastructure fields always forbidden in version defaults)
  let global_errors = (if not ($global_defaults | is-empty) {
    mut errs = []

    let structure_validation = (validate-version-overrides-structure $global_defaults "defaults")
    if not $structure_validation.valid {
      $errs = ($errs | append $structure_validation.errors)
    }

    # TLS is forbidden in version defaults (same rule as version overrides).
    let tls_validation = (validate-version-overrides-tls $global_defaults "defaults")
    if not $tls_validation.valid {
      $errs = ($errs | append $tls_validation.errors)
    }

    # SSH is allowed in version defaults; validate when present.
    if "ssh" in ($global_defaults | columns) {
      let ssh_config = (try { $global_defaults.ssh } catch { null })
      if $ssh_config != null {
        let ssh_validation = (validate-ssh-config $ssh_config "defaults")
        if not $ssh_validation.valid {
          $errs = ($errs | append $ssh_validation.errors)
        }
      }
    }

    $errs
  } else {
    []
  })
  
  # Validate platform-specific defaults if present
  let platform_errors = (if "platforms" in ($defaults | columns) {
    let default_platforms = $defaults.platforms
    
    let platforms_type = ($default_platforms | describe)
    if not ($platforms_type | str starts-with "record") {
      ["defaults.platforms must be a record"]
    } else {
      # Validate platform names against platforms manifest if available
      let name_errors = (if $platforms != null {
        use ../platforms/core.nu [get-platform-names]
        let platform_names = (get-platform-names $platforms)
        
        $default_platforms | columns | reduce --fold [] {|platform_name, acc|
          if not ($platform_name in $platform_names) {
            $acc | append $"defaults.platforms: platform '($platform_name)' not found in platforms manifest"
          } else {
            $acc
          }
        }
      } else {
        []
      })
      
      # Validate each platform's defaults structure recursively
      let structure_errors = ($default_platforms | columns | reduce --fold [] {|platform_name, acc|
        let platform_defaults = ($default_platforms | get $platform_name)
        let platform_type = ($platform_defaults | describe)
        if not ($platform_type | str starts-with "record") {
          $acc | append $"defaults.platforms.($platform_name) must be a record"
        } else {
          let ctx = $"defaults.platforms.($platform_name)"
          mut platform_errs = $acc

          let platform_structure_validation = (validate-version-overrides-structure $platform_defaults $ctx)
          if not $platform_structure_validation.valid {
            $platform_errs = ($platform_errs | append $platform_structure_validation.errors)
          }

          # TLS is forbidden in defaults.platforms.* (same rule as base platform configs).
          let platform_tls_validation = (validate-version-overrides-tls $platform_defaults $ctx)
          if not $platform_tls_validation.valid {
            $platform_errs = ($platform_errs | append $platform_tls_validation.errors)
          }

          # SSH is allowed in defaults.platforms.*; validate when present.
          if "ssh" in ($platform_defaults | columns) {
            let ssh_config = (try { $platform_defaults.ssh } catch { null })
            if $ssh_config != null {
              let ssh_validation = (validate-ssh-config $ssh_config $ctx)
              if not $ssh_validation.valid {
                $platform_errs = ($platform_errs | append $ssh_validation.errors)
              }
            }
          }

          $platform_errs
        }
      })
      
      $name_errors | append $structure_errors
    }
  } else {
    []
  })
  
  let all_errors = ($global_errors | append $platform_errors)
  
  {
    valid: ($all_errors | is-empty),
    errors: $all_errors
  }
}

export def validate-version-manifest [
  manifest: record,
  platforms: any = null
] {
  mut errors = []
  mut warnings = []
  
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
    use ../platforms/core.nu [get-platform-names]
    let platform_names = (get-platform-names $platforms)
    for version_spec in $versions {
      let version_name = (try { $version_spec.name } catch { "" })
      if ($version_name | str length) > 0 {
        for platform in $platform_names {
          if ($version_name | str ends-with $"-($platform)") {
            $errors = ($errors | append $"Version name '($version_name)' ends with platform suffix '-($platform)'. Version names should not include platform suffixes \(they are added automatically during expansion\)")
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
  
  let latest_versions = ($versions | where {|v| (try { $v.latest } catch { false }) == true})
  if ($latest_versions | length) > 1 {
    let latest_names = ($latest_versions | each {|v| $v.name} | str join ", ")
    $errors = ($errors | append $"Only one version can have 'latest: true' \(found: ($latest_names)\)")
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

      # SSH is allowed in version overrides (unlike TLS); validate when present.
      # Thread its advisory warnings through so they reach validate-manifest-file
      # and validate-service-complete instead of being dropped here.
      let ssh_validation = (validate-version-overrides-ssh $version_spec.overrides $version_name)
      if not $ssh_validation.valid {
        $errors = ($errors | append $ssh_validation.errors)
      }
      if "warnings" in ($ssh_validation | columns) {
        $warnings = ($warnings | append $ssh_validation.warnings)
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
  
  # Validate defaults if present
  if "defaults" in ($manifest | columns) {
    let defaults_validation = (validate-version-defaults $manifest.defaults $platforms)
    if not $defaults_validation.valid {
      $errors = ($errors | append $defaults_validation.errors)
    }
  }
  
  if not ($errors | is-empty) {
    return {valid: false, errors: $errors, warnings: $warnings}
  }
  
  # pass 2: validate expanded tags (only if platforms exist and pass 1 passed)
  if $platforms != null {
    use ../platforms/core.nu [get-platform-names get-default-platform expand-version-to-platforms]
    
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
    errors: $errors,
    warnings: $warnings
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
                    $errors = ($errors | append $"Version '($version_name)': external_images.($img_key).image: Field forbidden \(legacy\). Use 'tag' field in overrides.")
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
                
                # Validate forbidden fields (define infrastructure in base or platforms.nuon)
                if "service" in ($dep | columns) {
                    $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key).service: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
                
                if "build_arg" in ($dep | columns) {
                    $errors = ($errors | append $"Version '($version_name)': dependencies.($dep_key).build_arg: Field forbidden. Define in base config \(single-platform\) or platforms.nuon \(multi-platform\).")
                }
            }
        }
    }
    
    # Validate sources in global overrides (partial fragments allowed; full
    # url/ref completeness is enforced during merged validation)
    if "sources" in ($overrides | columns) {
        let src_validation = (validate-source-entries $overrides.sources $"Version '($version_name)'" false)
        if not $src_validation.valid {
            $errors = ($errors | append $src_validation.errors)
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
                                $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name).external_images.($img_key).image: Field forbidden \(legacy\). Use 'tag' field in overrides.")
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

                # Validate sources in platform-specific overrides (partial fragments allowed)
                if "sources" in ($platform_override | columns) {
                    let src_validation = (validate-source-entries $platform_override.sources $"Version '($version_name)': platforms.($platform_name)" false)
                    if not $src_validation.valid {
                        $errors = ($errors | append $src_validation.errors)
                    }
                }

                # TLS is forbidden in platform-specific overrides (base-config
                # only); reject it here so nested
                # overrides.platforms.<platform>.tls cannot survive the merge.
                if "tls" in ($platform_override | columns) {
                    $errors = ($errors | append $"Version '($version_name)': platforms.($platform_name): tls: Section forbidden. Configure TLS in base service config only.")
                }

                # SSH is allowed in platform-specific overrides (unlike TLS);
                # validate when present so invalid nested SSH cannot bypass the
                # version-overrides path.
                if "ssh" in ($platform_override | columns) {
                    let ssh_config = (try { $platform_override.ssh } catch { null })
                    if $ssh_config != null {
                        let ssh_validation = (validate-ssh-config $ssh_config $"Version '($version_name)': platforms.($platform_name)")
                        if not $ssh_validation.valid {
                            $errors = ($errors | append $ssh_validation.errors)
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