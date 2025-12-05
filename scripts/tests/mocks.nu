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

# Mock infrastructure for test isolation
# Replaces real dependencies with test-controlled alternatives

use ../lib/core/records.nu [deep-merge]
use ../lib/platforms/core.nu [
  strip-platform-suffix
  has-platform-suffix
  get-platform-spec
  get-platform-names
  merge-platform-config
  merge-version-overrides
]
use ../lib/validate/core.nu [validate-merged-config]
use ../lib/manifest/core.nu [get-version-or-null check-versions-manifest-exists]

# Test-controlled registry for platform manifest existence
# Using $env to store registry state (allows mutation from functions)

# Mock get-default-platform - returns default platform from platforms manifest
export def get-default-platform [platforms: record] {
  try { $platforms.default } catch { "" }
}

# Mock detect-build - returns test metadata
export def detect-build [] {
  {
    ref: "test-branch",
    sha: "test-sha-1234567890abcdef",
    commit_message: "Test commit message",
    is_local: true,
    platforms: ["linux/amd64"]
  }
}

# Mock get-mock-service-config - replaces load-service-config
export def get-mock-service-config [
  service: string,
  version_spec: record,
  platform: string = "",
  platforms: any = null
] {
  # Create base config with required fields
  mut base_cfg = {
    name: $service,
    context: $"services/($service)",
    dockerfile: $"services/($service)/Dockerfile",
    sources: {
      test_source: {
        url: "https://github.com/test/repo",
        ref: "v1.0.0"
      }
    }
  }
  
  # Check if this service has registered dependencies
  let registered_deps = (get-registered-dependencies $service $version_spec.name)
  if not ($registered_deps | is-empty) {
    $base_cfg = ($base_cfg | insert dependencies $registered_deps)
  }
  
  # Add external_images.build with tag if version_spec has overrides
  if "overrides" in ($version_spec | columns) {
    let overrides = $version_spec.overrides
    if "external_images" in ($overrides | columns) {
      let ext_images = $overrides.external_images
      if "build" in ($ext_images | columns) {
        let build_img = $ext_images.build
        if "tag" in ($build_img | columns) {
          $base_cfg = ($base_cfg | insert external_images {
            build: {
              name: (try { $build_img.name } catch { "golang" }),
              tag: $build_img.tag,
              build_arg: (try { $build_img.build_arg } catch { "BASE_BUILD_IMAGE" })
            }
          })
        }
      }
    }
  }
  
  # If no external_images yet, add default
  if not ("external_images" in ($base_cfg | columns)) {
    $base_cfg = ($base_cfg | insert external_images {
      build: {
        name: "golang",
        tag: "1.25-trixie",
        build_arg: "BASE_BUILD_IMAGE"
      }
    })
  }
  
  mut merged_cfg = $base_cfg
  
  # Apply platform config merge if platform specified
  if ($platform | str length) > 0 {
    if $platforms == null {
      error make { msg: $"Platform '($platform)' specified but platforms manifest not provided to get-mock-service-config" }
    }
    let platform_spec = (get-platform-spec $platforms $platform)
    $merged_cfg = (merge-platform-config $merged_cfg $platform_spec)
  }
  
  # Apply version overrides merge
  $merged_cfg = (merge-version-overrides $merged_cfg $version_spec $platform $platforms)
  
  # Calculate has_platforms (matches real code logic)
  let has_platforms = (if $platforms != null {
    true
  } else {
    (check-platforms-manifest-exists $service)
  })
  
  # Validate merged config before returning
  let validation = (validate-merged-config $merged_cfg $service $has_platforms $platform)
  if not $validation.valid {
    error make { msg: $"Mock config validation failed for service '($service)': ($validation.errors | str join ', ')" }
  }
  
  $merged_cfg
}

# Build mock version manifest - test-specific builder
export def build-mock-version-manifest [
  default_version: string = "v1.0.0",
  versions: list = []
] {
  # If no versions provided, create default
  let version_list = (if ($versions | length) == 0 {
    [{
      name: $default_version,
      latest: true,
      tags: [],
      overrides: {}
    }]
  } else {
    $versions
  })
  
  {
    default: $default_version,
    versions: $version_list
  }
}

# Build mock platform manifest - test-specific builder
export def build-mock-platform-manifest [
  default_platform: string = "debian",
  platforms: list = []
] {
  # If no platforms provided, create default single-platform
  let platform_list = (if ($platforms | length) == 0 {
    [{
      name: $default_platform,
      dockerfile: $"services/test-service/Dockerfile",
      external_images: {
        build: {
          name: "golang",
          tag: "1.25-trixie",
          build_arg: "BASE_BUILD_IMAGE"
        }
      }
    }]
  } else {
    $platforms
  })
  
  {
    default: $default_platform,
    platforms: $platform_list
  }
}

# Test-controlled registry functions for platform behavior
export def set-mock-platform-behavior [service: string, has_platforms: bool] {
  # Safe environment variable access - use try-catch
  let registry_str = (try {
    $env.MOCK_PLATFORM_REGISTRY
  } catch {
    null
  })
  
  let current = (if $registry_str != null {
    try {
      $registry_str | from json
    } catch {
      {}
    }
  } else {
    {}
  })
  
  let updated = ($current | upsert $service $has_platforms)
  $env.MOCK_PLATFORM_REGISTRY = ($updated | to json)
}

export def clear-mock-platform-registry [] {
  # Explicitly unset and reinitialize to ensure clean state
  try {
    $env.MOCK_PLATFORM_REGISTRY = "{}"
  } catch {
    # If setting fails, try to unset first, then set
    try {
      hide-env MOCK_PLATFORM_REGISTRY
    } catch {}
    $env.MOCK_PLATFORM_REGISTRY = "{}"
  }
}

# Test state registry using temporary files (avoids Nushell env var persistence issues)
const TEST_STATE_FILE = ".tmp/test-state-registry.json"

# Test-controlled registry for service dependencies
export def register-mock-service-dependencies [service: string, version: string, dependencies: record] {
  init-mock-service-deps-registry
  let node_key = $"($service):($version)"
  let current = (try {
    open $TEST_STATE_FILE
  } catch {
    {}  # Return empty registry if file doesn't exist
  })
  let updated = ($current | upsert $node_key $dependencies)
  $updated | to json | save -f $TEST_STATE_FILE
}

export def clear-mock-service-deps-registry [] {
  {} | to json | save -f $TEST_STATE_FILE
}

def init-mock-service-deps-registry [] {
  if not ($TEST_STATE_FILE | path exists) {
    mkdir .tmp
    {} | to json | save -f $TEST_STATE_FILE
  }
}

def get-registered-dependencies [service: string, version: string] {
  init-mock-service-deps-registry
  let node_key = $"($service):($version)"
  let registry = (open $TEST_STATE_FILE)
  if $node_key in ($registry | columns) {
    $registry | get $node_key
  } else {
    {}
  }
}

# Mock check-platforms-manifest-exists - uses test-controlled registry
export def check-platforms-manifest-exists [service: string] {
  let registry_str = (try { $env.MOCK_PLATFORM_REGISTRY } catch { null })
  let registry = (if $registry_str != null {
    try { $registry_str | from json } catch { {} }
  } else {
    {}
  })
  if $service in ($registry | columns) {
    $registry | get $service
  } else {
    true  # Default: multi-platform
  }
}

# Mock check-versions-manifest-exists - returns true by default
export def check-versions-manifest-exists [service: string] {
  true  # Mocks assume all services have version manifests
}

# Helper: Add node to nodes list if not already present
def add-node [nodes: list, node: string] {
  if not ($node in $nodes) {
    $nodes | append $node
  } else {
    $nodes
  }
}

# Mock resolve-dep-version - copies logic from real resolve-dep-version
def resolve-dep-version-mock [
  dep_config: record,
  dep_service: string,
  parent_version: string,
  parent_platform: string,
  parent_has_platforms: bool
] {
  let explicit_version = (try { $dep_config.version } catch { "" })
  
  let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
  let dep_platforms = (if $dep_has_platforms {
    try {
      build-mock-platform-manifest  # Use default platform manifest for dependency
    } catch {
      null
    }
  } else {
    null
  })
  
  if ($explicit_version | str length) > 0 {
    # Check if explicit version has platform suffix
    let has_suffix = (if $dep_platforms != null {
      has-platform-suffix $explicit_version $dep_platforms
    } else {
      false
    })
    
    if $has_suffix {
      # Extract platform from suffix
      let stripped = (strip-platform-suffix $explicit_version $dep_platforms)
      return {version: $stripped.base_name, platform: $stripped.platform_name}
    } else {
      # Apply platform inheritance if parent is multi-platform
      if $parent_has_platforms and ($parent_platform | str length) > 0 {
        if not $dep_has_platforms {
          error make { msg: $"Multi-platform service depends on single-platform service '($dep_service)'. Dependency cannot inherit platform '($parent_platform)'." }
        }
        return {version: $explicit_version, platform: $parent_platform}
      } else {
        return {version: $explicit_version, platform: ""}
      }
    }
  }
  
  # Inherit version from parent if no explicit version
  if ($parent_version | str length) > 0 {
    if $parent_has_platforms and ($parent_platform | str length) > 0 {
      if not $dep_has_platforms {
        error make { msg: $"Multi-platform service depends on single-platform service '($dep_service)'. Dependency cannot inherit platform '($parent_platform)'." }
      }
      return {version: $parent_version, platform: $parent_platform}
    } else {
      return {version: $parent_version, platform: ""}
    }
  }
  
  error make { msg: $"Dependency '($dep_service)' must have explicit 'version' field or inherit from parent version" }
}

# Recursively build dependency graph with mocks
def build-graph-recursive-mock [
  service: string,
  version: string,
  platform: string,
  nodes: list,
  edges: list,
  visited: list,
  config_cache: record
] {
  let node_key = (if ($platform | str length) > 0 {
    $"($service):($version):($platform)"
  } else {
    $"($service):($version)"
  })
  
  # Check if already visited
  if $node_key in $visited {
    return {nodes: $nodes, edges: $edges, visited: $visited, config_cache: $config_cache}
  }
  
  # Mark as visited
  mut visited = ($visited | append $node_key)
  
  # Check cache first, load lazily if not cached
  mut merged_cfg = null
  mut config_cache = $config_cache
  
  if $node_key in ($config_cache | columns) {
    $merged_cfg = ($config_cache | get $node_key)
  } else {
    # Lazy config loading (matching real code)
    if not (check-versions-manifest-exists $service) {
      error make { msg: $"Service '($service)' does not have a version manifest" }
    }
    
    # Use the resolved version to create the manifest (CRITICAL FIX)
    let versions_manifest = (build-mock-version-manifest $version)
    let has_platforms = (check-platforms-manifest-exists $service)
    let platforms_manifest = (if $has_platforms {
      build-mock-platform-manifest
    } else {
      null
    })
    
    # Strip platform suffix if needed
    let base_version_name = (if $platforms_manifest != null {
      let stripped = (strip-platform-suffix $version $platforms_manifest)
      $stripped.base_name
    } else {
      $version
    })
    
    # Get version spec
    let version_spec = (get-version-or-null $versions_manifest $base_version_name)
    if $version_spec == null {
      error make { msg: $"Version '($base_version_name)' not found in manifest for service '($service)'" }
    }
    
    # Load and merge config
    $merged_cfg = (get-mock-service-config $service $version_spec $platform $platforms_manifest)
    
    # Cache config
    mut config_cache = ($config_cache | insert $node_key $merged_cfg)
  }
  
  # Add node to nodes list
  let nodes = (add-node $nodes $node_key)
  
  # Extract dependencies
  let dependencies = (try { $merged_cfg.dependencies } catch { {} })
  
  # Process dependencies using reduce (for loops don't work with mut variables in Nushell)
  if not ($dependencies | is-empty) {
    # Check if parent has platforms
    let parent_has_platforms = (check-platforms-manifest-exists $service)
    
    # Use reduce to process dependencies, accumulating state
    # Note: reduce parameter order is {|item, acc|} not {|acc, item|}
    let result = ($dependencies | columns | reduce --fold {
      nodes: $nodes,
      edges: $edges,
      visited: $visited,
      config_cache: $config_cache
    } {|item, acc|
      let dep_key = $item
      let dep_config = ($dependencies | get $dep_key)
      
      # Check dep_config.service first (expected fixed behavior), fall back to dep_key
      let dep_service = (if "service" in ($dep_config | columns) {
        $dep_config.service
      } else {
        $dep_key
      })
      
      # Resolve dependency version/platform
      let dep_resolved = (resolve-dep-version-mock $dep_config $dep_service $version $platform $parent_has_platforms)
      
      # Create dependency node
      let dep_node_key = (if ($dep_resolved.platform | str length) > 0 {
        $"($dep_service):($dep_resolved.version):($dep_resolved.platform)"
      } else {
        $"($dep_service):($dep_resolved.version)"
      })
      
      # Add dependency node to graph
      let new_nodes = (add-node $acc.nodes $dep_node_key)
      
      # Add edge from current node to dependency node
      let new_edges = ($acc.edges | append {from: $node_key, to: $dep_node_key})
      
      # Recurse into dependency
      build-graph-recursive-mock $dep_service $dep_resolved.version $dep_resolved.platform $new_nodes $new_edges $acc.visited $acc.config_cache
    })
    
    $result
  } else {
    {nodes: $nodes, edges: $edges, visited: $visited, config_cache: $config_cache}
  }
}

# Build dependency graph with mocks - matches real build-dependency-graph signature
export def build-dependency-graph-with-mocks [
  service: string,
  version_spec: record,
  merged_cfg: record,
  platform: string,
  platforms: any,
  is_local: bool,
  registry_info: record
] {
  mut nodes = []
  mut edges = []
  mut visited = []
  
  # Pre-populate config cache with ALL registered service configs
  # This ensures recursive graph traversal finds dependency configs
  init-mock-service-deps-registry
  let registry = (try {
    open $TEST_STATE_FILE
  } catch {
    {}  # Return empty registry if file doesn't exist
  })
  
  # Use reduce to populate config cache (CRITICAL: for loop doesn't work)
  let config_cache = ($registry | columns | reduce --fold {} {|item, acc|
    let node_key = $item
    let parts = ($node_key | split row ":")
    let svc = ($parts | first)
    let ver = ($parts | last)
    let deps = ($registry | get $node_key)
    
    # Create a minimal config with dependencies
    let svc_cfg = {
      name: $svc,
      context: $"services/($svc)",
      dockerfile: $"services/($svc)/Dockerfile",
      sources: {
        test_source: {
          url: "https://github.com/test/repo",
          ref: "v1.0.0"
        }
      },
      external_images: {
        build: {
          name: "golang",
          tag: "1.25-trixie",
          build_arg: "BASE_BUILD_IMAGE"
        }
      },
      dependencies: $deps
    }
    $acc | upsert $node_key $svc_cfg
  })
  
  # Create target node
  let version_name = $version_spec.name
  let node_key = (if ($platform | str length) > 0 {
    $"($service):($version_name):($platform)"
  } else {
    $"($service):($version_name)"
  })
  
  # Pre-cache the target service config (this preserves dependencies from test setup)
  let config_cache = ($config_cache | upsert $node_key $merged_cfg)
  
  # Build graph recursively
  let result = (build-graph-recursive-mock $service $version_name $platform $nodes $edges $visited $config_cache)
  
  {
    nodes: $result.nodes,
    edges: $result.edges
  }
}
