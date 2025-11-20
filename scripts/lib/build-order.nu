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

use ./manifest.nu [check-versions-manifest-exists load-versions-manifest get-version-or-null get-default-version]
use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform strip-platform-suffix has-platform-suffix]
use ./build-ops.nu [load-service-config]

# Helper: Add node to nodes list if not already present
def add-node [nodes: list, node: string] {
  if not ($node in $nodes) {
    $nodes | append $node
  } else {
    $nodes
  }
}

# Resolve dependency version and platform
# Returns {version: string, platform: string}
def resolve-dep-version [
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
      load-platforms-manifest $dep_service
    } catch {
      null
    }
  } else {
    null
  })
  
  if ($explicit_version | str length) > 0 {
    # Check if explicit version has platform suffix FIRST
    let has_suffix = (if $dep_platforms != null {
      has-platform-suffix $explicit_version $dep_platforms
    } else {
      false
    })
    
    if $has_suffix {
      # Extract platform from suffix - use as-is
      # If single_platform flag is also set, warn that suffix takes precedence
      let single_platform = (try {
        let val = ($dep_config.single_platform | default false)
        if $val == true { true } else { false }
      } catch { false })
      if $single_platform {
        print $"Warning: Dependency '($dep_service)' has both platform suffix in version '($explicit_version)' and single_platform: true. Platform suffix takes precedence, single_platform flag is ignored."
      }
      let stripped = (strip-platform-suffix $explicit_version $dep_platforms)
      return {version: $stripped.base_name, platform: $stripped.platform_name}
    } else {
      # No platform suffix - check for single_platform flag (only true has meaning)
      let single_platform = (try {
        let val = ($dep_config.single_platform | default false)
        if $val == true { true } else { false }
      } catch { false })
      
      if $single_platform {
        let dep_has_platforms_check = (check-platforms-manifest-exists $dep_service)
        if $dep_has_platforms_check {
          print $"Warning: Dependency '($dep_service)' has single_platform: true but has platforms.nuon. Using version without platform suffix anyway."
        }
        return {version: $explicit_version, platform: ""}
      }
      
      # Apply platform inheritance if parent is multi-platform
      if $parent_has_platforms and ($parent_platform | str length) > 0 {
        let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
        
        if not $dep_has_platforms {
          # Single-platform dependency - allow with informational message
          print $"Info: Multi-platform service depends on single-platform service '($dep_service)'. Dependency will use version '($explicit_version)' for all platforms. If intentional, add 'single_platform: true' to suppress this message."
          return {version: $explicit_version, platform: ""}
        }
        
        return {version: $explicit_version, platform: $parent_platform}
      } else {
        return {version: $explicit_version, platform: ""}
      }
    }
  }
  
  # Inherit version from parent if no explicit version
  if ($parent_version | str length) > 0 {
    let single_platform = (try {
      let val = ($dep_config.single_platform | default false)
      if $val == true { true } else { false }
    } catch { false })
    
    if $single_platform {
      let dep_has_platforms_check = (check-platforms-manifest-exists $dep_service)
      if $dep_has_platforms_check {
        print $"Warning: Dependency '($dep_service)' has single_platform: true but has platforms.nuon. Using version without platform suffix anyway."
      }
      return {version: $parent_version, platform: ""}
    }
    
    if $parent_has_platforms and ($parent_platform | str length) > 0 {
      let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
      
      if not $dep_has_platforms {
        # Single-platform dependency - allow with informational message
        print $"Info: Multi-platform service depends on single-platform service '($dep_service)'. Dependency will use version '($parent_version)' for all platforms. If intentional, add 'single_platform: true' to suppress this message."
        return {version: $parent_version, platform: ""}
      }
      
      return {version: $parent_version, platform: $parent_platform}
    } else {
      return {version: $parent_version, platform: ""}
    }
  }
  
  error make { msg: $"Dependency '($dep_service)' must have explicit 'version' field or inherit from parent version" }
}

# Load service config for graph construction (with caching)
# Returns {config: record, cache: record}
def load-service-config-for-graph [
  service: string,
  version_name: string,
  platform: string,
  config_cache: record
] {
  let node_key = (if ($platform | str length) > 0 {
    $"($service):($version_name):($platform)"
  } else {
    $"($service):($version_name)"
  })
  
  # Check cache
  if $node_key in ($config_cache | columns) {
    return {config: ($config_cache | get $node_key), cache: $config_cache}
  }
  
  # Load versions manifest
  if not (check-versions-manifest-exists $service) {
    error make { msg: $"Service '($service)' does not have a version manifest" }
  }
  
  let versions_manifest = (load-versions-manifest $service)
  
  # Resolve version name (strip platform suffix if needed)
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms {
    try {
      load-platforms-manifest $service
    } catch {
      null
    }
  } else {
    null
  })
  
  let base_version_name = (if $platforms_manifest != null {
    let stripped = (try {
      strip-platform-suffix $version_name $platforms_manifest
    } catch {
      {base_name: $version_name, platform_name: ""}
    })
    $stripped.base_name
  } else {
    $version_name
  })
  
  # Get version_spec
  let version_spec = (get-version-or-null $versions_manifest $base_version_name)
  if $version_spec == null {
    error make { msg: $"Version '($base_version_name)' not found in manifest for service '($service)'" }
  }
  
  # Load and merge config
  let merged_cfg = (load-service-config $service $version_spec $platform $platforms_manifest)
  
  # Cache and return
  let updated_cache = ($config_cache | insert $node_key $merged_cfg)
  {config: $merged_cfg, cache: $updated_cache}
}

# Recursively build dependency graph (using reduce to avoid Nushell for loop scope issues)
def build-graph-recursive [
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
  let visited = ($visited | append $node_key)
  
  # Load config (with caching)
  let config_result = (load-service-config-for-graph $service $version $platform $config_cache)
  let merged_cfg = $config_result.config
  let config_cache = $config_result.cache
  
  # Add node to graph
  let nodes = (add-node $nodes $node_key)
  
  # Extract dependencies
  let dependencies = (try { $merged_cfg.dependencies } catch { {} })
  
  # Process dependencies using reduce (for loops don't work with mut variables in Nushell)
  if not ($dependencies | is-empty) {
    # Check if parent has platforms
    let parent_has_platforms = (check-platforms-manifest-exists $service)
    
    # Use reduce to process dependencies, accumulating state
    let result = ($dependencies | columns | reduce --fold {
      nodes: $nodes,
      edges: $edges,
      visited: $visited,
      config_cache: $config_cache
    } {|item, acc|
      let dep_key = $item
      let dep_config = ($dependencies | get $dep_key)
      # Use 'service' field from config if present, otherwise use dependency key as service name
      let dep_service = (try { $dep_config.service } catch { $dep_key })
      
      # Resolve dependency version/platform
      let dep_resolved = (resolve-dep-version $dep_config $dep_service $version $platform $parent_has_platforms)
      
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
      build-graph-recursive $dep_service $dep_resolved.version $dep_resolved.platform $new_nodes $new_edges $acc.visited $acc.config_cache
    })
    
    $result
  } else {
    {nodes: $nodes, edges: $edges, visited: $visited, config_cache: $config_cache}
  }
}

# Build dependency graph for a service
# Returns {nodes: list, edges: list}
export def build-dependency-graph [
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
  mut config_cache = {}
  
  # Create target node
  let version_name = $version_spec.name
  let node_key = (if ($platform | str length) > 0 {
    $"($service):($version_name):($platform)"
  } else {
    $"($service):($version_name)"
  })
  
  # Add target node to graph
  mut nodes = (add-node $nodes $node_key)
  
  # Cache target service config
  mut config_cache = ($config_cache | insert $node_key $merged_cfg)
  
  # Build graph recursively
  let result = (build-graph-recursive $service $version_name $platform $nodes $edges $visited $config_cache)
  
  {nodes: $result.nodes, edges: $result.edges}
}

# Topological sort using DFS (detects all cycles)
# Returns build order (list of node keys)
export def topological-sort-dfs [
  graph: record
] {
  # DFS helper (uses reduce to avoid for loop scope issues)
  def dfs [node: string, visited_ref: list, visiting_ref: list, finished_ref: list, cycles_ref: list] {
    # Check for cycle
    if $node in $visiting_ref {
      # Found a cycle - collect it
      let cycle_start_idx = ($visiting_ref | enumerate | where {|item| $item.item == $node} | first | get index)
      let cycle_nodes = ($visiting_ref | skip $cycle_start_idx | append $node)
      return {
        visited: $visited_ref,
        visiting: $visiting_ref,
        finished: $finished_ref,
        cycles: ($cycles_ref | append $cycle_nodes)
      }
    }
    
    # Check if already visited
    if $node in $visited_ref {
      return {
        visited: $visited_ref,
        visiting: $visiting_ref,
        finished: $finished_ref,
        cycles: $cycles_ref
      }
    }
    
    # Mark as visiting
    let visiting_new = ($visiting_ref | append $node)
    
    # Find dependencies (edges where node is "from")
    let deps = ($graph.edges | where {|edge| $edge.from == $node} | each {|edge| $edge.to})
    
    # Recursively visit each dependency using reduce (for loops don't work with mut variables)
    let deps_result = (if ($deps | length) > 0 {
      $deps | reduce --fold {
        visited: $visited_ref,
        visiting: $visiting_new,
        finished: $finished_ref,
        cycles: $cycles_ref
      } {|item, acc|
        dfs $item $acc.visited $acc.visiting $acc.finished $acc.cycles
      }
    } else {
      {
        visited: $visited_ref,
        visiting: $visiting_new,
        finished: $finished_ref,
        cycles: $cycles_ref
      }
    })
    
    # Mark as visited
    let visited_new = ($deps_result.visited | append $node)
    
    # Remove from visiting
    let visiting_final = ($deps_result.visiting | where {|item| $item != $node})
    
    # Append node to finished list AFTER dependencies (build order: dependencies first, then dependents)
    let finished_new = ($deps_result.finished | append $node)
    
    {
      visited: $visited_new,
      visiting: $visiting_final,
      finished: $finished_new,
      cycles: $deps_result.cycles
    }
  }
  
  # Run DFS from all nodes using reduce (for loops don't work with mut variables)
  let result = ($graph.nodes | reduce --fold {
    visited: [],
    visiting: [],
    finished: [],
    cycles: []
  } {|item, acc|
    if not ($item in $acc.visited) {
      dfs $item $acc.visited $acc.visiting $acc.finished $acc.cycles
    } else {
      $acc
    }
  })
  
  # Check if cycles detected
  if ($result.cycles | length) > 0 {
    let error_msg = ($result.cycles | reduce --fold "Circular dependencies detected:\n" {|item, acc|
      let cycle_str = ($item | str join " -> ")
      $acc + $"  ($cycle_str)\n"
    })
    error make { msg: $error_msg }
  }
  
  $result.finished
}
