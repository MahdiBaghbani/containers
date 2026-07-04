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

# Service validation - split into focused modules:
# - paths.nu: Local path validation
# - tls.nu: TLS configuration validation
# This file: Platform, version, and service config validation

use ../core/records.nu [find-duplicates]
use ../core/repo.nu [get-repo-root]
use ../tls/lib.nu [get-tls-mode]
use ../platforms/core.nu [validate-platform-name-format]
use ./paths.nu [validate-local-path]
use ./tls.nu [
  validate-tls-config
  validate-version-overrides-tls
  validate-tls-config-merged
]
use ./ssh.nu [
  validate-ssh-config
  validate-version-overrides-ssh
  validate-platform-ssh
  validate-ssh-config-merged
]
use ../plane/guard.nu [PLANE_LOCAL]
use ../plane/effective-config.nu [apply-local-plane-effective-sources]
use ../plane/versions.nu [load-effective-versions-manifest]

# Re-export for backwards compatibility
export use ./paths.nu [validate-local-path]
export use ./tls.nu [
  validate-tls-config
  validate-version-overrides-tls
  validate-tls-config-merged
]

# Centralized source-entry validation shared by base, version override/defaults,
# and merged validation paths. Enforces key regex, forbidden build_arg,
# path/url/ref mutual exclusivity, and local path checks. When require_complete
# is true (base single-platform and merged configs), git sources must declare
# both url and ref; when false (version overrides/defaults), partial fragments
# are allowed because the missing fields are inherited during merge.
def validate-source-entries [
  sources: any,
  context: string,
  require_complete: bool
] {
  mut errors = []

  if not (($sources | describe) | str starts-with "record") {
    return {valid: false, errors: [$"($context): sources: Must be a record."]}
  }

  let repo_root = (get-repo-root)

  for source_key in ($sources | columns) {
    let source = ($sources | get $source_key)

    if not ($source_key =~ '^[a-z0-9_]+$') {
      $errors = ($errors | append $"($context): sources.($source_key): key must be lowercase alphanumeric with underscores only \(pattern: ^[a-z0-9_]+$\)")
    }

    let source_type = ($source | describe)
    if not ($source_type | str starts-with "record") {
      $errors = ($errors | append $"($context): sources.($source_key): Must be a record.")
      continue
    }

    let has_path = ("path" in ($source | columns))
    let has_url = ("url" in ($source | columns))
    let has_ref = ("ref" in ($source | columns))

    if "build_arg" in ($source | columns) {
      $errors = ($errors | append $"($context): sources.($source_key): 'build_arg' field is forbidden. Build args are auto-generated as <KEY>_REF and <KEY>_URL.")
    }

    # Mutual exclusivity: cannot have both path and url/ref
    if $has_path and ($has_url or $has_ref) {
      $errors = ($errors | append $"($context): sources.($source_key): Cannot have both 'path' and 'url'/'ref' fields. They are mutually exclusive.")
      continue
    }

    if $has_path {
      let path_value = (try { $source.path } catch { "" })
      if ($path_value | str length) == 0 {
        $errors = ($errors | append $"($context): sources.($source_key): 'path' field is empty")
      } else {
        let path_validation = (validate-local-path $path_value $repo_root)
        if not $path_validation.valid {
          let formatted_errors = ($path_validation.errors | each {|err| $"($context): sources.($source_key): ($err)"})
          $errors = ($errors | append $formatted_errors)
        }
      }
    } else if $require_complete {
      if not $has_url {
        $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'url'.")
      }
      if not $has_ref {
        $errors = ($errors | append $"($context): sources.($source_key): Missing required field 'ref'.")
      }
    }
  }

  {valid: ($errors | is-empty), errors: $errors}
}

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

# Validate platforms manifest (required fields, unique names, default exists, config structure)
# Validate version defaults structure (reuses validate-version-overrides-structure)
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

# Validate platform defaults structure (reuses validate-platform-config)
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

# Validate version manifest (two-phase: base names first, then expanded tags if platforms exist)
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
    
    # Validate sources via centralized validator (merged configs must be complete:
    # git sources need both url and ref)
    if "sources" in ($merged_config | columns) {
        let src_validation = (validate-source-entries $merged_config.sources $context true)
        if not $src_validation.valid {
            $errors = ($errors | append $src_validation.errors)
        }
    }
    
    {
        valid: ($errors | is-empty),
        errors: $errors
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
    # When platforms.nuon exists, base config can ONLY contain metadata fields:
    # name, context, tls, ssh, and labels. Labels are metadata like TLS/SSH
    # (Docker image labels), not infrastructure or version control.
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
          $errors = ($errors | append $"($service_ctx): ($field): Field forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
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
      $errors = ($errors | append $"($service_ctx): sources: Section forbidden when platforms.nuon exists. Define in versions.nuon defaults or overrides.")
    } else {
      let src_validation = (validate-source-entries $config.sources $service_ctx true)
      if not $src_validation.valid {
        $errors = ($errors | append $src_validation.errors)
      }
    }
  }
  # Note: sources is NOT required in base config for single-platform services.
  # Single-platform services can define sources entirely in versions.nuon defaults.
  
  if "external_images" in ($config | columns) {
    if $has_platforms {
      $errors = ($errors | append $"($service_ctx): external_images: Section forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
    } else {
      let ext_images = $config.external_images
      for img_key in ($ext_images | columns) {
        let img = ($ext_images | get $img_key)
        
        if "image" in ($img | columns) {
          $errors = ($errors | append $"($service_ctx): external_images.($img_key).image: Field forbidden \(legacy\). Use 'name' field in base config.")
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
      $errors = ($errors | append $"($service_ctx): dependencies: Section forbidden when platforms.nuon exists. Move to platforms.nuon \(infrastructure\) or versions.nuon \(versions\).")
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

  # SSH is allowed in base service config (unlike TLS, it may vary per platform
  # and per version, but base placement is valid); validate when present.
  if "ssh" in ($config | columns) {
    let ssh_config = (try { $config.ssh } catch { null })
    if $ssh_config != null {
      let ssh_validation = (validate-ssh-config $ssh_config $"Service '($config.name? | default "")'")
      if not $ssh_validation.valid {
        $errors = ($errors | append $ssh_validation.errors)
      }
      if "warnings" in ($ssh_validation | columns) {
        $warnings = ($warnings | append $ssh_validation.warnings)
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
  use ../platforms/core.nu [check-platforms-manifest-exists]
  
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
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
  
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
  
  # Load platforms manifest if it exists for expanded-tag validation
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
  
  # Pass platforms manifest to enable expanded-tag validation (tag collision detection after expansion)
  # Note: platforms can be null for single-platform services
  validate-version-manifest $manifest $platforms
}

# Validate that all Dockerfile paths referenced in a service config/platforms exist on disk
export def validate-dockerfile-paths [
  service: string
] {
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
  use ../core/repo.nu [get-repo-root]

  mut errors = []
  let repo_root = (get-repo-root)
  let has_platforms = (check-platforms-manifest-exists $service)

  if $has_platforms {
    let platforms_result = (try {
      load-platforms-manifest $service
    } catch { |err|
      return {valid: false, errors: [$"Could not load platforms manifest for '($service)': ($err.msg)"]}
    })
    for platform in $platforms_result.platforms {
      let df = (try { $platform.dockerfile } catch { "" })
      if ($df | str length) > 0 {
        if not (($repo_root | path join $df) | path exists) {
          $errors = ($errors | append $"Service '($service)' platform '($platform.name)': Dockerfile not found: ($df)")
        }
      }
    }
  } else {
    let cfg_path = $"services/($service).nuon"
    let config = (try { open $cfg_path } catch { null })
    if $config != null {
      let df = (try { $config.dockerfile } catch { "" })
      if ($df | str length) > 0 {
        if not (($repo_root | path join $df) | path exists) {
          $errors = ($errors | append $"Service '($service)': Dockerfile not found: ($df)")
        }
      }
    }
  }

  {
    valid: ($errors | is-empty),
    errors: $errors
  }
}

# True when a git source ref is a full 40-hex commit SHA (build REF_KIND=sha).
def source-ref-is-full-sha [source: record] {
  if "path" in ($source | columns) {
    return false
  }
  let ref = (try { $source.ref } catch { "" } | str trim)
  ($ref | str replace --regex '^[0-9a-fA-F]{40}$' "MATCHED") == "MATCHED"
}

# Uppercase build-arg prefix for a manifest source key (foo_bar -> FOO_BAR).
def source-build-arg-prefix [source_key: string] {
  $source_key | str upcase
}

# Read Dockerfile text and nearby service build override scripts for clone-surface checks.
def read-clone-build-surface-text [
  merged: record,
  service: string,
  repo_root: string
] {
  mut parts = []

  let dockerfile = (try { $merged.dockerfile } catch { "" })
  if ($dockerfile | str length) > 0 {
    let df_path = ($repo_root | path join $dockerfile)
    if ($df_path | path exists) {
      $parts = ($parts | append (open -r $df_path))
    }
  }

  let service_ctx = (try { $merged.context } catch { $"services/($service)" })
  let scripts_dir = ($repo_root | path join $service_ctx "scripts" "build")
  if ($scripts_dir | path exists) {
    for script_path in (try { glob $"($scripts_dir)/*.nu" } catch { [] }) {
      $parts = ($parts | append (open -r $script_path))
    }
  }

  $parts | str join "\n"
}

# Non-comment, non-empty trimmed lines from a build surface text blob.
def surface-active-trimmed-lines [surface_text: string] {
  $surface_text
  | lines
  | each {|line| $line | str trim}
  | where {|line| ($line | str length) > 0 and not ($line | str starts-with "#")}
}

# Strip trailing shell inline comments (Docker RUN/CMD lines); full-line comments become empty.
def surface-strip-inline-shell-comment [line: string] {
  let trimmed = ($line | str trim)
  if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
    return ""
  }
  if not ($trimmed | str contains " #") {
    return $trimmed
  }
  let idx = ($trimmed | str index-of " #")
  $trimmed | str substring 0..$idx | str trim
}

# Active build lines with inline shell comments removed.
def surface-code-trimmed-lines [surface_text: string] {
  surface-active-trimmed-lines $surface_text
  | each {|line| surface-strip-inline-shell-comment $line}
  | where {|line| ($line | str length) > 0}
}

# Merge Dockerfile backslash continuations into logical blocks (comments skipped).
def surface-logical-blocks [surface_text: string] {
  let raw_lines = ($surface_text | lines)
  mut blocks = []
  mut i = 0
  while $i < ($raw_lines | length) {
    let stripped = ($raw_lines | get $i | str trim)
    if ($stripped | is-empty) or ($stripped | str starts-with "#") {
      $i = $i + 1
      continue
    }
    mut block_lines = [($raw_lines | get $i)]
    mut j = $i
    while ($block_lines | last | str trim | str ends-with "\\") {
      $j = $j + 1
      if $j >= ($raw_lines | length) {
        break
      }
      $block_lines = ($block_lines | append ($raw_lines | get $j))
    }
    $blocks = ($blocks | append ($block_lines | str join " "))
    $i = $j + 1
  }
  $blocks
}

# PREFIX_REF without matching PREFIX_REF_KIND (substring false positive).
def surface-text-mentions-exact-ref-arg [text: string, prefix: string] {
  let token = $"($prefix)_REF"
  let pattern = ($token + "(?!_KIND)")
  (($text | str replace --regex $pattern "FOUND") | str contains "FOUND")
}

def surface-text-mentions-ref-kind-arg [text: string, prefix: string] {
  $text | str contains $"($prefix)_REF_KIND"
}

# True when text passes a clone-source.nu --ref flag (not --ref-kind).
def surface-text-contains-ref-flag [text: string] {
  (($text | str replace --regex '--ref(?!-kind)' "FOUND") | str contains "FOUND")
}

# Variable name from a simple `let name = ...` binding line.
def surface-let-binding-var-name [line: string] {
  try {
    ($line | parse --regex 'let (?<name>[A-Za-z_][A-Za-z0-9_]*)' | get name.0)
  } catch {
    ""
  }
}

# Active (non-comment) build lines that mention PREFIX_REF exactly.
def surface-active-mentions-exact-ref-arg [surface_text: string, prefix: string] {
  surface-active-trimmed-lines $surface_text
  | any {|line| surface-text-mentions-exact-ref-arg $line $prefix}
}

# Active (non-comment) build lines that mention PREFIX_REF_KIND.
def surface-active-mentions-ref-kind-arg [surface_text: string, prefix: string] {
  surface-active-trimmed-lines $surface_text
  | any {|line| surface-text-mentions-ref-kind-arg $line $prefix}
}

# Logical blocks with inline shell comments stripped from each block.
def surface-code-logical-blocks [surface_text: string] {
  surface-logical-blocks $surface_text
  | each {|block| surface-strip-inline-shell-comment $block}
  | where {|block| ($block | str length) > 0}
}

# Legacy git clone --branch wiring cannot checkout a full commit SHA.
def build-surface-has-legacy-branch-clone [
  surface_text: string,
  prefix: string
] {
  surface-logical-blocks $surface_text
  | any {|block|
    (($block | str contains "git clone")
      and ($block | str contains "--branch")
      and (surface-text-mentions-exact-ref-arg $block $prefix))
  }
}

# Split a logical block into per-command clone-source.nu invocation segments.
def surface-clone-invocation-segments [block: string] {
  if not ($block | str contains "clone-source.nu") {
    return []
  }
  $block
  | str replace -a " && " "\n"
  | str replace -a " ; " "\n"
  | lines
  | each {|seg| $seg | str trim}
  | where {|seg|
      (
        ($seg | str length) > 0
        and ($seg | str contains "clone-source.nu")
        and (surface-text-contains-ref-flag $seg)
        and ($seg | str contains "--ref-kind")
      )
    }
}

# True when a clone-source.nu invocation passes PREFIX_REF and PREFIX_REF_KIND.
def build-surface-clone-block-wires-ref-kind [block: string, prefix: string] {
  surface-clone-invocation-segments $block
  | any {|segment|
      (
        (surface-text-mentions-exact-ref-arg $segment $prefix)
        and (surface-text-mentions-ref-kind-arg $segment $prefix)
      )
    }
}

# True when an override script binds PREFIX_REF and PREFIX_REF_KIND before clone-source.nu.
def build-surface-script-clone-wires-ref-kind [
  surface_text: string,
  prefix: string
] {
  let ref_env = $"($prefix)_REF"
  let ref_kind_env = $"($prefix)_REF_KIND"
  let ref_env_pattern = ($"\\$env\\.($ref_env)" + "(?!_KIND)")
  let indexed = (
    $surface_text
    | lines
    | enumerate
    | each {|e| {index: $e.index, text: ($e.item | str trim)}}
    | where {|e| ($e.text | str length) > 0 and not ($e.text | str starts-with "#")}
  )
  let ref_binding = (
    $indexed
    | where {|e|
        (
          ($e.text | str starts-with "let ")
          and (($e.text | str replace --regex $ref_env_pattern "FOUND") | str contains "FOUND")
        )
      }
    | first
  )
  let ref_kind_binding = (
    $indexed
    | where {|e|
        (
          ($e.text | str starts-with "let ")
          and ($e.text | str contains $"$env.($ref_kind_env)")
        )
      }
    | first
  )
  if $ref_binding == null or $ref_kind_binding == null {
    return false
  }
  let ref_idx = ($ref_binding | get index)
  let ref_kind_idx = ($ref_kind_binding | get index)
  let clone_entries = (
    $indexed
    | where {|e|
        (
          ($e.text | str contains "clone-source.nu")
          and ($e.index) > $ref_idx
          and ($e.index) > $ref_kind_idx
        )
      }
  )
  if ($clone_entries | is-empty) {
    return false
  }
  let ref_var = (surface-let-binding-var-name ($ref_binding | get text))
  let ref_kind_var = (surface-let-binding-var-name ($ref_kind_binding | get text))
  $clone_entries
  | any {|entry|
      let segments = (surface-clone-invocation-segments ($entry | get text))
      $segments
      | any {|segment|
          let uses_ref = (
            (surface-text-mentions-exact-ref-arg $segment $prefix)
            or (
              ($ref_var | str length) > 0
              and (surface-text-contains-ref-flag $segment)
              and ($segment | str contains $"$($ref_var)")
            )
          )
          let uses_ref_kind = (
            (surface-text-mentions-ref-kind-arg $segment $prefix)
            or (
              ($ref_kind_var | str length) > 0
              and ($segment | str contains "--ref-kind")
              and ($segment | str contains $"$($ref_kind_var)")
            )
          )
          $uses_ref and $uses_ref_kind
        }
    }
}

# Shared clone-source.nu helper with per-source REF_KIND build arg.
def build-surface-has-clone-helper-compat [
  surface_text: string,
  prefix: string
] {
  let blocks = (surface-logical-blocks $surface_text)
  if ($blocks | any {|block| build-surface-clone-block-wires-ref-kind $block $prefix}) {
    return true
  }
  build-surface-script-clone-wires-ref-kind $surface_text $prefix
}

# True when one logical block wires fetch and SHA checkout for this source.
def build-surface-block-has-inline-sha-wiring [block: string, prefix: string] {
  let sha_token = $"($prefix)_SHA"
  if not ($block | str contains $sha_token) {
    return false
  }
  let has_fetch = (
    ($block | str contains "git fetch")
    or ($block | str contains "fetch --depth")
    or ($block | str contains "FETCH_HEAD")
  )
  let has_checkout = (
    ($block | str contains "checkout") and ($block | str contains $sha_token)
  )
  $has_fetch and $has_checkout
}

# Inline Dockerfile or override SHA fetch/checkout path for one source.
def build-surface-has-inline-sha-compat [
  surface_text: string,
  prefix: string
] {
  let inline_ok = (
    surface-code-logical-blocks $surface_text
    | any {|block| build-surface-block-has-inline-sha-wiring $block $prefix}
  )
  if $inline_ok {
    return true
  }
  build-surface-script-inline-sha-wiring $surface_text $prefix
}

# True when an override script guards and runs SHA checkout for this source.
def build-surface-script-inline-sha-wiring [
  surface_text: string,
  prefix: string
] {
  let sha_env = $"($prefix)_SHA"
  let active = (surface-active-trimmed-lines $surface_text)
  let binds_sha = (
    $active
    | any {|line|
        (($line | str contains $"$env.($sha_env)") or ($line | str contains $sha_env))
      }
  )
  if not $binds_sha {
    return false
  }
  let checkout_def = (
    $active
    | enumerate
    | where {|e| $e.item | str starts-with "def checkout-sha"}
    | first
  )
  if $checkout_def == null {
    return false
  }
  let helper_body = (
    $active
    | skip ($checkout_def.index + 1)
    | take 25
  )
  let fetch_retry = (
    $helper_body
    | any {|line|
        ($line | str contains "fetch --depth") and ($line | str contains "$sha")
      }
  )
  let guarded_call = (
    $active
    | any {|line|
        (($line | str contains "checkout-sha")
          and ($line | str contains "sha")
          and (not ($line | str starts-with "def ")))
      }
  )
  $fetch_retry and $guarded_call
}

# Validate merged git sources pinned to full SHAs against Dockerfile/override clone wiring.
export def validate-source-clone-compat [
  merged: record,
  service: string,
  context: string
] {
  mut errors = []

  if not ("sources" in ($merged | columns)) {
    return {valid: true, errors: []}
  }

  let repo_root = (get-repo-root)
  let surface_text = (read-clone-build-surface-text $merged $service $repo_root)
  let dockerfile = (try { $merged.dockerfile } catch { "" })

  for source_key in ($merged.sources | columns) {
    let source = ($merged.sources | get $source_key)
    if not (source-ref-is-full-sha $source) {
      continue
    }

    let prefix = (source-build-arg-prefix $source_key)
    let ref = ($source.ref | str trim)

    # Only enforce when active build lines reference this source's REF arg.
    if not (surface-active-mentions-exact-ref-arg $surface_text $prefix) {
      continue
    }

    let helper_ok = (build-surface-has-clone-helper-compat $surface_text $prefix)
    let inline_ok = (build-surface-has-inline-sha-compat $surface_text $prefix)
    let legacy_branch = (build-surface-has-legacy-branch-clone $surface_text $prefix)

    if $legacy_branch {
      $errors = ($errors | append
        $"($context): sources.($source_key): ref '($ref)' is a full git SHA but the build surface uses legacy 'git clone --branch' for ($prefix)_REF. Migrate to clone-source.nu with ($prefix)_REF_KIND or an explicit SHA fetch/checkout path."
      )
    } else if not ($helper_ok or $inline_ok) {
      $errors = ($errors | append
        $"($context): sources.($source_key): ref '($ref)' is a full git SHA but the build surface in '($dockerfile)' lacks ($prefix)_REF_KIND / clone-source.nu or explicit SHA fetch wiring for this source."
      )
    }
  }

  {valid: ($errors | is-empty), errors: $errors}
}

# Validate one fully-merged config: structure (external_images, sources),
# merge-aware TLS dependency rules, and SSH placement. Used by merged validation
# so errors that only surface after version/platform merge are caught by
# `validate --all-services`.
def validate-merged-bundle [
  merged: record,
  service: string,
  has_platforms: bool,
  platform_name: string,
  ctx: string
] {
  mut errors = []
  mut warnings = []

  let struct_result = (validate-merged-config $merged $service $has_platforms $platform_name)
  if not $struct_result.valid {
    $errors = ($errors | append ($struct_result.errors | each {|e| $"($ctx): ($e)"}))
  }

  # Merge-aware TLS dependency check: validates the merged config so services
  # whose common-tools dependency lives in versions/platforms do not false-fail.
  let tls_result = (validate-tls-config-merged $merged $service)
  if not $tls_result.valid {
    $errors = ($errors | append ($tls_result.errors | each {|e| $"($ctx): ($e)"}))
  }
  if "warnings" in ($tls_result | columns) {
    $warnings = ($warnings | append $tls_result.warnings)
  }

  let ssh_result = (validate-ssh-config-merged $merged $service)
  if not $ssh_result.valid {
    $errors = ($errors | append ($ssh_result.errors | each {|e| $"($ctx): ($e)"}))
  }
  if "warnings" in ($ssh_result | columns) {
    $warnings = ($warnings | append $ssh_result.warnings)
  }

  let clone_compat = (validate-source-clone-compat $merged $service $ctx)
  if not $clone_compat.valid {
    $errors = ($errors | append $clone_compat.errors)
  }

  {valid: ($errors | is-empty), errors: $errors, warnings: $warnings}
}

# Build and validate the merged config for every version (and per-platform
# expansion) of a service, mirroring the build-time merge order
# (apply-version-defaults -> merge-platform-config -> merge-version-overrides).
def validate-service-merged-configs [
  service: string,
  has_platforms: bool,
  plane_ctx: any = null
] {
  use ../manifest/core.nu [
    check-versions-manifest-exists
    load-versions-manifest
    apply-version-defaults
  ]
  use ../platforms/core.nu [load-platforms-manifest get-platform-names get-platform-spec merge-platform-config merge-version-overrides]

  mut errors = []
  mut warnings = []

  let cfg_path = $"services/($service).nuon"
  let base_config = (try { open $cfg_path } catch { null })
  if $base_config == null {
    return {valid: true, errors: [], warnings: []}
  }

  let is_local_plane = $plane_ctx != null and (try { $plane_ctx.plane } catch { "" }) == $PLANE_LOCAL
  let manifest = (if $is_local_plane {
    if not (check-versions-manifest-exists $service) {
      null
    } else {
      try {
        load-effective-versions-manifest $service $plane_ctx
      } catch {|err|
        return {valid: false, errors: [$err.msg], warnings: []}
      }
    }
  } else {
    try { load-versions-manifest $service } catch { null }
  })
  if $manifest == null {
    return {valid: true, errors: [], warnings: []}
  }

  let versions = (try { $manifest.versions } catch { [] })

  let platforms = (if $has_platforms {
    try { load-platforms-manifest $service } catch { null }
  } else {
    null
  })

  for version_spec in $versions {
    let version_name = (try { $version_spec.name } catch { "" })
    let version_with_defaults = (apply-version-defaults $manifest $version_spec)

    if $has_platforms and $platforms != null {
      let platform_names = (get-platform-names $platforms)
      for platform in $platform_names {
        let ctx = $"Service '($service)' version '($version_name)' platform '($platform)'"
        let merge_result = (try {
          let platform_spec = (get-platform-spec $platforms $platform)
          let with_platform = (merge-platform-config $base_config $platform_spec)
          {ok: true, merged: (merge-version-overrides $with_platform $version_with_defaults $platform $platforms)}
        } catch {|err|
          {ok: false, msg: $err.msg}
        })
        if $merge_result.ok {
          mut merged = $merge_result.merged
          if $plane_ctx != null and (try { $plane_ctx.plane } catch { "" }) == $PLANE_LOCAL {
            $merged = (apply-local-plane-effective-sources $merged $service $version_with_defaults $plane_ctx)
          }
          let bundle = (validate-merged-bundle $merged $service $has_platforms $platform $ctx)
          $errors = ($errors | append $bundle.errors)
          $warnings = ($warnings | append $bundle.warnings)
        } else {
          $errors = ($errors | append $"($ctx): Failed to build merged config: ($merge_result.msg)")
        }
      }
    } else {
      let ctx = $"Service '($service)' version '($version_name)'"
      let merge_result = (try {
        {ok: true, merged: (merge-version-overrides $base_config $version_with_defaults "" null)}
      } catch {|err|
        {ok: false, msg: $err.msg}
      })
      if $merge_result.ok {
        mut merged = $merge_result.merged
        if $plane_ctx != null and (try { $plane_ctx.plane } catch { "" }) == $PLANE_LOCAL {
          $merged = (apply-local-plane-effective-sources $merged $service $version_with_defaults $plane_ctx)
        }
        let bundle = (validate-merged-bundle $merged $service $has_platforms "" $ctx)
        $errors = ($errors | append $bundle.errors)
        $warnings = ($warnings | append $bundle.warnings)
      } else {
        $errors = ($errors | append $"($ctx): Failed to build merged config: ($merge_result.msg)")
      }
    }
  }

  {valid: ($errors | is-empty), errors: $errors, warnings: $warnings}
}

# Validate that a service has both config AND manifest (complete validation)
export def validate-service-complete [
  service: string,
  plane_ctx: any = null
] {
  use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest]
  
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

  # Validate Dockerfile paths exist on disk
  let dockerfile_result = (validate-dockerfile-paths $service)
  if not $dockerfile_result.valid {
    $all_errors = ($all_errors | append $dockerfile_result.errors)
  }
  
  # Validate manifest (REQUIRED)
  let manifest_result = (validate-manifest-file $service)
  if not $manifest_result.valid {
    $all_errors = ($all_errors | append $manifest_result.errors)
  }
  if "warnings" in ($manifest_result | columns) {
    $all_warnings = ($all_warnings | append $manifest_result.warnings)
  }

  # Validate merged configs across versions/platforms only when the base layers
  # are sound; otherwise merged errors would just echo upstream failures.
  if ($all_errors | is-empty) {
    let merged_result = (validate-service-merged-configs $service $has_platforms $plane_ctx)
    if not $merged_result.valid {
      $all_errors = ($all_errors | append $merged_result.errors)
    }
    if "warnings" in ($merged_result | columns) {
      $all_warnings = ($all_warnings | append $merged_result.warnings)
    }
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
