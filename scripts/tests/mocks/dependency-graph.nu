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

use ../../lib/platforms/core.nu [
  strip-platform-suffix
  has-platform-suffix
]
use ../../lib/manifest/core.nu [get-version-or-null]
use ../../lib/build/dependencies.nu [apply-platform-inheritance]
use ./config-builders.nu [
  build-mock-version-manifest
  build-mock-platform-manifest
  get-mock-service-config
]
use ./deps-registry.nu [TEST_STATE_FILE init-mock-service-deps-registry]
use ./platform-registry.nu [
  check-platforms-manifest-exists
  check-versions-manifest-exists
]

def add-node [nodes: list, node: string] {
  if not ($node in $nodes) {
    $nodes | append $node
  } else {
    $nodes
  }
}

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
      build-mock-platform-manifest
    } catch {
      null
    }
  } else {
    null
  })

  let single_platform = (try {
    let val = ($dep_config.single_platform | default false)
    if $val == true { true } else { false }
  } catch { false })

  if ($explicit_version | str length) > 0 {
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

  if $node_key in $visited {
    return {nodes: $nodes, edges: $edges, visited: $visited, config_cache: $config_cache}
  }

  mut visited = ($visited | append $node_key)

  mut merged_cfg = null
  mut config_cache = $config_cache

  if $node_key in ($config_cache | columns) {
    $merged_cfg = ($config_cache | get $node_key)
  } else {
    if not (check-versions-manifest-exists $service) {
      error make { msg: $"Service '($service)' does not have a version manifest" }
    }

    let versions_manifest = (build-mock-version-manifest $version)
    let has_platforms = (check-platforms-manifest-exists $service)
    let platforms_manifest = (if $has_platforms {
      build-mock-platform-manifest
    } else {
      null
    })

    let base_version_name = (if $platforms_manifest != null {
      let stripped = (strip-platform-suffix $version $platforms_manifest)
      $stripped.base_name
    } else {
      $version
    })

    let version_spec = (get-version-or-null $versions_manifest $base_version_name)
    if $version_spec == null {
      error make { msg: $"Version '($base_version_name)' not found in manifest for service '($service)'" }
    }

    $merged_cfg = (get-mock-service-config $service $version_spec $platform $platforms_manifest)

    mut config_cache = ($config_cache | insert $node_key $merged_cfg)
  }

  let nodes = (add-node $nodes $node_key)

  let dependencies = (try { $merged_cfg.dependencies } catch { {} })

  if not ($dependencies | is-empty) {
    let parent_has_platforms = (check-platforms-manifest-exists $service)

    let result = ($dependencies | columns | reduce --fold {
      nodes: $nodes,
      edges: $edges,
      visited: $visited,
      config_cache: $config_cache
    } {|item, acc|
      let dep_key = $item
      let dep_config = ($dependencies | get $dep_key)

      let dep_service = (if "service" in ($dep_config | columns) {
        $dep_config.service
      } else {
        $dep_key
      })

      let dep_resolved = (resolve-dep-version-mock $dep_config $dep_service $version $platform $parent_has_platforms)

      let dep_node_key = (if ($dep_resolved.platform | str length) > 0 {
        $"($dep_service):($dep_resolved.version):($dep_resolved.platform)"
      } else {
        $"($dep_service):($dep_resolved.version)"
      })

      let new_nodes = (add-node $acc.nodes $dep_node_key)

      let new_edges = ($acc.edges | append {from: $node_key, to: $dep_node_key})

      build-graph-recursive-mock $dep_service $dep_resolved.version $dep_resolved.platform $new_nodes $new_edges $acc.visited $acc.config_cache
    })

    $result
  } else {
    {nodes: $nodes, edges: $edges, visited: $visited, config_cache: $config_cache}
  }
}

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

  init-mock-service-deps-registry
  let registry = (try {
    open $TEST_STATE_FILE
  } catch {
    {}
  })

  let config_cache = ($registry | columns | reduce --fold {} {|item, acc|
    let node_key = $item
    let parts = ($node_key | split row ":")
    let svc = ($parts | first)
    let ver = ($parts | last)
    let deps = ($registry | get $node_key)

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

  let version_name = $version_spec.name
  let node_key = (if ($platform | str length) > 0 {
    $"($service):($version_name):($platform)"
  } else {
    $"($service):($version_name)"
  })

  let config_cache = ($config_cache | upsert $node_key $merged_cfg)

  let result = (build-graph-recursive-mock $service $version_name $platform $nodes $edges $visited $config_cache)

  {
    nodes: $result.nodes,
    edges: $result.edges
  }
}
