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

# Single-version build logic
# See docs/concepts/build-system.md for architecture

use ../registries/info.nu [get-registry-info]
use ../registries/core.nu [login-ghcr login-forgejo]
use ./docker.nu [build verify-image-exists-locally get-service-def-hash-from-image]
use ./dependencies.nu [resolve-dependencies]
use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest get-version-or-null resolve-version-name apply-version-defaults]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform get-platform-names expand-version-to-platforms strip-platform-suffix]
use ./config.nu [detect-all-source-types load-service-config]
use ../tls/validation.nu [sync-and-validate-ca]
use ../validate/core.nu [validate-tls-config-merged]
use ../core/repo.nu [get-repo-root]
use ../tls/lib.nu [read-ca-name]
use ./tags.nu [generate-tags]
use ./context.nu [extract-tls-metadata prepare-tls-context cleanup-tls-context]
use ./sources.nu [prepare-local-sources-context extract-source-shas]
use ./labels.nu [generate-labels]
use ./args.nu [generate-build-args]
use ./order.nu [build-dependency-graph topological-sort-dfs]
use ./pull.nu [compute-canonical-image-ref]
use ./hash.nu [compute-service-def-hash-graph]

# Filter build order to exclude target service (dependencies only)
export def filter-to-dependencies-only [
  build_order: list,
  target_node: string
] {
  $build_order | where {|node| $node != $target_node}
}

# Resolve dependency version_spec from node key
export def resolve-dependency-version-spec [
  dep_node: string,
  dep_platform: string
] {
  let parts = ($dep_node | split row ":")
  if ($parts | length) < 2 {
    error make { msg: $"Invalid dependency node format: '($dep_node)'. Expected 'service:version' or 'service:version:platform'" }
  }
  
  let dep_service = ($parts | get 0)
  let dep_version_name = ($parts | get 1)
  
  if not (check-versions-manifest-exists $dep_service) {
    error make { msg: $"Dependency service '($dep_service)' does not have a version manifest" }
  }
  
  let dep_versions_manifest = (load-versions-manifest $dep_service)
  
  let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
  let dep_platforms_manifest = (if $dep_has_platforms {
    try {
      load-platforms-manifest $dep_service
    } catch {
      null
    }
  } else {
    null
  })
  
  let base_version_name = (if $dep_platforms_manifest != null {
    let stripped = (try {
      strip-platform-suffix $dep_version_name $dep_platforms_manifest
    } catch {
      {base_name: $dep_version_name, platform_name: ""}
    })
    $stripped.base_name
  } else {
    $dep_version_name
  })
  
  let version_resolved = (resolve-version-name $base_version_name $dep_versions_manifest $dep_platforms_manifest null)
  
  let version_spec = (get-version-or-null $dep_versions_manifest $version_resolved.base_name)
  if $version_spec == null {
    error make { msg: $"Version '($version_resolved.base_name)' not found in manifest for dependency service '($dep_service)'" }
  }
  
  if $dep_has_platforms and ($dep_platform | str length) > 0 {
    let expanded_versions = (expand-version-to-platforms $version_spec $dep_platforms_manifest (get-default-platform $dep_platforms_manifest))
    let matching = ($expanded_versions | where {|item| $item.platform == $dep_platform} | first)
    if $matching == null {
      error make { msg: $"Platform '($dep_platform)' not found in expanded versions for dependency '($dep_service):($base_version_name)'" }
    }
    $matching
  } else {
    $version_spec
  }
}

# Build a single version of a service
# See docs/concepts/build-system.md for build flow details
export def build-single-version [
  service: string,
  version_spec: record,
  push_val: bool,
  latest_val: bool,
  extra_tag: string,
  provenance_val: bool,
  progress: string,
  info: record,
  meta: record,
  sha_cache: record,
  platform: string = "",
  default_platform: string = "",
  platforms: any = null,
  cache_bust_override: string = "",
  no_cache: bool = false,
  dep_cache_mode: string = "off",
  push_deps: bool = false,
  tag_deps: bool = false,
  hash_graph: record = {},
  cache_match: string = ""
] {
  let current_platform = (try { $version_spec.platform } catch { $platform })
  
  if $platforms != null and ($current_platform | str length) > 0 {
    let platform_names = (get-platform-names $platforms)
      if not ($current_platform in $platform_names) {
        let available = ($platform_names | str join ", ")
        error make { 
          msg: ($"Platform '($current_platform)' from version_spec not found in platforms manifest for service '($service)'.\n\n" +
                $"Available platforms: ($available)\n" +
                "This is an internal error - platform should have been validated earlier.\n" +
                "Please report this issue.")
        }
      }
  }
  
  let cfg = (load-service-config $service $version_spec $current_platform $platforms)
  
  let cfg_sources = (try { $cfg.sources } catch { {} })
  let source_types = (if not ($cfg_sources | is-empty) {
    detect-all-source-types $cfg_sources
  } else {
    {}
  })
  
  if not ($cfg_sources | is-empty) {
    let local_sources = ($source_types | columns | where {|k| ($source_types | get $k) == "local"})
    if ($local_sources | length) > 0 and not $meta.is_local {
      error make {
        msg: ($"Error: Local sources are not allowed in CI builds. Use git sources instead.\n" +
              $"Local sources found: [($local_sources | str join ', ')]")
      }
    }
  }
  
  let tls_validation = (validate-tls-config-merged $cfg $service)
  if not $tls_validation.valid {
    print "ERROR: TLS validation failed"
    for error in $tls_validation.errors {
      print $"  - ($error)"
    }
    if "warnings" in ($tls_validation | columns) {
      for warning in $tls_validation.warnings {
        print $"  WARNING: ($warning)"
      }
    }
    error make {msg: "TLS validation failed"}
  }
  
  let tls_enabled_check = (try { $cfg.tls.enabled | default false } catch { false })
  let ca_name = (if $tls_enabled_check {
    read-ca-name $tls_enabled_check
  } else {
    ""
  })
  
  let tls_meta = (extract-tls-metadata $cfg $ca_name)
  if $tls_meta.enabled {
    sync-and-validate-ca $service $cfg $ca_name
  }
  
  let is_local = $meta.is_local
  let version_tag = $version_spec.name
  
  mut current_cache = $sha_cache
  
  let source_shas_result = (if (try { $cfg.sources } catch { {} } | is-empty) {
    {shas: {}, cache: $current_cache}
  } else {
    let git_sources = (if not ($source_types | is-empty) {
      ($cfg_sources | columns | where {|k| ($source_types | get $k | default "git") == "git"} | reduce --fold {} {|k, acc|
        $acc | upsert $k ($cfg_sources | get $k)
      })
    } else {
      ($cfg_sources | columns | where {|k|
        let source = ($cfg_sources | get $k)
        not ("path" in ($source | columns))
      } | reduce --fold {} {|k, acc|
        $acc | upsert $k ($cfg_sources | get $k)
      })
    })
    
    if ($git_sources | is-empty) {
      let local_shas = ($cfg_sources | columns | reduce --fold {} {|k, acc|
        let sha_key = ($"($k | str upcase)_SHA")
        $acc | upsert $sha_key ""
      })
      {shas: $local_shas, cache: $current_cache}
    } else {
      let git_shas_result = (extract-source-shas $git_sources $service $current_cache)
      let local_shas = ($cfg_sources | columns | where {|k| ($source_types | get $k | default "git") == "local"} | reduce --fold {} {|k, acc|
        let sha_key = ($"($k | str upcase)_SHA")
        $acc | upsert $sha_key ""
      })
      {
        shas: ($git_shas_result.shas | merge $local_shas),
        cache: $git_shas_result.cache
      }
    }
  })
  let source_shas = $source_shas_result.shas
  $current_cache = ($current_cache | merge $source_shas_result.cache)

  let tags = (generate-tags $service $version_spec $is_local $info $current_platform $default_platform)
  
  let node_key = (if ($current_platform | str length) > 0 {
    $"($service):($version_tag):($current_platform)"
  } else {
    $"($service):($version_tag)"
  })
  let service_def_hash = (try { $hash_graph | get $node_key } catch { "" })
  
  let labels = (generate-labels $service $meta $cfg $source_shas $source_types $service_def_hash)
  
  let build_label = (if ($current_platform | str length) > 0 {
    $"($service):($version_tag)-($current_platform)"
  } else {
    $"($service):($version_tag)"
  })
  print $"Building ($build_label)"
  if ($tags | length) > 0 {
    print $"Tags: ($tags | str join ', ')"
  }

  if not $is_local {
    let _a = (login-ghcr)
    let _b = (login-forgejo $info.forgejo_registry)
  }
  
  let context = ($cfg.context)
  let dockerfile = ($cfg.dockerfile)
  
  let ci_mode = (not $is_local)
  let allow_auto_build = ($dep_cache_mode != "strict")
  
  if $allow_auto_build {
    let graph = (build-dependency-graph $service $version_spec $cfg $current_platform $platforms $is_local $info)
    let build_order = (topological-sort-dfs $graph)
    
    let target_node = (if ($current_platform | str length) > 0 {
      $"($service):($version_tag):($current_platform)"
    } else {
      $"($service):($version_tag)"
    })
    let dep_build_order = (filter-to-dependencies-only $build_order $target_node)
    
    if not ($dep_build_order | is-empty) {
      print ""
      print "=== Building Dependencies ==="
      print ""
      print "Build order:"
      for $idx in 0..<($dep_build_order | length) {
        let dep_node = ($dep_build_order | get $idx)
        let label = ($idx + 1 | into string)
        print $"  ($label). ($dep_node)"
      }
      print ""
      
      for dep_node in $dep_build_order {
        let dep_parts = ($dep_node | split row ":")
        let dep_service = ($dep_parts | get 0)
        let dep_version_name = ($dep_parts | get 1)
        let dep_platform = (if ($dep_parts | length) > 2 { $dep_parts | get 2 } else { "" })
        
        let dep_info = (get-registry-info)
        let dep_meta = $meta
        
        let dep_version_spec = (resolve-dependency-version-spec $dep_node $dep_platform)
        
        let dep_has_platforms = (check-platforms-manifest-exists $dep_service)
        let dep_platforms_manifest = (if $dep_has_platforms {
          try {
            load-platforms-manifest $dep_service
          } catch {
            null
          }
        } else {
          null
        })
        
        let dep_default_platform = (if $dep_has_platforms {
          get-default-platform $dep_platforms_manifest
        } else {
          ""
        })
        
        let dep_push = $push_deps
        let dep_latest = (if $tag_deps { $latest_val } else { false })
        let dep_extra_tag = (if $tag_deps { $extra_tag } else { "" })
        
        let dep_label = (if ($dep_platform | str length) > 0 {
          $"($dep_service):($dep_version_spec.name)-($dep_platform)"
        } else {
          $"($dep_service):($dep_version_spec.name)"
        })
        
        let cache_hint = (if ($cache_match | str length) > 0 { $" [cache: ($cache_match)]" } else { "" })
        
        let should_skip_build = (if $ci_mode and $dep_cache_mode != "off" {
          let expected_hash = (try { $hash_graph | get $dep_node } catch { "" })
          
          if ($expected_hash | str length) == 0 {
            false
          } else {
            let dep_image_ref = (compute-canonical-image-ref $dep_node $info $is_local)
            let actual_hash = (get-service-def-hash-from-image $dep_image_ref)
            
            if ($actual_hash | str length) == 0 {
              print $"CI: Dependency '($dep_label)' - local image missing or unlabeled, will auto-build($cache_hint)"
              false
            } else if $actual_hash == $expected_hash {
              print $"CI: Dependency '($dep_label)' - found fresh image with matching hash, skipping build"
              true
            } else {
              print $"CI: Dependency '($dep_label)' - hash mismatch (expected: ($expected_hash | str substring 0..8)..., actual: ($actual_hash | str substring 0..8)...), will auto-build($cache_hint)"
              false
            }
          }
        } else {
          false
        })
        
        if $should_skip_build {
          continue
        }
        
        let prev_cache = $current_cache
        try {
          let build_result = (build-single-version $dep_service $dep_version_spec $dep_push $dep_latest $dep_extra_tag $provenance_val $progress $dep_info $dep_meta $current_cache $dep_platform $dep_default_platform $dep_platforms_manifest $cache_bust_override $no_cache "strict" $push_deps $tag_deps $hash_graph $cache_match)
          $current_cache = (try { $build_result.sha_cache } catch { $prev_cache })
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          error make {
            msg: ($"Failed to build dependency '($dep_label)' while building '($build_label)'.\n\n" +
                  $"Error: ($error_msg)\n\n" +
                  "Common causes:\n" +
                  "  - Missing required files (check error message above)\n" +
                  "  - Invalid configuration in service manifest\n" +
                  "  - Docker build failure (check Dockerfile and context)")
          }
        }
      }
    }
  }
  
  let deps_resolved = (resolve-dependencies $cfg $version_tag $is_local $info $current_platform $platforms)
  if $is_local {
    for dep_image in ($deps_resolved | values) {
      let exists = (verify-image-exists-locally $dep_image)
      if not $exists {
        print $"Warning: Dependency image '($dep_image)' not found locally. Build may fail."
      }
    }
  }
  
  if $ci_mode and $dep_cache_mode == "strict" {
    let strict_graph = (build-dependency-graph $service $version_spec $cfg $current_platform $platforms $is_local $info)
    let strict_build_order = (topological-sort-dfs $strict_graph)
    let strict_target_node = (if ($current_platform | str length) > 0 {
      $"($service):($version_tag):($current_platform)"
    } else {
      $"($service):($version_tag)"
    })
    let strict_dep_order = (filter-to-dependencies-only $strict_build_order $strict_target_node)
    
    mut stale_deps = []
    
    for dep_node in $strict_dep_order {
      let expected_hash = (try { $hash_graph | get $dep_node } catch { "" })
      
      if ($expected_hash | str length) == 0 {
        continue
      }
      
      let dep_image_ref = (compute-canonical-image-ref $dep_node $info $is_local)
      let actual_hash = (get-service-def-hash-from-image $dep_image_ref)
      
      if ($actual_hash | str length) == 0 {
        $stale_deps = ($stale_deps | append {node: $dep_node, reason: "missing or unlabeled"})
      } else if $actual_hash != $expected_hash {
        $stale_deps = ($stale_deps | append {node: $dep_node, reason: $"hash mismatch (expected: ($expected_hash | str substring 0..8)..., actual: ($actual_hash | str substring 0..8)...)"})
      }
    }
    
    if not ($stale_deps | is-empty) {
      let stale_list = ($stale_deps | each {|d| $"  - ($d.node): ($d.reason)"} | str join "\n")
      error make {
        msg: ($"CI strict mode (--dep-cache=strict): Found stale or missing dependency images.\n\n" +
              $"The following dependencies need to be rebuilt:\n($stale_list)\n\n" +
              "In strict mode, dependencies must have matching service definition hashes.\n" +
              "Either rebuild the dependencies first, or use --dep-cache=soft to allow auto-building.")
      }
    }
  }
  
  let tls_context = (prepare-tls-context $service $context $tls_meta.enabled $tls_meta.mode)
  
  let repo_root = (get-repo-root)
  let local_source_paths = (if not ($cfg_sources | is-empty) {
    prepare-local-sources-context $service $context $cfg_sources $source_types $repo_root
  } else {
    {}
  })
  
  let build_args = (generate-build-args $version_tag $cfg $meta $deps_resolved $tls_meta $cache_bust_override $no_cache $source_shas $source_types $local_source_paths)
  
  print ""
  print $"=== Building ($service):($version_tag) ==="
  print ""
  
  build --context $context --dockerfile $dockerfile --platforms $meta.platforms --tags $tags --build-args $build_args --labels $labels --progress $progress $push_val $provenance_val $is_local
  
  cleanup-tls-context $context $tls_context
  
  {sha_cache: $current_cache}
}

# Print machine-parseable build summary
export def print-build-summary [
  successes: list,
  failures: list,
  skipped: list
] {
  let success_count = ($successes | length)
  let failure_count = ($failures | length)
  let skipped_count = ($skipped | length)
  let total = $success_count + $failure_count + $skipped_count
  
  let status = (if $failure_count == 0 {
    if $success_count == $total {
      "SUCCESS"
    } else {
      "PARTIAL"
    }
  } else {
    "FAILED"
  })
  
  print ""
  print "=== Build Summary ==="
  print $"STATUS: ($status)"
  print $"SUCCESS: ($success_count)"
  print $"FAILED: ($failure_count)"
  print $"SKIPPED: ($skipped_count)"
  print ""
  
  if $success_count > 0 {
    print "SUCCESS:"
    for item in $successes {
      print $"  - ($item.label)"
    }
    print ""
  }
  
  if $failure_count > 0 {
    print "FAILED:"
    for item in $failures {
      print $"  - ($item.label)"
      print $"    Error: ($item.error)"
    }
    print ""
  }
  
  if $skipped_count > 0 {
    print "SKIPPED:"
    for item in $skipped {
      print $"  - ($item.label)"
      print $"    Reason: ($item.reason)"
    }
    print ""
  }
}
