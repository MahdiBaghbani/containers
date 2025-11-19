#!/usr/bin/env nu

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

# Test helper functions for setup, assertions, and cleanup

use ./mocks.nu [
  detect-build
  get-mock-service-config
  build-mock-version-manifest
  build-mock-platform-manifest
  check-platforms-manifest-exists
  set-mock-platform-behavior
  clear-mock-platform-registry
]
use ../lib/manifest.nu [get-version-or-null]

# Setup Functions

export def setup-test-environment [
  service: string = "test-service",
  version_name: string = "v1.0.0",
  has_platforms: bool = true,
  custom_version_overrides: record = {},
  custom_platforms: list = []
] {
  # Set mock platform behavior
  set-mock-platform-behavior $service $has_platforms
  
  # Build version manifest with custom overrides
  let version_list = (if ($custom_version_overrides | is-empty) {
    [{
      name: $version_name,
      latest: true,
      tags: [],
      overrides: {}
    }]
  } else {
    [{
      name: $version_name,
      latest: true,
      tags: [],
      overrides: $custom_version_overrides
    }]
  })
  let version_manifest = (build-mock-version-manifest $version_name $version_list)
  
  # Get version spec
  let version_spec = (get-version-or-null $version_manifest $version_name)
  if $version_spec == null {
    error make { msg: $"Version '($version_name)' not found in mock manifest" }
  }
  
  # Build platform manifest if has_platforms
  let platforms = (if $has_platforms {
    if ($custom_platforms | length) > 0 {
      build-mock-platform-manifest "debian" $custom_platforms
    } else {
      build-mock-platform-manifest
    }
  } else {
    null
  })
  
  # Get merged config
  let platform = (if $platforms != null {
    try { $platforms.default } catch { "" }
  } else {
    ""
  })
  let merged_cfg = (get-mock-service-config $service $version_spec $platform $platforms)
  
  # Get meta
  let meta = (detect-build)
  
  # Create default deps_resolved
  let deps_resolved = {}
  
  # Create default tls_meta
  let tls_meta = {
    enabled: false,
    mode: "disabled",
    cert_name: "",
    ca_name: ""
  }
  
  # Create default registry_info
  let registry_info = {
    registry: "",
    namespace: "",
    is_local: true
  }
  
  {
    service: $service,
    version_spec: $version_spec,
    version_manifest: $version_manifest,
    platforms: $platforms,
    merged_cfg: $merged_cfg,
    meta: $meta,
    deps_resolved: $deps_resolved,
    tls_meta: $tls_meta,
    registry_info: $registry_info
  }
}

export def setup-test-service-with-deps [
  service: string,
  dependencies: record,
  version_name: string = "v1.0.0"
] {
  # Call setup-test-environment for base service
  mut test_env = (setup-test-environment $service $version_name)
  
  # Add dependencies to merged_cfg.dependencies
  mut merged_cfg = $test_env.merged_cfg
  if "dependencies" in ($merged_cfg | columns) {
    $merged_cfg = ($merged_cfg | upsert dependencies ($merged_cfg.dependencies | merge $dependencies))
  } else {
    $merged_cfg = ($merged_cfg | insert dependencies $dependencies)
  }
  
  # Update test_env with modified merged_cfg
  $test_env = ($test_env | upsert merged_cfg $merged_cfg)
  
  # Register this service's config with dependencies so graph construction can find them
  use ./mocks.nu [register-mock-service-dependencies]
  register-mock-service-dependencies $service $version_name $dependencies
  
  $test_env
}

export def create-test-version-spec [
  version_name: string = "v1.0.0",
  latest: bool = true,
  tags: list = [],
  overrides: record = {}
] {
  {
    name: $version_name,
    latest: $latest,
    tags: $tags,
    overrides: $overrides
  }
}

export def create-test-dependency [
  service: string,
  version: string = "",
  build_arg: string = ""
] {
  mut dep = {service: $service}
  if ($version | str length) > 0 {
    $dep = ($dep | upsert version $version)
  }
  if ($build_arg | str length) > 0 {
    $dep = ($dep | upsert build_arg $build_arg)
  }
  $dep
}

export def create-test-deps-resolved [dependencies: record = {}] {
  $dependencies
}

export def create-test-tls-meta [
  enabled: bool = false,
  mode: string = "disabled",
  cert_name: string = "",
  ca_name: string = ""
] {
  {
    enabled: $enabled,
    mode: $mode,
    cert_name: $cert_name,
    ca_name: $ca_name
  }
}

export def create-test-registry-info [
  registry: string = "",
  namespace: string = "",
  is_local: bool = true
] {
  {
    registry: $registry,
    namespace: $namespace,
    is_local: $is_local
  }
}

# Assertion Functions

export def assert-cache-bust-format [
  cache_bust: string,
  expected_length: int,
  expected_format: string = "hash"
] {
  # Validate length
  let actual_length = ($cache_bust | str length)
  if $actual_length != $expected_length {
    error make { msg: $"Cache bust length mismatch: expected ($expected_length), got ($actual_length): ($cache_bust)" }
  }
  
  # Validate format
  if $expected_format == "uuid" {
    if not ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected UUID format with dashes, got: ($cache_bust)" }
    }
  } else if $expected_format == "hash" {
    # Hash format: alphanumeric, no dashes
    if ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected hash format (no dashes), got: ($cache_bust)" }
    }
  } else if $expected_format == "sha" {
    # SHA format: alphanumeric, variable length
    if ($cache_bust | str contains "-") {
      error make { msg: $"Cache bust format mismatch: expected SHA format (no dashes), got: ($cache_bust)" }
    }
  }
  # "any" format: no validation
  true
}

export def assert-cache-bust-value [
  cache_bust: string,
  expected_value: string
] {
  if $cache_bust != $expected_value {
    error make { msg: $"Cache bust value mismatch: expected '($expected_value)', got '($cache_bust)'" }
  }
  true
}

export def assert-build-args-contain [
  build_args: record,
  expected_fields: list
] {
  for field in $expected_fields {
    if not ($field in ($build_args | columns)) {
      error make { msg: $"Build args missing required field: ($field)" }
    }
  }
  true
}

export def assert-build-order [
  build_order: list,
  expected_order: list
] {
  if ($build_order | length) != ($expected_order | length) {
    error make { msg: $"Build order length mismatch: expected ($expected_order | length), got ($build_order | length)" }
  }
  
  for $i in 0..<($expected_order | length) {
    let expected = ($expected_order | get $i)
    let actual = ($build_order | get $i)
    if $actual != $expected {
      error make { msg: $"Build order mismatch at index ($i): expected '($expected)', got '($actual)'" }
    }
  }
  true
}

export def assert-graph-structure [
  graph: record,
  expected_nodes: list,
  expected_edges: list
] {
  # Validate nodes
  let actual_nodes = $graph.nodes
  if ($actual_nodes | length) != ($expected_nodes | length) {
    error make { msg: $"Graph nodes count mismatch: expected ($expected_nodes | length), got ($actual_nodes | length)" }
  }
  
  for expected_node in $expected_nodes {
    if not ($expected_node in $actual_nodes) {
      error make { msg: $"Graph missing expected node: ($expected_node)" }
    }
  }
  
  # Validate edges
  let actual_edges = $graph.edges
  if ($actual_edges | length) != ($expected_edges | length) {
    error make { msg: $"Graph edges count mismatch: expected ($expected_edges | length), got ($actual_edges | length)" }
  }
  
  for expected_edge in $expected_edges {
    let found = ($actual_edges | any {|edge| ($edge.from == $expected_edge.from) and ($edge.to == $expected_edge.to)})
    if not $found {
      error make { msg: $"Graph missing expected edge: from '($expected_edge.from)' to '($expected_edge.to)'" }
    }
  }
  true
}

# Cleanup Functions

export def cleanup-test-environment [] {
  use ./mocks.nu [clear-mock-platform-registry clear-mock-service-deps-registry]
  clear-mock-platform-registry
  clear-mock-service-deps-registry
  
  # Reinitialize temp state file from scratch
  try {
    rm -f .tmp/test-state-registry.json
    mkdir .tmp
    {} | to json | save -f .tmp/test-state-registry.json
  } catch {
    # If cleanup fails, at least try to reset the registry
    if (".tmp/test-state-registry.json" | path exists) {
      {} | to json | save -f .tmp/test-state-registry.json
    }
  }
  
  true
}

# Test wrapper that guarantees cleanup runs even on failure
export def with-test-cleanup [test_block: closure] {
  let result = (try {
    do $test_block
  } catch {|err|
    # Always cleanup on failure
    cleanup-test-environment | ignore
    error make {msg: $err.msg}
  })
  
  # Always cleanup on success
  cleanup-test-environment | ignore
  
  # Return the test result
  $result
}
