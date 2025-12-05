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

# Dependency resolution for builds
# See docs/concepts/dependency-management.md for details

use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest has-platform-suffix]

# Resolve dependency tag with platform inheritance
def resolve-dependency-tag [
  dep_config: record,
  parent_version: string,
  dep_service: string,
  dep_key: string,
  platform: string = "",
  platforms: any = null
] {
  let explicit_version = (try {
    $dep_config.version
  } catch {
    ""
  })
  
  if ($explicit_version | str length) > 0 {
    # Check platform suffix against dependency's platforms FIRST
    # A platform suffix is only valid if it matches the dependency service's platforms
    let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
    let dep_platforms = (if $dep_has_platforms {
      try {
        load-platforms-manifest $dep_service
      } catch {
        null  # Treat as single-platform if load fails
      }
    } else {
      null
    })
    
    let has_suffix = (if $dep_platforms != null {
      has-platform-suffix $explicit_version $dep_platforms
    } else {
      false  # No platforms manifest = no suffix detection
    })
    
    if $has_suffix {
      # Explicit platform suffix detected - use as-is (no inheritance, no single_platform logic)
      # If single_platform flag is also set, warn that suffix takes precedence
      let single_platform = (try { $dep_config.single_platform | default false } catch { false })
      if $single_platform {
        print $"Warning: Dependency '($dep_key)' has both platform suffix in version '($explicit_version)' and single_platform: true. Platform suffix takes precedence, single_platform flag is ignored."
      }
      return $explicit_version
    } else {
      # No valid platform suffix detected
      # Check for single_platform flag (only true has meaning, false is treated as not set)
      let single_platform = (try {
        let val = ($dep_config.single_platform | default false)
        if $val == true { true } else { false }
      } catch { false })
      
      if $single_platform {
        # Explicitly marked as single-platform - use version as-is, no platform suffix
        # Warn if dependency actually has platforms (misconfiguration)
        let dep_has_platforms_check = (check-platforms-manifest-exists $dep_service)
        if $dep_has_platforms_check {
          print $"Warning: Dependency '($dep_key)' (service: ($dep_service)) has single_platform: true but service '($dep_service)' has platforms.nuon. Using version without platform suffix anyway."
        }
        return $explicit_version
      }
      
      # No single_platform flag - apply platform inheritance if parent is multi-platform
      if ($platform | str length) > 0 {
        let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
        
        if not $dep_has_platforms {
          # Single-platform dependency - allow it with informational message
          print $"Info: Multi-platform service depends on single-platform service '($dep_service)'. Dependency '($dep_key)' will use version '($explicit_version)' for all platforms. If this is intentional, consider adding 'single_platform: true' to suppress this message."
          return $explicit_version
        }
        
        # Dependency has platforms - use platform inheritance
        let has_dashes = ($explicit_version | str contains "-")
        if $has_dashes {
          print $"Warning: Dependency '($dep_key)' version '($explicit_version)' does not have a valid platform suffix for '($dep_service)' platforms, inheriting '($platform)' from parent"
        } else {
          print $"Warning: Dependency '($dep_key)' version '($explicit_version)' lacks platform suffix, inheriting '($platform)' from parent"
        }
        return $"($explicit_version)-($platform)"
      } else {
        return $explicit_version
      }
    }
  }
  
  # Parent version inheritance path
  if ($parent_version | str length) > 0 {
    # Check for single_platform flag (only true has meaning)
    let single_platform = (try {
      let val = ($dep_config.single_platform | default false)
      if $val == true { true } else { false }
    } catch { false })
    
    if $single_platform {
      let dep_has_platforms_check = (check-platforms-manifest-exists $dep_service)
      if $dep_has_platforms_check {
        print $"Warning: Dependency '($dep_key)' (service: ($dep_service)) has single_platform: true but service '($dep_service)' has platforms.nuon. Using version without platform suffix anyway."
      }
      return $parent_version
    }
    
    if ($platform | str length) > 0 {
      let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
      
      if not $dep_has_platforms {
        # Single-platform dependency - allow with informational message
        print $"Info: Multi-platform service depends on single-platform service '($dep_service)'. Dependency '($dep_key)' will use version '($parent_version)' for all platforms. If this is intentional, consider adding 'single_platform: true' to suppress this message."
        return $parent_version
      }
      
      return $"($parent_version)-($platform)"
    } else {
      return $parent_version
    }
  }
  
  error make { msg: $"Dependency '($dep_key)' must have explicit 'version' field or inherit from parent version" }
}

def check-image-exists [
  image_ref: string,
  is_local: bool,
  registry_info: record
] {
  # Always check locally first (handles --load builds in CI)
  let local_exists = (try {
    let cmd_result = (^docker image inspect $image_ref | complete)
    $cmd_result.exit_code == 0
  } catch {
    false
  })
  
  if $local_exists {
    return true
  }
  
  # For local builds, we're done
  if $is_local {
    return false
  }
  
  # In CI, also check remote registry
  let remote_exists = (try {
    let cmd_result = (^docker manifest inspect $image_ref | complete)
    $cmd_result.exit_code == 0
  } catch {
    false
  })
  
  $remote_exists
}

def construct-image-ref [
  service: string,
  tag: string,
  is_local: bool,
  registry_info: record
] {
  if $is_local {
    return $"($service):($tag)"
  }
  
  # Use ci_platform to select correct registry (matches pull.nu behavior)
  let ci_platform = (try { $registry_info.ci_platform } catch { "local" })
  
  if $ci_platform == "github" {
    $"($registry_info.github_registry)/($registry_info.github_path)/($service):($tag)"
  } else if $ci_platform == "forgejo" {
    $"($registry_info.forgejo_registry)/($registry_info.forgejo_path)/($service):($tag)"
  } else {
    # Fallback to local format
    $"($service):($tag)"
  }
}

# Resolve all dependencies for a service (platform-aware)
# See docs/concepts/dependency-management.md for resolution rules
export def resolve-dependencies [
  service_config: record,
  parent_version: string,
  is_local: bool,
  registry_info: record,
  platform: string = "",
  platforms: any = null
] {
  let deps = (try {
    $service_config.dependencies
  } catch {
    {}
  })
  
  if ($deps | is-empty) or ($deps == null) {
    return {}
  }
  
  mut resolved = {}
  
  for dep_key in ($deps | columns) {
    let dep = ($deps | get $dep_key)
    
    let dep_service = (try {
      $dep.service
    } catch {
      $dep_key
    })
    
    let resolved_tag = (resolve-dependency-tag $dep $parent_version $dep_service $dep_key $platform $platforms)
    let image_ref = (construct-image-ref $dep_service $resolved_tag $is_local $registry_info)
    let exists = (check-image-exists $image_ref $is_local $registry_info)
    if not $exists {
      let error_msg = (if ($platform | str length) > 0 {
        $"Dependency image '($image_ref)' not found for platform '($platform)'. Please build it first: nu scripts/build.nu --service ($dep_service) --version ($resolved_tag)"
      } else {
        $"Dependency image '($image_ref)' not found. Please build it first: nu scripts/build.nu --service ($dep_service) --version ($resolved_tag)"
      })
      error make { msg: $error_msg }
    }
    
    let build_arg = (try {
      $dep.build_arg
    } catch {
      ""
    })
    if ($build_arg | str length) == 0 {
      error make { msg: ($"Dependency '($dep_key)' missing 'build_arg' field") }
    }
    
    $resolved = ($resolved | insert $build_arg $image_ref)
  }
  
  return $resolved
}
