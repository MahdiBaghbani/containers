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

use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest has-platform-suffix strip-platform-suffix]

# Apply single_platform / parent-platform inheritance to an already-chosen base
# version, returning {version, platform}. Shared by the explicit-version and
# parent-inherited-version paths so the inheritance decision lives in one place.
#
# Exported so the test mock can reuse the exact same inheritance decision
# instead of maintaining a drift-prone copy. This helper is pure (no manifest
# I/O), so reusing it does not pull real filesystem loading into the mock path.
export def apply-platform-inheritance [
  dep_service: string,
  base_version: string,
  single_platform: bool,
  dep_has_platforms: bool,
  parent_has_platforms: bool,
  parent_platform: string
] {
  if $single_platform {
    if $dep_has_platforms {
      print $"Warning: Dependency '($dep_service)' has single_platform: true but has platforms.nuon. Using version without platform suffix anyway."
    }
    {version: $base_version, platform: ""}
  } else if $parent_has_platforms and ($parent_platform | str length) > 0 {
    if not $dep_has_platforms {
      # Single-platform dependency - allow with informational message
      print $"Info: Multi-platform service depends on single-platform service '($dep_service)'. Dependency will use version '($base_version)' for all platforms. If intentional, add 'single_platform: true' to suppress this message."
      {version: $base_version, platform: ""}
    } else {
      {version: $base_version, platform: $parent_platform}
    }
  } else {
    {version: $base_version, platform: ""}
  }
}

# Fail-closed platforms-manifest resolution for a dependency edge.
#
# When a dependency declares a platforms manifest (dep_has_platforms == true)
# but loading it fails, raise instead of silently degrading to single-platform.
# A silent degrade would drop the platform suffix and produce a wrong node key.
# The manifest load is injected as a closure so this branch is unit-testable
# without a real malformed platforms.nuon on disk. Returns the loaded manifest,
# or null when the dependency has no platforms manifest.
export def resolve-dep-platforms [
  dep_service: string,
  dep_has_platforms: bool,
  load_manifest: closure
] {
  if $dep_has_platforms {
    try {
      do $load_manifest
    } catch {|err|
      let detail = (try { $err.msg } catch { "unknown error" })
      error make { msg: $"Dependency '($dep_service)' declares a platforms manifest that failed to load: ($detail). Refusing to silently treat '($dep_service)' as single-platform; fix or remove its platforms.nuon." }
    }
  } else {
    null
  }
}

# Resolve a dependency edge to its {version, platform}.
#
# This is the single decision tree for dependency version/platform resolution.
# Both the graph node key (resolve-dep-node) and the image tag string
# (resolve-dependency-tag) are derived from this result, so the two cannot
# drift apart.
#
# Fail-closed: if the dependency declares a platforms manifest but it cannot be
# loaded, raise an error instead of silently degrading to single-platform. A
# malformed manifest would otherwise produce a wrong (suffix-less) node key.
def resolve-dep-version-platform [
  dep_config: record,
  dep_service: string,
  parent_version: string,
  parent_platform: string,
  parent_has_platforms: bool
] {
  let explicit_version = (try { $dep_config.version } catch { "" })

  let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
  let dep_platforms = (resolve-dep-platforms $dep_service $dep_has_platforms {|| load-platforms-manifest $dep_service })

  let single_platform = (try {
    let val = ($dep_config.single_platform | default false)
    if $val == true { true } else { false }
  } catch { false })

  if ($explicit_version | str length) > 0 {
    # Explicit platform suffix wins over inheritance and single_platform.
    let has_suffix = (if $dep_platforms != null {
      has-platform-suffix $explicit_version $dep_platforms
    } else {
      false
    })

    if $has_suffix {
      if $single_platform {
        print $"Warning: Dependency '($dep_service)' has both platform suffix in version '($explicit_version)' and single_platform: true. Platform suffix takes precedence, single_platform flag is ignored."
      }
      let stripped = (strip-platform-suffix $explicit_version $dep_platforms)
      {version: $stripped.base_name, platform: $stripped.platform_name}
    } else {
      apply-platform-inheritance $dep_service $explicit_version $single_platform $dep_has_platforms $parent_has_platforms $parent_platform
    }
  } else if ($parent_version | str length) > 0 {
    apply-platform-inheritance $dep_service $parent_version $single_platform $dep_has_platforms $parent_has_platforms $parent_platform
  } else {
    error make { msg: $"Dependency '($dep_service)' must have explicit 'version' field or inherit from parent version" }
  }
}

# Resolve a dependency to its graph node identity (version, platform, node_key).
#
# This is the single source of truth for how a dependency edge maps to a node
# key in both the build graph (order.nu) and the service-definition hash graph
# (hash.nu). Keeping both callers on this function prevents the two from
# drifting (for example, the hash graph reconstructing keys with looser logic
# and then failing to find the matching hash).
#
# Returns {version: string, platform: string, node_key: string}.
export def resolve-dep-node [
  dep_config: record,
  dep_service: string,
  parent_version: string,
  parent_platform: string,
  parent_has_platforms: bool
] {
  let resolved = (resolve-dep-version-platform $dep_config $dep_service $parent_version $parent_platform $parent_has_platforms)

  let node_key = (if ($resolved.platform | str length) > 0 {
    $"($dep_service):($resolved.version):($resolved.platform)"
  } else {
    $"($dep_service):($resolved.version)"
  })

  {version: $resolved.version, platform: $resolved.platform, node_key: $node_key}
}

# Resolve a dependency to its image tag string with platform inheritance.
#
# Derives the tag from the shared {version, platform} resolver so the tag and
# the graph node key stay consistent. A non-empty platform becomes a
# "-<platform>" suffix; otherwise the version is used as-is.
def resolve-dependency-tag [
  dep_config: record,
  parent_version: string,
  dep_service: string,
  platform: string = ""
] {
  # The tag path only knows the parent platform string, so a non-empty parent
  # platform implies the parent is multi-platform (matches prior behavior).
  let parent_has_platforms = (($platform | str length) > 0)
  let resolved = (resolve-dep-version-platform $dep_config $dep_service $parent_version $platform $parent_has_platforms)

  if ($resolved.platform | str length) > 0 {
    $"($resolved.version)-($resolved.platform)"
  } else {
    $resolved.version
  }
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
    
    let resolved_tag = (resolve-dependency-tag $dep $parent_version $dep_service $platform)
    let image_ref = (construct-image-ref $dep_service $resolved_tag $is_local $registry_info)
    let exists = (check-image-exists $image_ref $is_local $registry_info)
    if not $exists {
      let error_msg = (if ($platform | str length) > 0 {
        $"Dependency image '($image_ref)' not found for platform '($platform)'. Please build it first: nu scripts/dockypody.nu build --service ($dep_service) --version ($resolved_tag)"
      } else {
        $"Dependency image '($image_ref)' not found. Please build it first: nu scripts/dockypody.nu build --service ($dep_service) --version ($resolved_tag)"
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
