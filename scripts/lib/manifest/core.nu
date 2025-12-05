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

# Manifest domain - version manifest loading and filtering
# See docs/concepts/build-system.md for architecture

use ../core/records.nu [deep-merge]

export def check-versions-manifest-exists [
  service: string
] {
  let manifest_path = $"services/($service)/versions.nuon"
  $manifest_path | path exists
}

export def load-versions-manifest [
  service: string
] {
  let manifest_path = $"services/($service)/versions.nuon"
  
  if not ($manifest_path | path exists) {
    error make { msg: $"Version manifest not found: ($manifest_path)" }
  }
  
  try {
    open $manifest_path
  } catch {
    error make { msg: $"Failed to parse version manifest: ($manifest_path)" }
  }
}

export def get-default-version [
  manifest: record
] {
  try {
    $manifest.default
  } catch {
    error make { msg: "Manifest missing 'default' field" }
  }
}

# Merge Git source with field-level merging
# Complete override (both url+ref) -> replace; partial -> merge fields
def merge-git-source [
  default_source: record,
  override_source: record
] {
  # Empty override: preserve defaults (no-op)
  if ($override_source | is-empty) {
    return $default_source
  }

  # Detect override mode (complete vs partial)
  let override_has_url = ("url" in ($override_source | columns))
  let override_has_ref = ("ref" in ($override_source | columns))
  let is_complete_override = ($override_has_url and $override_has_ref)

  if $is_complete_override {
    # Complete override: full replacement (backward compatible)
    $override_source
  } else {
    # Partial override: field-level merge
    mut merged = $default_source

    if $override_has_url {
      $merged = ($merged | upsert url ($override_source | get url))
    }
    if $override_has_ref {
      $merged = ($merged | upsert ref ($override_source | get ref))
    }

    $merged
  }
}

# Merge local source (always replace - path is single field)
def merge-local-source [
  default_source: record,
  override_source: record
] {
  $override_source
}

# Merge sources per key with type-aware field-level merging
# Type switch (local<->git) -> full replacement; same type -> type-specific merge
def merge-sources-per-key [
  default_sources: record,
  override_sources: record
] {
  mut result = $default_sources

  for key in ($override_sources | columns) {
    let default_source = (try { $default_sources | get $key } catch { {} })
    let override_source = ($override_sources | get $key)

    # Detect source types
    let default_has_path = ("path" in ($default_source | columns))
    let default_has_git = (("url" in ($default_source | columns)) or ("ref" in ($default_source | columns)))
    let override_has_path = ("path" in ($override_source | columns))
    let override_has_git = (("url" in ($override_source | columns)) or ("ref" in ($override_source | columns)))

    # Route to appropriate merge function
    if ($override_has_path and $default_has_git) or ($override_has_git and $default_has_path) {
      # Type switch: full replacement
      $result = ($result | upsert $key $override_source)
    } else if $override_has_git and $default_has_git {
      # Both Git: use Git merge with mode detection
      $result = ($result | upsert $key (merge-git-source $default_source $override_source))
    } else if $override_has_path and $default_has_path {
      # Both Local: use local merge (replacement)
      $result = ($result | upsert $key (merge-local-source $default_source $override_source))
    } else if ($override_source | is-empty) and $default_has_git {
      # Empty override with Git default: preserve default via merge-git-source
      $result = ($result | upsert $key (merge-git-source $default_source $override_source))
    } else {
      # No default or override only: use override
      $result = ($result | upsert $key $override_source)
    }
  }

  $result
}

# Apply version defaults to version spec (deep-merge defaults into overrides)
export def apply-version-defaults [
  manifest: record,
  version_spec: record
] {
  let defaults = (try { $manifest.defaults } catch { {} })
  if ($defaults | is-empty) {
    return $version_spec
  }

  mut version = $version_spec
  let overrides = (try { $version.overrides } catch { {} })

  # Extract global defaults (exclude platforms if present)
  let global_defaults = (if "platforms" in ($defaults | columns) {
    $defaults | reject platforms
  } else {
    $defaults
  })

  let merged_overrides = (if ($overrides | is-empty) {
    # Even with empty overrides, we might have platform-specific defaults
    if "platforms" in ($defaults | columns) {
      $defaults  # Return full defaults including platforms
    } else {
      $global_defaults
    }
  } else {
    # Deep merge global defaults into global overrides
    let global_overrides = (if "platforms" in ($overrides | columns) {
      $overrides | reject platforms
    } else {
      $overrides
    })
    
    # Extract and replace sources per key
    let default_sources = (try { $global_defaults.sources } catch { {} })
    let override_sources = (try { $global_overrides.sources } catch { {} })
    let merged_sources = (merge-sources-per-key $default_sources $override_sources)
    
    # Merge everything else (excluding sources)
    let defaults_other = (if "sources" in ($global_defaults | columns) {
      $global_defaults | reject sources
    } else {
      $global_defaults
    })
    let overrides_other = (if "sources" in ($global_overrides | columns) {
      $global_overrides | reject sources
    } else {
      $global_overrides
    })
    mut merged_global = (deep-merge $defaults_other $overrides_other)
    
    # Insert merged sources
    if not ($merged_sources | is-empty) {
      $merged_global = ($merged_global | insert sources $merged_sources)
    }

    # Handle platform-specific defaults
    if "platforms" in ($defaults | columns) {
      let default_platforms = $defaults.platforms
      let override_platforms = (try { $overrides.platforms } catch { {} })

      mut merged_platforms = $override_platforms
      for platform_name in ($default_platforms | columns) {
        let platform_defaults = ($default_platforms | get $platform_name)
        let platform_overrides = (try { $override_platforms | get $platform_name } catch { {} })
        
        # Extract and replace platform sources per key
        let platform_default_sources = (try { $platform_defaults.sources } catch { {} })
        let platform_override_sources = (try { $platform_overrides.sources } catch { {} })
        let merged_platform_sources = (merge-sources-per-key $platform_default_sources $platform_override_sources)
        
        # Merge everything else (excluding sources)
        let platform_defaults_other = (if "sources" in ($platform_defaults | columns) {
          $platform_defaults | reject sources
        } else {
          $platform_defaults
        })
        let platform_overrides_other = (if "sources" in ($platform_overrides | columns) {
          $platform_overrides | reject sources
        } else {
          $platform_overrides
        })
        mut merged_platform = (deep-merge $platform_defaults_other $platform_overrides_other)
        
        # Insert merged platform sources
        if not ($merged_platform_sources | is-empty) {
          $merged_platform = ($merged_platform | insert sources $merged_platform_sources)
        }
        
        $merged_platforms = ($merged_platforms | upsert $platform_name $merged_platform)
      }
      $merged_global = ($merged_global | insert platforms $merged_platforms)
    } else if "platforms" in ($overrides | columns) {
      # No platform defaults, but overrides has platforms - keep them
      $merged_global = ($merged_global | insert platforms $overrides.platforms)
    }

    $merged_global
  })

  $version = ($version | upsert overrides $merged_overrides)
  $version
}

export def get-version-spec [
  manifest: record,
  version_name: string
] {
  let versions = (try {
    $manifest.versions
  } catch {
    error make { msg: "Manifest missing 'versions' field" }
  })
  
  let found = ($versions | where name == $version_name)
  
  if ($found | is-empty) {
    error make { msg: $"Version '($version_name)' not found in manifest" }
  }
  
  let version_spec = $found.0
  
  # Apply defaults before returning
  apply-version-defaults $manifest $version_spec
}

export def get-latest-versions [
  manifest: record
] {
  let versions = (try {
    $manifest.versions
  } catch {
    []
  })
  
  $versions | where ($it.latest? | default false) == true
}

# Filter versions (strips platform suffixes from input, returns {versions, detected_platforms})
export def filter-versions [
  manifest: record,
  platforms_manifest: any = null,
  --all = false,
  --versions: string = "",
  --latest-only = false
] {
  let all_versions = (try {
    $manifest.versions
  } catch {
    []
  })
  
  if $all {
    return {versions: $all_versions, detected_platforms: []}
  }
  
  if $latest_only {
    return {versions: ($all_versions | where ($it.latest? | default false) == true), detected_platforms: []}
  }
  
  if ($versions | str length) > 0 {
    let requested = ($versions | split row "," | each {|v| $v | str trim} | where ($it | str length) > 0)
    
    if ($requested | is-empty) {
      return {versions: [], detected_platforms: []}
    }
    
    mut base_names = []
    mut detected_platforms = []
    
    for version_name in $requested {
      if $platforms_manifest != null {
        use ../platforms/core.nu [strip-platform-suffix]
        let stripped = (try {
          strip-platform-suffix $version_name $platforms_manifest
        } catch {
          {base_name: $version_name, platform_name: ""}
        })
        
        $base_names = ($base_names | append $stripped.base_name)
        
        if ($stripped.platform_name | str length) > 0 {
          if not ($stripped.platform_name in $detected_platforms) {
            $detected_platforms = ($detected_platforms | append $stripped.platform_name)
          }
        }
      } else {
        $base_names = ($base_names | append $version_name)
      }
    }
    
    let unique_base_names = ($base_names | uniq)
    let matched = ($all_versions | where $it.name in $unique_base_names)
    
    return {versions: $matched, detected_platforms: $detected_platforms}
  }
  
  return {versions: [], detected_platforms: []}
}

# Resolve version name from CLI args or manifest (returns {base_name, detected_platform})
export def resolve-version-name [
  version_arg: string,
  versions_manifest: record,
  platforms_manifest: any,
  version_suffix_info: any
] {
  if $version_suffix_info != null {
    return {
      base_name: $version_suffix_info.base_name,
      detected_platform: $version_suffix_info.platform_name
    }
  }
  
  if ($version_arg | str length) > 0 {
    if $platforms_manifest != null {
      use ../platforms/core.nu [strip-platform-suffix]
      let stripped = (try {
        strip-platform-suffix $version_arg $platforms_manifest
      } catch {
        return {base_name: $version_arg, detected_platform: ""}
      })
      return {base_name: $stripped.base_name, detected_platform: $stripped.platform_name}
    } else {
      return {base_name: $version_arg, detected_platform: ""}
    }
  }
  
  if $versions_manifest != null {
    let default_version = (get-default-version $versions_manifest)
    return {base_name: $default_version, detected_platform: ""}
  }
  
  return {base_name: "", detected_platform: ""}
}

export def get-version-or-null [
  versions_manifest: record,
  version_name: string
] {
  if $versions_manifest == null {
    return null
  }
  
  if ($version_name | str length) == 0 {
    let default_name = (get-default-version $versions_manifest)
    return (get-version-spec $versions_manifest $default_name)
  }
  
  try {
    get-version-spec $versions_manifest $version_name
  } catch {
    return null
  }
}
