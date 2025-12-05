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

# Build orchestration - high-level build coordination
# See docs/concepts/build-system.md for architecture

use ./config.nu [
  validate-all-services-flags
  validate-service-required
  load-service-manifests
  validate-platform-flag
  require-versions-manifest
  has-multi-version-flags
  is-metadata-only-mode
  load-service-config
]
use ./disk.nu [record-disk-usage prune-build-cache]
use ./matrix.nu [generate-service-matrix generate-multi-service-matrix]
use ./version.nu [build-single-version print-build-summary resolve-dependency-version-spec]
use ./order.nu [build-dependency-graph topological-sort-dfs show-build-order-for-version compute-single-service-build-order]
use ./hash.nu [compute-service-def-hash-graph]
use ./pull.nu [run-pulls print-pull-summary compute-canonical-image-ref]
use ./docker.nu [get-service-def-hash-from-image]
use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest filter-versions get-version-or-null resolve-version-name get-version-spec apply-version-defaults get-default-version]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform get-platform-names expand-version-to-platforms strip-platform-suffix]
use ../services/core.nu [list-service-names]
use ../registries/info.nu [get-registry-info]

# Main build orchestration entrypoint
# Routes to appropriate build path based on flags
export def run-build [ctx: record] {
  let f = $ctx.flags
  let meta = $ctx.meta
  let info = $ctx.registry_info
  
  # Route based on --all-services flag
  if $f.all_services {
    validate-all-services-flags $f.service $f.version $f.versions
    run-all-services-build $ctx
  } else {
    validate-service-required $f.service
    run-single-service-build $ctx
  }
}

# Build all services in dependency order
def run-all-services-build [ctx: record] {
  let f = $ctx.flags
  let meta = $ctx.meta
  let info = $ctx.registry_info
  mut sha_cache = {}
  
  # Disk monitoring: pre phase (skip for metadata-only modes)
  if $f.disk_monitor != "off" and not (is-metadata-only-mode $f.show_build_order $f.matrix_json) {
    try { 
      record-disk-usage "all-services" "pre" $f.disk_monitor 
    } catch {|err| 
      print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" 
    }
  }
  
  # Discover all services
  let all_service_names = (list-service-names)
  
  if ($all_service_names | is-empty) {
    print "No services found."
    return
  }
  
  # Handle matrix JSON generation
  if $f.matrix_json {
    let services_with_manifests = ($all_service_names | where {|svc|
      check-versions-manifest-exists $svc
    })
    
    if ($services_with_manifests | is-empty) {
      print "No services with version manifests found."
      return
    }
    
    let full_matrix = (generate-multi-service-matrix $services_with_manifests)
    
    mut filtered_entries = $full_matrix.include
    
    if $f.latest_only {
      $filtered_entries = ($filtered_entries | where {|entry|
        (try { $entry.latest } catch { false }) == true
      })
    } else if not $f.all_versions {
      mut default_entries = []
      for service_name in $services_with_manifests {
        let manifest = (load-versions-manifest $service_name)
        let default_version_name = (get-default-version $manifest)
        let service_defaults = ($filtered_entries | where {|entry|
          $entry.service == $service_name and $entry.version == $default_version_name
        })
        $default_entries = ($default_entries | append $service_defaults)
      }
      $filtered_entries = $default_entries
    }
    
    if ($f.platform | str length) > 0 {
      $filtered_entries = ($filtered_entries | where {|entry|
        $entry.platform == $f.platform
      })
    }
    
    let filtered_matrix = {include: $filtered_entries}
    print ($filtered_matrix | to json)
    return
  }
  
  print $"=== Building All Services ==="
  let service_count = ($all_service_names | length | into string)
  print $"Found ($service_count) service\(s\)"
  print ""
  
  # Resolve versions and platforms for each service
  let service_builds = ($all_service_names | reduce --fold [] {|item, acc|
    let service_name = $item
    
    if not (check-versions-manifest-exists $service_name) {
      print $"WARNING: Service '($service_name)' has no versions manifest. Skipping."
      $acc
    } else {
      let versions_manifest = (load-versions-manifest $service_name)
      let has_platforms = (check-platforms-manifest-exists $service_name)
      let platforms_manifest = (if $has_platforms {
        try {
          load-platforms-manifest $service_name
        } catch {
          null
        }
      } else {
        null
      })
      
      let versions_to_build = (if $f.all_versions {
        $versions_manifest.versions | each {|v| apply-version-defaults $versions_manifest $v}
      } else if $f.latest_only {
        $versions_manifest.versions | where {|v| try { $v.latest == true } catch { false }} | each {|v| apply-version-defaults $versions_manifest $v}
      } else {
        let default_version_name = (get-default-version $versions_manifest)
        let default_version_spec = (get-version-spec $versions_manifest $default_version_name)
        [$default_version_spec]
      })
      
      if ($versions_to_build | is-empty) {
        print $"WARNING: No versions to build for service '($service_name)'. Skipping."
        $acc
      } else {
        if $has_platforms and $platforms_manifest != null {
          let default_platform = (get-default-platform $platforms_manifest)
          
          let expanded = ($versions_to_build | reduce --fold [] {|ver_item, ver_acc|
            let platform_variants = (expand-version-to-platforms $ver_item $platforms_manifest $default_platform)
            $ver_acc | append $platform_variants
          })
          
          let filtered_expanded = (if ($f.platform | str length) > 0 {
            $expanded | where {|v| $v.platform == $f.platform}
          } else {
            $expanded
          })
          
          if ($filtered_expanded | is-empty) {
            print $"WARNING: No platform variants to build for service '($service_name)'. Skipping."
            $acc
          } else {
            $filtered_expanded | reduce --fold $acc {|exp_item, exp_acc|
              $exp_acc | append {
                service: $service_name,
                version_spec: $exp_item,
                platform: $exp_item.platform,
                platforms_manifest: $platforms_manifest,
                default_platform: $default_platform
              }
            }
          }
        } else {
          if ($f.platform | str length) > 0 {
            print $"WARNING: Service '($service_name)' has no platforms manifest but --platform specified. Skipping."
            $acc
          } else {
            $versions_to_build | reduce --fold $acc {|ver_item, ver_acc|
              $ver_acc | append {
                service: $service_name,
                version_spec: $ver_item,
                platform: "",
                platforms_manifest: null,
                default_platform: ""
              }
            }
          }
        }
      }
    }
  })
  
  if ($service_builds | is-empty) {
    print "No services to build after filtering."
    return
  }
  
  # Build dependency graph for each service:version:platform and merge
  let graph_result = ($service_builds | reduce --fold {nodes: [], edges: []} {|item, acc|
    let service = $item.service
    let version_spec = $item.version_spec
    let plat = $item.platform
    let platforms_manifest = $item.platforms_manifest
    
    let graph = (if $f.show_build_order {
      try {
        let cfg = (load-service-config $service $version_spec $plat $platforms_manifest)
        build-dependency-graph $service $version_spec $cfg $plat $platforms_manifest false $info
      } catch {|err|
        print $"WARNING: Could not build dependency graph for ($service):($version_spec.name): ($err.msg)"
        {nodes: [], edges: []}
      }
    } else {
      let cfg = (load-service-config $service $version_spec $plat $platforms_manifest)
      build-dependency-graph $service $version_spec $cfg $plat $platforms_manifest false $info
    })
    
    let merged_nodes = ($graph.nodes | reduce --fold $acc.nodes {|node_item, node_acc|
      if not ($node_item in $node_acc) {
        $node_acc | append $node_item
      } else {
        $node_acc
      }
    })
    
    let merged_edges = ($graph.edges | reduce --fold $acc.edges {|edge_item, edge_acc|
      let edge_exists = ($edge_acc | any {|e|
        $e.from == $edge_item.from and $e.to == $edge_item.to
      })
      if not $edge_exists {
        $edge_acc | append $edge_item
      } else {
        $edge_acc
      }
    })
    
    let service_node = (if ($plat | str length) > 0 {
      $"($service):($version_spec.name):($plat)"
    } else {
      $"($service):($version_spec.name)"
    })
    
    let final_nodes = (if not ($service_node in $merged_nodes) {
      $merged_nodes | append $service_node
    } else {
      $merged_nodes
    })
    
    {nodes: $final_nodes, edges: $merged_edges}
  })
  
  let merged_graph = {
    nodes: $graph_result.nodes,
    edges: $graph_result.edges
  }
  
  # Handle --show-build-order
  if $f.show_build_order {
    let build_order = (topological-sort-dfs $merged_graph)
    
    print "=== Build Order (All Services) ==="
    print ""
    for $idx in 0..<($build_order | length) {
      let node = ($build_order | get $idx)
      let label = ($idx + 1 | into string)
      print $"($label). ($node)"
    }
    return
  }
  
  # Perform topological sort on merged graph
  let build_order = (topological-sort-dfs $merged_graph)
  
  print $"=== Build Order ==="
  print ""
  for $idx in 0..<($build_order | length) {
    let node = ($build_order | get $idx)
    let label = ($idx + 1 | into string)
    print $"($label). ($node)"
  }
  print ""
  
  # Compute service definition hash graph
  let hash_graph = (compute-service-def-hash-graph $build_order $info $sha_cache)
  
  # Pre-pull images if --pull flag is provided
  if not ($f.pull | is-empty) {
    let pull_metrics = (run-pulls $f.pull $build_order $info $meta.is_local)
    print-pull-summary $pull_metrics
    print ""
  }
  
  # Execute builds in topological order
  let build_result = ($build_order | reduce --fold {built_nodes: [], successes: [], failures: [], skipped: [], cache: $sha_cache} {|item, acc|
    let node = $item
    
    if $node in $acc.built_nodes {
      $acc
    } else {
      let parts = ($node | split row ":")
      if ($parts | length) < 2 {
        let failure_record = {
          label: $node,
          success: false,
          error: "Invalid node format"
        }
        {
          built_nodes: $acc.built_nodes,
          successes: $acc.successes,
          failures: ($acc.failures | append $failure_record),
          skipped: $acc.skipped,
          cache: $acc.cache
        }
      } else {
        let node_service = ($parts | get 0)
        let node_version = ($parts | get 1)
        let node_platform = (if ($parts | length) > 2 { $parts | get 2 } else { "" })
        
        let is_target_service = ($service_builds | any {|svc_item|
          let item_node = (if ($svc_item.platform | str length) > 0 {
            $"($svc_item.service):($svc_item.version_spec.name):($svc_item.platform)"
          } else {
            $"($svc_item.service):($svc_item.version_spec.name)"
          })
          $item_node == $node
        })
        
        let node_version_spec = (resolve-dependency-version-spec $node $node_platform)
        
        let node_has_platforms = (check-platforms-manifest-exists $node_service)
        let node_platforms_manifest = (if $node_has_platforms {
          try {
            load-platforms-manifest $node_service
          } catch {
            null
          }
        } else {
          null
        })
        
        let node_default_platform = (if $node_has_platforms and $node_platforms_manifest != null {
          get-default-platform $node_platforms_manifest
        } else {
          ""
        })
        
        let node_push = (if $is_target_service { $f.push } else { $f.push_deps })
        let node_latest = (if $is_target_service {
          $f.latest
        } else {
          if $f.tag_deps { $f.latest } else { false }
        })
        let node_extra_tag = (if $is_target_service {
          $f.extra_tag
        } else {
          if $f.tag_deps { $f.extra_tag } else { "" }
        })
        
        let node_info = (get-registry-info)
        let node_meta = $meta
        
        let build_label = (if ($node_platform | str length) > 0 {
          $"($node_service):($node_version_spec.name)-($node_platform)"
        } else {
          $"($node_service):($node_version_spec.name)"
        })
        
        print $"\n--- Building ($build_label) ---"
        
        let build_result = (try {
          build-single-version $node_service $node_version_spec $node_push $node_latest $node_extra_tag $f.provenance $f.progress $node_info $node_meta $acc.cache $node_platform $node_default_platform $node_platforms_manifest $f.cache_bust $f.no_cache "strict" $f.push_deps $f.tag_deps $hash_graph $f.cache_match
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          error make { msg: $error_msg }
        })
        let result = {success: true, label: $build_label}
        print $"OK: Successfully built ($build_label)"
        
        let new_built_nodes = ($acc.built_nodes | append $node)
        
        if $result.success {
          {
            built_nodes: $new_built_nodes,
            successes: ($acc.successes | append {label: $result.label, success: true}),
            failures: $acc.failures,
            skipped: $acc.skipped,
            cache: (try { $build_result.sha_cache } catch { $acc.cache })
          }
        } else {
          let dependents = ($merged_graph.edges | where {|e| $e.from == $node} | each {|e| $e.to})
          let new_skipped = ($dependents | reduce --fold $acc.skipped {|dep_item, skip_acc|
            if not ($dep_item in $new_built_nodes) {
              $skip_acc | append {
                label: $dep_item,
                reason: $"Dependency failed: ($build_label)"
              }
            } else {
              $skip_acc
            }
          })
          
          let final_built_nodes = ($dependents | reduce --fold $new_built_nodes {|dep_item, built_acc|
            if not ($dep_item in $built_acc) {
              $built_acc | append $dep_item
            } else {
              $built_acc
            }
          })
          
          {
            built_nodes: $final_built_nodes,
            successes: $acc.successes,
            failures: ($acc.failures | append {label: $result.label, success: false, error: $result.error}),
            skipped: $new_skipped,
            cache: $acc.cache
          }
        }
      }
    }
  })
  
  print-build-summary $build_result.successes $build_result.failures $build_result.skipped
  
  # Disk monitoring: post-build phase (skip for metadata-only modes)
  if $f.disk_monitor != "off" and not (is-metadata-only-mode $f.show_build_order $f.matrix_json) {
    try { 
      record-disk-usage "all-services" "post-build" $f.disk_monitor 
    } catch {|err| 
      print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" 
    }
  }
  
  if ($build_result.failures | length) > 0 {
    exit 1
  }
}

# Build a single service
def run-single-service-build [ctx: record] {
  let f = $ctx.flags
  let info = $ctx.registry_info
  let meta = $ctx.meta
  mut sha_cache = {}
  
  # Load service manifests
  let manifests = (load-service-manifests $f.service)
  
  # Validate platform if specified
  validate-platform-flag $f.platform $f.service $manifests.has_platforms $manifests.platforms_manifest
  
  # Handle matrix JSON mode
  if $f.matrix_json {
    require-versions-manifest $f.service $manifests.has_versions "generate matrix"
    let matrix = (generate-service-matrix $f.service)
    print ($matrix | to json)
    return
  }
  
  # Disk monitoring: pre phase (skip for metadata-only modes)
  if $f.disk_monitor != "off" and not (is-metadata-only-mode $f.show_build_order $f.matrix_json) {
    try { 
      record-disk-usage $f.service "pre" $f.disk_monitor 
    } catch {|err| 
      print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" 
    }
  }
  
  let has_versions_manifest = $manifests.has_versions
  let versions_manifest = $manifests.versions_manifest
  let has_platforms_manifest = $manifests.has_platforms
  let platforms_manifest = $manifests.platforms_manifest
  let default_platform = (if $has_platforms_manifest { get-default-platform $platforms_manifest } else { "" })
  
  # Validate platform suffix in version for non-platform services
  if not $has_platforms_manifest and ($f.version | str length) > 0 {
    if ($f.version | str contains "-") {
      let parts = ($f.version | split row "-")
      if ($parts | length) > 1 {
        let potential_platform = ($parts | last)
        if ($potential_platform =~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
          error make { 
            msg: ($"Version '($f.version)' contains platform suffix '-($potential_platform)' but service '($f.service)' has no platforms manifest.\n\n" +
                  "Platform suffixes are only valid for multi-platform services.\n" +
                  "Options:\n" +
                  "1. Remove the platform suffix: --version ($parts | drop | str join "-")\n" +
                  "2. Create a platforms manifest: services/($f.service)/platforms.nuon\n" +
                  "3. If this is a valid version name (not a platform suffix), use it as-is in your versions.nuon manifest")
          }
        }
      }
    }
  }
  
  # Handle version suffix detection for platform services
  mut version_suffix_info = null
  if $has_platforms_manifest and ($f.version | str length) > 0 {
    let stripped = (try {
      strip-platform-suffix $f.version $platforms_manifest
    } catch {|err|
      error make { msg: $"Invalid version format '($f.version)': ($err.msg)" }
    })
    
    if ($stripped.platform_name | str length) > 0 {
      $version_suffix_info = $stripped
      
      let platform_names = (get-platform-names $platforms_manifest)
      if not ($stripped.platform_name in $platform_names) {
        let available = ($platform_names | str join ", ")
        error make { msg: $"Version suffix platform '($stripped.platform_name)' not found in platforms manifest. Available: ($available)" }
      }
      
      if ($f.platform | str length) > 0 and $f.platform != $stripped.platform_name {
        error make { msg: $"Version suffix '($stripped.platform_name)' conflicts with --platform '($f.platform)'" }
      }
    }
  }
  
  # Handle --show-build-order
  if $f.show_build_order {
    require-versions-manifest $f.service $has_versions_manifest "show build order"
    
    let has_mv_flags = (has-multi-version-flags $f.all_versions $f.versions $f.latest_only)
    
    if not $has_mv_flags {
      # Single-version path
      let version_resolved = (resolve-version-name $f.version $versions_manifest $platforms_manifest $version_suffix_info)
      let version_spec = (get-version-or-null $versions_manifest $version_resolved.base_name)
      
      if $version_spec == null {
        let available_versions = (try {
          $versions_manifest.versions | each {|v| $v.name} | str join ", "
        } catch {
          "unknown"
        })
        error make { 
          msg: ($"Version '($version_resolved.base_name)' not found in manifest for service '($f.service)'.\n\n" +
                $"Available versions: ($available_versions)")
        }
      }
      
      let target_platform = (if ($f.platform | str length) > 0 {
        $f.platform
      } else if ($version_resolved.detected_platform | str length) > 0 {
        $version_resolved.detected_platform
      } else if $has_platforms_manifest {
        $default_platform
      } else {
        ""
      })
      
      print "=== Build Order ==="
      print ""
      show-build-order-for-version $f.service $version_spec $target_platform $platforms_manifest $info {}
      return
    }
    
    # Multi-version path
    let filter_result = (filter-versions $versions_manifest $platforms_manifest --all=$f.all_versions --versions=$f.versions --latest-only=$f.latest_only)
    let versions_to_build = ($filter_result.versions | each {|v| apply-version-defaults $versions_manifest $v})
    let detected_platforms_from_filter = $filter_result.detected_platforms
    
    if ($versions_to_build | is-empty) {
      print "No versions to build based on filter criteria."
      return
    }
    
    mut expanded_versions = []
    if $has_platforms_manifest {
      for version_spec in $versions_to_build {
        $expanded_versions = ($expanded_versions | append (expand-version-to-platforms $version_spec $platforms_manifest $default_platform))
      }
      
      $expanded_versions = ($expanded_versions | where {|item|
        ($f.platform | str length) == 0 or $item.platform == $f.platform
      } | where {|item|
        ($detected_platforms_from_filter | is-empty) or ($item.platform in $detected_platforms_from_filter)
      })
      
      if ($expanded_versions | is-empty) {
        print "No versions to build after platform filtering."
        return
      }
    } else {
      $expanded_versions = $versions_to_build
    }
    
    print "=== Build Order ==="
    print ""
    
    mut graph_cache = {}
    
    for $idx in 0..<($expanded_versions | length) {
      let expanded_version = ($expanded_versions | get $idx)
      let version_platform = (try { $expanded_version.platform } catch { "" })
      
      let version_label = (if $has_platforms_manifest and ($version_platform | str length) > 0 {
        $"Version: ($expanded_version.name) (($version_platform))"
      } else {
        $"Version: ($expanded_version.name)"
      })
      
      print $version_label
      
      try {
        let result = (show-build-order-for-version $f.service $expanded_version $version_platform $platforms_manifest $info $graph_cache)
        $graph_cache = $result.cache
      } catch {|err|
        let error_msg = (try { $err.msg } catch { "Unknown error" })
        print $"ERROR: Could not determine build order: ($error_msg)"
      }
      
      if $idx < (($expanded_versions | length) - 1) {
        print ""
      }
    }
    return
  }
  
  # Validate --versions flag for non-platform services
  if not $has_platforms_manifest and ($f.versions | str length) > 0 {
    for v in ($f.versions | split row "," | each {|x| $x | str trim} | where ($it | str length) > 0) {
      if ($v | str contains "-") {
        let parts = ($v | split row "-")
        if ($parts | length) > 1 {
          let potential_platform = ($parts | last)
          if ($potential_platform =~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            error make { 
              msg: ($"Version '($v)' in --versions flag contains platform suffix '-($potential_platform)' but service '($f.service)' has no platforms manifest.\n\n" +
                    "Platform suffixes are only valid for multi-platform services.\n" +
                    "Options:\n" +
                    "1. Remove the platform suffix: --versions ($parts | drop | str join "-")\n" +
                    "2. Create a platforms manifest: services/($f.service)/platforms.nuon\n" +
                    "3. If this is a valid version name (not a platform suffix), use it as-is in your versions.nuon manifest")
            }
          }
        }
      }
    }
  }
  
  # Detect platforms from --versions flag
  mut detected_platforms_from_versions = []
  if $has_platforms_manifest and ($f.versions | str length) > 0 {
    for v in ($f.versions | split row "," | each {|x| $x | str trim} | where ($it | str length) > 0) {
      let stripped = (try {
        strip-platform-suffix $v $platforms_manifest
    } catch {|err| 
        error make { msg: $"Invalid version format '($v)': ($err.msg)" }
      })
      
      if ($stripped.platform_name | str length) > 0 {
        if not ($stripped.platform_name in $detected_platforms_from_versions) {
          $detected_platforms_from_versions = ($detected_platforms_from_versions | append $stripped.platform_name)
        }
        
        let platform_names = (get-platform-names $platforms_manifest)
        if not ($stripped.platform_name in $platform_names) {
          let available = ($platform_names | str join ", ")
          error make { msg: $"Version suffix platform '($stripped.platform_name)' not found in platforms manifest. Available: ($available)" }
        }
      }
    }
    
    if not ($detected_platforms_from_versions | is-empty) and ($f.platform | str length) > 0 {
      if not ($f.platform in $detected_platforms_from_versions) {
        let detected = ($detected_platforms_from_versions | str join ", ")
        error make { msg: $"--platform '($f.platform)' conflicts with detected platforms from --versions: ($detected)" }
      }
    }
  }
  
  # Multi-version build mode
  if $f.all_versions or ($f.versions | str length) > 0 or $f.latest_only {
    require-versions-manifest $f.service $has_versions_manifest "build multiple versions"
    
    let filter_result = (filter-versions $versions_manifest $platforms_manifest --all=$f.all_versions --versions=$f.versions --latest-only=$f.latest_only)
    let versions_to_build = ($filter_result.versions | each {|v| apply-version-defaults $versions_manifest $v})
    let detected_platforms_from_filter = $filter_result.detected_platforms
    
    if ($versions_to_build | is-empty) {
      print "No versions to build based on filter criteria."
      return
    }
    
    if $has_platforms_manifest {
      mut expanded_versions = []
      for version_spec in $versions_to_build {
        $expanded_versions = ($expanded_versions | append (expand-version-to-platforms $version_spec $platforms_manifest $default_platform))
      }
      
      $expanded_versions = ($expanded_versions | where {|item|
        ($f.platform | str length) == 0 or $item.platform == $f.platform
      } | where {|item|
        ($detected_platforms_from_filter | is-empty) or ($item.platform in $detected_platforms_from_filter)
      })
      
      if ($expanded_versions | is-empty) {
        print "No versions to build after platform filtering."
        return
      }
      
      let build_order = (compute-single-service-build-order $f.service $expanded_versions $platforms_manifest $info)
      let hash_graph = (compute-service-def-hash-graph $build_order $info $sha_cache)
      
      if not ($f.pull | is-empty) {
        let pull_metrics = (run-pulls $f.pull $build_order $info $meta.is_local)
        print-pull-summary $pull_metrics
        print ""
      }
      
      if $f.disk_monitor != "off" {
        try { record-disk-usage $f.service "after-deps" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
      }
      
      print $"\n=== Building ($expanded_versions | length) version\(s\) of ($f.service) ==="
      print ""
      
      mut successes = []
      mut failures = []
      mut skipped = []
      
      for expanded_version in $expanded_versions {
        let build_label = $"($f.service):($expanded_version.name)-($expanded_version.platform)"
        print $"\n--- Building ($build_label) ---"
        
        let prev_cache = $sha_cache
        let result = (try {
          let build_result = (build-single-version $f.service $expanded_version $f.push $f.latest $f.extra_tag $f.provenance $f.progress $info $meta $sha_cache $expanded_version.platform $default_platform $platforms_manifest $f.cache_bust $f.no_cache $f.dep_cache $f.push_deps $f.tag_deps $hash_graph $f.cache_match)
          $sha_cache = (try { $build_result.sha_cache } catch { $prev_cache })
          print $"OK: Successfully built ($build_label)"
          {success: true, label: $build_label}
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          {success: false, label: $build_label, error: $error_msg}
        })
        
        if $f.disk_monitor != "off" {
          try { record-disk-usage $build_label "after-version" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
        }
        
        if $f.prune_cache_mounts {
          try { prune-build-cache $build_label } catch {|err| print $"WARNING: Cache prune failed: (try { $err.msg } catch { 'Unknown error' })" }
        }
        
        if $result.success {
          $successes = ($successes | append {label: $result.label, success: true})
        } else {
          $failures = ($failures | append {label: $result.label, success: false, error: $result.error})
          
          if $f.fail_fast {
            break
          }
        }
      }
      
      print-build-summary $successes $failures $skipped
      
      if $f.disk_monitor != "off" {
        try { record-disk-usage $f.service "post-build" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
      }
      
      if ($failures | length) > 0 {
        exit 1
      }
      
      return
    } else {
      # Single-platform multi-version
      let build_order = (compute-single-service-build-order $f.service $versions_to_build null $info)
      let hash_graph = (compute-service-def-hash-graph $build_order $info $sha_cache)
      
      if not ($f.pull | is-empty) {
        let pull_metrics = (run-pulls $f.pull $build_order $info $meta.is_local)
        print-pull-summary $pull_metrics
        print ""
      }
      
      if $f.disk_monitor != "off" {
        try { record-disk-usage $f.service "after-deps" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
      }
      
      print $"\n=== Building ($versions_to_build | length) version\(s\) of ($f.service) ==="
      print ""
      
      mut successes = []
      mut failures = []
      mut skipped = []
      
      for version_spec in $versions_to_build {
        let build_label = $"($f.service):($version_spec.name)"
        print $"\n--- Building ($build_label) ---"
        
        let prev_cache = $sha_cache
        let result = (try {
          let build_result = (build-single-version $f.service $version_spec $f.push $f.latest $f.extra_tag $f.provenance $f.progress $info $meta $sha_cache "" "" null $f.cache_bust $f.no_cache $f.dep_cache $f.push_deps $f.tag_deps $hash_graph $f.cache_match)
          $sha_cache = (try { $build_result.sha_cache } catch { $prev_cache })
          print $"OK: Successfully built ($build_label)"
          {success: true, label: $build_label}
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          {success: false, label: $build_label, error: $error_msg}
        })
        
        if $f.disk_monitor != "off" {
          try { record-disk-usage $build_label "after-version" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
        }
        
        if $f.prune_cache_mounts {
          try { prune-build-cache $build_label } catch {|err| print $"WARNING: Cache prune failed: (try { $err.msg } catch { 'Unknown error' })" }
        }
        
        if $result.success {
          $successes = ($successes | append {label: $result.label, success: true})
        } else {
          $failures = ($failures | append {label: $result.label, success: false, error: $result.error})
          
          if $f.fail_fast {
            break
          }
        }
      }
      
      print-build-summary $successes $failures $skipped
      
      if ($failures | length) > 0 {
        exit 1
      }
      
      return
    }
  }
  
  # Single-version build
  require-versions-manifest $f.service $has_versions_manifest "build"
  
  let version_resolved = (resolve-version-name $f.version $versions_manifest $platforms_manifest $version_suffix_info)
  let version_spec = (get-version-or-null $versions_manifest $version_resolved.base_name)
  
  if $version_spec == null {
    let available_versions = (try {
      $versions_manifest.versions | each {|v| $v.name} | str join ", "
    } catch {
      "unknown"
    })
    let first_version = (try {
      $available_versions | split row ", " | first
    } catch {
      "unknown"
    })
    error make { 
      msg: ($"Version '($version_resolved.base_name)' not found in manifest for service '($f.service)'.\n\n" +
            $"Available versions: ($available_versions)\n" +
            "Options:\n" +
            $"1. Use one of the available versions: --version ($first_version)\n" +
            $"2. Add the version to services/($f.service)/versions.nuon\n" +
            "3. Check for typos in the version name")
    }
  }
  
  # Platform expansion if platforms manifest exists
  if $has_platforms_manifest {
    mut expanded_versions = (expand-version-to-platforms $version_spec $platforms_manifest $default_platform)
    
    $expanded_versions = ($expanded_versions | where {|item|
      ($f.platform | str length) == 0 or $item.platform == $f.platform
    } | where {|item|
      ($version_resolved.detected_platform | str length) == 0 or $item.platform == $version_resolved.detected_platform
    })
    
    if ($expanded_versions | is-empty) {
      print "No versions to build after platform filtering."
      return
    }
    
    let build_order = (compute-single-service-build-order $f.service $expanded_versions $platforms_manifest $info)
    let hash_graph = (compute-service-def-hash-graph $build_order $info $sha_cache)
    
    if not ($f.pull | is-empty) {
      let pull_metrics = (run-pulls $f.pull $build_order $info $meta.is_local)
      print-pull-summary $pull_metrics
      print ""
    }
    
    if $f.disk_monitor != "off" {
      try { record-disk-usage $f.service "after-deps" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
    }
    
    for expanded_version in $expanded_versions {
      let prev_cache = $sha_cache
      let build_result = (build-single-version $f.service $expanded_version $f.push $f.latest $f.extra_tag $f.provenance $f.progress $info $meta $sha_cache $expanded_version.platform $default_platform $platforms_manifest $f.cache_bust $f.no_cache $f.dep_cache $f.push_deps $f.tag_deps $hash_graph $f.cache_match)
      $sha_cache = (try { $build_result.sha_cache } catch { $prev_cache })
    }
  } else {
    # Single-platform build (no platforms manifest)
    let build_order = (compute-single-service-build-order $f.service [$version_spec] null $info)
    let hash_graph = (compute-service-def-hash-graph $build_order $info $sha_cache)
    
    if not ($f.pull | is-empty) {
      let pull_metrics = (run-pulls $f.pull $build_order $info $meta.is_local)
      print-pull-summary $pull_metrics
      print ""
    }
    
    if $f.disk_monitor != "off" {
      try { record-disk-usage $f.service "after-deps" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
    }
    
    let prev_cache = $sha_cache
    let build_result = (build-single-version $f.service $version_spec $f.push $f.latest $f.extra_tag $f.provenance $f.progress $info $meta $sha_cache "" "" null $f.cache_bust $f.no_cache $f.dep_cache $f.push_deps $f.tag_deps $hash_graph $f.cache_match)
    $sha_cache = (try { $build_result.sha_cache } catch { $prev_cache })
  }
  
  if $f.disk_monitor != "off" {
    try { record-disk-usage $f.service "post-build" $f.disk_monitor } catch {|err| print $"WARNING: Disk monitoring failed: (try { $err.msg } catch { 'Unknown error' })" }
  }
}
