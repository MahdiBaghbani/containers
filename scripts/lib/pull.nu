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

# Pull orchestration for pre-build image caching and validation
# See docs/concepts/build-system.md for --pull flag documentation

use ./build-config.nu [get-env-or-config]
use ./registry/registry-info.nu [get-registry-info]

# Valid pull modes
const VALID_PULL_MODES = ["deps", "externals"]

# Parse and validate --pull flag value
# Returns list of validated modes or errors on invalid input
export def parse-pull-modes [raw: string = ""] {
  # Empty string means no --pull flag provided
  if ($raw | str trim | is-empty) {
    return []
  }
  
  # Split on comma, trim whitespace, drop empty segments
  let segments = ($raw | split row "," | each {|s| $s | str trim} | where {|s| ($s | str length) > 0})
  
  # Bare --pull (no value after split) is an error
  if ($segments | is-empty) {
    error make {
      msg: "Missing value for --pull flag. Use `--pull=deps`, `--pull=externals`, or `--pull=deps,externals`."
    }
  }
  
  # Validate each segment
  for segment in $segments {
    if not ($segment in $VALID_PULL_MODES) {
      let valid_list = ($VALID_PULL_MODES | str join ", ")
      error make {
        msg: $"Invalid pull mode '($segment)'. Valid modes: ($valid_list)"
      }
    }
  }
  
  # Deduplicate and return
  $segments | uniq
}

# Orchestrate pre-pull operations for deps and/or externals
# Called before build starts when --pull flag is provided
#
# Parameters:
#   modes: list of pull modes (from parse-pull-modes)
#   build_order: list of service:version[:platform] nodes to be built
#   registry_info: registry configuration record
#   is_local: whether this is a local build
#
# Returns: record with pull metrics {deps: {...}, externals: {...}}
export def run-pulls [
  modes: list,
  build_order: list,
  registry_info: record,
  is_local: bool
] {
  # Initialize metrics
  mut metrics = {
    deps: {pulled: 0, skipped: 0, failed: 0},
    externals: {pulled: 0, skipped: 0, failed: 0}
  }
  
  # Skip if no modes requested
  if ($modes | is-empty) {
    return $metrics
  }
  
  # Process deps mode (best-effort cache warm-up)
  if "deps" in $modes {
    print "=== Pre-pulling Dependencies (cache warm-up) ==="
    print ""
    let deps_result = (pull-deps $build_order $registry_info $is_local)
    $metrics = ($metrics | upsert deps $deps_result)
  }
  
  # Process externals mode (fail-fast preflight)
  if "externals" in $modes {
    print ""
    print "=== Pre-pulling External Images (preflight check) ==="
    print ""
    let externals_result = (pull-externals $build_order $registry_info)
    $metrics = ($metrics | upsert externals $externals_result)
  }
  
  $metrics
}

# Pull internal dependency images (best-effort, non-fatal on failure)
def pull-deps [
  build_order: list,
  registry_info: record,
  is_local: bool
] {
  mut pulled = 0
  mut skipped = 0
  mut failed = 0
  mut seen_refs = []
  
  for node in $build_order {
    # Compute canonical image reference for this node
    let image_ref = (compute-canonical-image-ref $node $registry_info $is_local)
    
    # Skip if already processed (deduplication)
    if $image_ref in $seen_refs {
      $skipped = $skipped + 1
      continue
    }
    $seen_refs = ($seen_refs | append $image_ref)
    
    # Attempt pull (best-effort)
    let result = (pull-image $image_ref)
    if $result.success {
      print $"OK: Pulled ($image_ref)"
      $pulled = $pulled + 1
    } else {
      print $"WARNING: Cache warm-up failed for ($image_ref): ($result.error)"
      print "  Build will proceed (dependency will be built if needed)"
      $failed = $failed + 1
    }
  }
  
  {pulled: $pulled, skipped: $skipped, failed: $failed}
}

# Pull external images with fail-fast semantics
def pull-externals [
  build_order: list,
  registry_info: record
] {
  # Aggregate external images from all build-order nodes
  let aggregated = (aggregate-external-images $build_order)
  
  if ($aggregated | is-empty) {
    print "No external images declared in build scope."
    return {pulled: 0, skipped: 0, failed: 0}
  }
  
  mut pulled = 0
  mut skipped = 0
  mut failures = []
  
  for entry in $aggregated {
    let image_ref = $entry.image_ref
    let nodes = $entry.nodes
    
    let result = (pull-image $image_ref)
    if $result.success {
      let node_list = ($nodes | str join ", ")
      print $"OK: Pulled ($image_ref) (used by: ($node_list))"
      $pulled = $pulled + 1
    } else {
      $failures = ($failures | append {
        image_ref: $image_ref,
        nodes: $nodes,
        error: $result.error
      })
    }
  }
  
  # Fail-fast: if any external images failed, report and error
  if not ($failures | is-empty) {
    print ""
    print "ERROR: External image preflight failed"
    print ""
    for failure in $failures {
      let node_list = ($failure.nodes | str join ", ")
      print $"  Missing: ($failure.image_ref)"
      print $"    Required by: ($node_list)"
      print $"    Error: ($failure.error)"
      print ""
    }
    error make {
      msg: $"External image preflight failed: ($failures | length) image\(s\) could not be pulled"
    }
  }
  
  {pulled: $pulled, skipped: $skipped, failed: ($failures | length)}
}

# Compute canonical image reference for a build-order node
# Matches the tag format used by generate-tags in build-ops.nu
# Exported for testing
export def compute-canonical-image-ref [
  node: string,
  registry_info: record,
  is_local: bool
] {
  # Parse node: service:version or service:version:platform
  let parts = ($node | split row ":")
  let service = ($parts | get 0)
  let version = ($parts | get 1)
  let platform = (if ($parts | length) > 2 { $parts | get 2 } else { "" })
  
  # Construct version tag (with platform suffix if multi-platform)
  let version_tag = (if ($platform | str length) > 0 {
    $"($version)-($platform)"
  } else {
    $version
  })
  
  # Construct full image reference based on environment
  if $is_local {
    $"($service):($version_tag)"
  } else {
    let ci_platform = (try { $registry_info.ci_platform } catch { "local" })
    
    if $ci_platform == "github" {
      $"($registry_info.github_registry)/($registry_info.github_path)/($service):($version_tag)"
    } else if $ci_platform == "forgejo" {
      $"($registry_info.forgejo_registry)/($registry_info.forgejo_path)/($service):($version_tag)"
    } else {
      # Fallback to local format
      $"($service):($version_tag)"
    }
  }
}

# Aggregate external images from all nodes in build order
# Returns list of {image_ref: string, nodes: list<string>}
def aggregate-external-images [build_order: list] {
  use ./manifest.nu [check-versions-manifest-exists load-versions-manifest get-version-or-null]
  use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest strip-platform-suffix]
  use ./build-ops.nu [load-service-config]
  
  # Accumulate external images with their referencing nodes
  let result = ($build_order | reduce --fold {} {|node, acc|
    # Parse node
    let parts = ($node | split row ":")
    if ($parts | length) < 2 {
      $acc  # Skip invalid nodes
    } else {
      let service = ($parts | get 0)
      let version_name = ($parts | get 1)
      let platform = (if ($parts | length) > 2 { $parts | get 2 } else { "" })
      
      # Load service config to get external_images
      let external_refs = (try {
        # Load versions manifest
        if not (check-versions-manifest-exists $service) {
          []
        } else {
          let versions_manifest = (load-versions-manifest $service)
          let has_platforms = (check-platforms-manifest-exists $service)
          let platforms_manifest = (if $has_platforms {
            try { load-platforms-manifest $service } catch { null }
          } else {
            null
          })
          
          # Strip platform suffix from version name if present
          let base_version = (if $platforms_manifest != null {
            let stripped = (try {
              strip-platform-suffix $version_name $platforms_manifest
            } catch {
              {base_name: $version_name, platform_name: ""}
            })
            $stripped.base_name
          } else {
            $version_name
          })
          
          # Get version spec
          let version_spec = (get-version-or-null $versions_manifest $base_version)
          if $version_spec == null {
            []
          } else {
            # Load merged config
            let cfg = (load-service-config $service $version_spec $platform $platforms_manifest)
            
            # Extract external images
            let external_images = (try { $cfg.external_images } catch { {} })
            if ($external_images | is-empty) {
              []
            } else {
              # Resolve each external image to its effective ref
              ($external_images | columns | reduce --fold [] {|img_key, refs|
                let img = ($external_images | get $img_key)
                let name = (try { $img.name } catch { "" })
                let tag = (try { $img.tag } catch { "" })
                let build_arg = (try { $img.build_arg } catch { "" })
                
                if ($name | str length) == 0 or ($tag | str length) == 0 {
                  $refs
                } else {
                  # Apply env var override (same as process-external-images-to-build-args)
                  let image_value = $"($name):($tag)"
                  let effective_ref = (if ($build_arg | str length) > 0 {
                    get-env-or-config $build_arg $image_value
                  } else {
                    $image_value
                  })
                  $refs | append $effective_ref
                }
              })
            }
          }
        }
      } catch {
        []  # Skip nodes that fail to load
      })
      
      # Add each external ref to accumulator
      ($external_refs | reduce --fold $acc {|ref, inner_acc|
        if $ref in ($inner_acc | columns) {
          # Add node to existing entry's nodes list
          let existing = ($inner_acc | get $ref)
          let new_nodes = ($existing.nodes | append $node)
          $inner_acc | upsert $ref {image_ref: $ref, nodes: $new_nodes}
        } else {
          # Create new entry
          $inner_acc | upsert $ref {image_ref: $ref, nodes: [$node]}
        }
      })
    }
  })
  
  # Convert to list format
  $result | columns | each {|key| $result | get $key}
}

# Pull a single image using docker pull
# Returns {success: bool, error: string}
def pull-image [image_ref: string] {
  let result = (try {
    let cmd_result = (^docker pull $image_ref | complete)
    if $cmd_result.exit_code == 0 {
      {success: true, error: ""}
    } else {
      let stderr = (try { $cmd_result.stderr } catch { "Unknown error" })
      {success: false, error: $stderr}
    }
  } catch {|err|
    {success: false, error: (try { $err.msg } catch { "Command execution failed" })}
  })
  
  $result
}

# Print pull summary (follows print-build-summary style from build.nu)
export def print-pull-summary [metrics: record] {
  let deps = (try { $metrics.deps } catch { {pulled: 0, skipped: 0, failed: 0} })
  let externals = (try { $metrics.externals } catch { {pulled: 0, skipped: 0, failed: 0} })
  
  let total_pulled = $deps.pulled + $externals.pulled
  let total_skipped = $deps.skipped + $externals.skipped
  let total_failed = $deps.failed + $externals.failed
  
  # Determine status
  let status = (if $externals.failed > 0 {
    "FAILED"
  } else if $total_pulled > 0 or $total_skipped > 0 {
    "SUCCESS"
  } else {
    "SKIPPED"
  })
  
  print ""
  print "=== Pull Summary ==="
  print $"STATUS: ($status)"
  print ""
  
  if $deps.pulled > 0 or $deps.skipped > 0 or $deps.failed > 0 {
    print "Dependencies (cache warm-up):"
    print $"  Pulled: ($deps.pulled)"
    print $"  Skipped (deduped): ($deps.skipped)"
    print $"  Failed (non-fatal): ($deps.failed)"
    print ""
  }
  
  if $externals.pulled > 0 or $externals.skipped > 0 or $externals.failed > 0 {
    print "External Images (preflight):"
    print $"  Pulled: ($externals.pulled)"
    print $"  Skipped (deduped): ($externals.skipped)"
    print $"  Failed (fatal): ($externals.failed)"
    print ""
  }
}
