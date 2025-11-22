#! /usr/bin/env nu

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

use ./lib/meta.nu [detect-build]
use ./lib/registry/registry-info.nu [get-registry-info]
use ./lib/registry/registry.nu [login-ghcr login-forgejo]
use ./lib/buildx.nu [build load-image-into-builder]
use ./lib/dependencies.nu [resolve-dependencies]
use ./lib/manifest.nu [check-versions-manifest-exists load-versions-manifest filter-versions get-version-or-null resolve-version-name get-version-spec apply-version-defaults]
use ./lib/platforms.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform get-platform-names expand-version-to-platforms strip-platform-suffix]
use ./lib/matrix.nu [generate-service-matrix]
use ./lib/build-config.nu [parse-bool-flag detect-all-source-types]
use ./lib/tls-validation.nu [sync-and-validate-ca]
use ./lib/validate.nu [validate-tls-config-merged]
use ./lib/common.nu [read-ca-name get-repo-root]
use ./lib/build-ops.nu [
    load-service-config
    extract-tls-metadata
    prepare-tls-context
    cleanup-tls-context
    prepare-local-sources-context
    generate-tags
    generate-labels
    generate-build-args
]
use ./lib/build-order.nu [build-dependency-graph topological-sort-dfs show-build-order-for-version]

export def main [
  --service: string,
  --all-services,
  --push,
  --latest,
  --extra-tag: string = "",
  --provenance,
  # Version from manifest or custom version
  --version: string = "",
  # Build all versions from manifest
  --all-versions,
  # Build specific versions from manifest (comma-separated)
  --versions: string = "",
  # Build only versions marked as latest in manifest
  --latest-only,
  # Platform to build (filters multi-platform builds)
  --platform: string = "",
  # Output GitHub Actions matrix JSON and exit
  --matrix-json,
  # Build progress output: auto, plain, tty. Use 'plain' for full logs when debugging
  --progress: string = "auto",
  # Global cache bust override (applies to all services in build)
  --cache-bust: string = "",
  # Generate random UUID for all services (forces cache invalidation)
  --no-cache,
  # Show build order and exit (no build)
  --show-build-order,
  # Disable automatic dependency building (default: auto-build enabled)
  --no-auto-build-deps,
  # Push dependency images when auto-building (independent of --push)
  --push-deps,
  # Tag dependencies with --latest and --extra-tag when auto-building
  --tag-deps,
  # Fail fast on first error (default: continue building all services)
  --fail-fast
] {
  let info = (get-registry-info)
  let meta = (detect-build)
  
  # Initialize SHA cache (shared across all services in build session)
  mut sha_cache = {}
  
  let all_services_val = (parse-bool-flag ($all_services | default false))
  let push_val = (parse-bool-flag ($push | default false))
  let latest_val = (parse-bool-flag ($latest | default true))
  let provenance_val = (parse-bool-flag ($provenance | default false))
  let all_versions_val = (parse-bool-flag ($all_versions | default false))
  let latest_only_val = (parse-bool-flag ($latest_only | default false))
  let matrix_json_val = (parse-bool-flag ($matrix_json | default false))
  let cache_bust = $cache_bust
  let no_cache = (parse-bool-flag ($no_cache | default false))
  let show_build_order = (parse-bool-flag ($show_build_order | default false))
  let no_auto_build_deps = (parse-bool-flag ($no_auto_build_deps | default false))
  let push_deps = (parse-bool-flag ($push_deps | default false))
  let tag_deps = (parse-bool-flag ($tag_deps | default false))
  let fail_fast = (parse-bool-flag ($fail_fast | default false))
  
  # Validate flag conflicts with --all-services
  if $all_services_val {
    let service_provided = (try { ($service | str length) > 0 } catch { false })
    if $service_provided {
      error make {
        msg: "Cannot use --service with --all-services. Use --all-services alone to build all services."
      }
    }
    
    if ($version | str length) > 0 {
      error make {
        msg: "Cannot use --version with --all-services. Use --latest-only or --all-versions to control version selection."
      }
    }
    
    if ($versions | str length) > 0 {
      error make {
        msg: "Cannot use --versions with --all-services. Use --latest-only or --all-versions to control version selection."
      }
    }
    
    # Route to build-all-services function
    build-all-services $push_val $latest_val $extra_tag $provenance_val $progress $info $meta $sha_cache $all_versions_val $latest_only_val $platform $cache_bust $no_cache $no_auto_build_deps $push_deps $tag_deps $fail_fast $show_build_order $matrix_json_val
    return
  }
  
  # Require --service when not using --all-services
  let service_provided = (try { ($service | str length) > 0 } catch { false })
  if not $service_provided {
    error make {
      msg: "Either --service <name> or --all-services must be specified."
    }
  }
  
  let has_versions_manifest = (check-versions-manifest-exists $service)
  let versions_manifest = (if $has_versions_manifest { load-versions-manifest $service } else { null })
  let has_platforms_manifest = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms_manifest { load-platforms-manifest $service } else { null })
  let default_platform = (if $has_platforms_manifest { get-default-platform $platforms_manifest } else { "" })
  
  if ($platform | str length) > 0 {
    if not $has_platforms_manifest {
      error make { 
        msg: ($"Platform '($platform)' specified but service '($service)' has no platforms manifest.\n\n" +
              "The --platform flag is only valid for multi-platform services.\n" +
              "Options:\n" +
              "1. Remove the --platform flag (service is single-platform)\n" +
              "2. Create a platforms manifest: services/($service)/platforms.nuon\n" +
              "3. See docs/guides/multi-platform-builds.md for details")
      }
    }
    let platform_names = (get-platform-names $platforms_manifest)
    if not ($platform in $platform_names) {
      let available = ($platform_names | str join ", ")
      let first_platform = ($available | split row ", " | first)
      error make { 
        msg: ($"Platform '($platform)' not found in platforms manifest for service '($service)'.\n\n" +
              $"Available platforms: ($available)\n" +
              "Options:\n" +
              $"1. Use one of the available platforms: --platform ($first_platform)\n" +
              $"2. Add the platform to services/($service)/platforms.nuon\n" +
              "3. Check for typos in the platform name")
      }
    }
  }
  
  if $matrix_json_val {
    if not $has_versions_manifest {
      error make { 
        msg: ($"Service '($service)' does not have a version manifest. Cannot generate matrix.\n\n" +
              "Matrix generation requires a version manifest.\n" +
              "To fix:\n" +
              "1. Create services/($service)/versions.nuon\n" +
              "2. Define at least one version with a 'default' field\n" +
              "3. See docs/guides/multi-version-builds.md for examples")
      }
    }
    let matrix = (generate-service-matrix $service)
    print ($matrix | to json)
    return
  }
  
  # Reject platform suffixes when no platforms manifest exists
  if not $has_platforms_manifest and ($version | str length) > 0 {
    if ($version | str contains "-") {
      let parts = ($version | split row "-")
      if ($parts | length) > 1 {
        let potential_platform = ($parts | last)
        if ($potential_platform =~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
          error make { 
            msg: ($"Version '($version)' contains platform suffix '-($potential_platform)' but service '($service)' has no platforms manifest.\n\n" +
                  "Platform suffixes are only valid for multi-platform services.\n" +
                  "Options:\n" +
                  "1. Remove the platform suffix: --version ($parts | drop | str join "-")\n" +
                  "2. Create a platforms manifest: services/($service)/platforms.nuon\n" +
                  "3. If this is a valid version name (not a platform suffix), use it as-is in your versions.nuon manifest")
          }
        }
      }
    }
  }
  
  mut version_suffix_info = null
  if $has_platforms_manifest and ($version | str length) > 0 {
    let stripped = (try {
      strip-platform-suffix $version $platforms_manifest
    } catch {|err|
      error make { msg: $"Invalid version format '($version)': ($err.msg)" }
    })
    
    if ($stripped.platform_name | str length) > 0 {
      $version_suffix_info = $stripped
      
      let platform_names = (get-platform-names $platforms_manifest)
      if not ($stripped.platform_name in $platform_names) {
        let available = ($platform_names | str join ", ")
        error make { msg: $"Version suffix platform '($stripped.platform_name)' not found in platforms manifest. Available: ($available)" }
      }
      
      if ($platform | str length) > 0 and $platform != $stripped.platform_name {
        error make { msg: $"Version suffix '($stripped.platform_name)' conflicts with --platform '($platform)'" }
      }
    }
  }
  
  if $show_build_order {
    if not $has_versions_manifest {
      error make { 
        msg: ($"Service '($service)' does not have a version manifest. Cannot show build order.\n\n" +
              "Build order requires a version manifest.\n" +
              "To fix:\n" +
              "1. Create services/($service)/versions.nuon\n" +
              "2. Define at least one version with a 'default' field\n" +
              "3. See docs/guides/multi-version-builds.md for examples")
      }
    }
    
    # Check for multi-version flags
    let has_multi_version_flags = ($all_versions_val or ($versions | str length) > 0 or $latest_only_val)
    
    if not $has_multi_version_flags {
      # Single-version path
      # Resolve version
      let version_resolved = (resolve-version-name $version $versions_manifest $platforms_manifest $version_suffix_info)
      let version_spec = (get-version-or-null $versions_manifest $version_resolved.base_name)
      
      if $version_spec == null {
        let available_versions = (try {
          $versions_manifest.versions | each {|v| $v.name} | str join ", "
        } catch {
          "unknown"
        })
        error make { 
          msg: ($"Version '($version_resolved.base_name)' not found in manifest for service '($service)'.\n\n" +
                $"Available versions: ($available_versions)")
        }
      }
      
      # Determine platform
      let target_platform = (if ($platform | str length) > 0 {
        $platform
      } else if ($version_resolved.detected_platform | str length) > 0 {
        $version_resolved.detected_platform
      } else if $has_platforms_manifest {
        $default_platform
      } else {
        ""
      })
      
      # Load service config and show build order
      print "=== Build Order ==="
      print ""
      show-build-order-for-version $service $version_spec $target_platform $platforms_manifest $info {}
      
      return
    }
    
    if $has_multi_version_flags {
      # Version manifest check (for consistency with build path error message style)
      # NOTE: This check is technically redundant since the version manifest is already validated
      # before the --show-build-order early return. However, it is included here to:
      # 1. Match the build path pattern (which checks manifest in multi-version path at line 343)
      # 2. Provide consistent error message context ("show build order" vs "build")
      # 3. Ensure error messages are clear and contextual for the display operation
      if not $has_versions_manifest {
        error make {
          msg: ($"Service '($service)' does not have a version manifest. Cannot show build order for multiple versions.\n\n" +
                "Multi-version build order requires a version manifest.\n" +
                "To fix:\n" +
                "1. Create services/($service)/versions.nuon\n" +
                "2. Define at least one version with a 'default' field\n" +
                "3. See docs/guides/multi-version-builds.md for examples")
        }
      }
      
      # Multi-version path: filter, expand, and display
      let filter_result = (filter-versions $versions_manifest $platforms_manifest --all=$all_versions_val --versions=$versions --latest-only=$latest_only_val)
      # Apply defaults to each version spec (filter-versions returns raw specs without defaults)
      let versions_to_build = ($filter_result.versions | each {|v| apply-version-defaults $versions_manifest $v})
      let detected_platforms_from_filter = $filter_result.detected_platforms
      
      if ($versions_to_build | is-empty) {
        print "No versions to build based on filter criteria."
        return
      }
      
      # Platform expansion
      mut expanded_versions = []
      if $has_platforms_manifest {
        for version_spec in $versions_to_build {
          $expanded_versions = ($expanded_versions | append (expand-version-to-platforms $version_spec $platforms_manifest $default_platform))
        }
        
        # Apply platform filtering
        $expanded_versions = ($expanded_versions | where {|item|
          ($platform | str length) == 0 or $item.platform == $platform
        } | where {|item|
          ($detected_platforms_from_filter | is-empty) or ($item.platform in $detected_platforms_from_filter)
        })
        
        if ($expanded_versions | is-empty) {
          print "No versions to build after platform filtering."
          return
        }
      } else {
        # Single-platform: use versions_to_build as-is
        # Note: This differs from build path (lines 420-460) which iterates directly over versions_to_build.
        # We use expanded_versions for consistency, but expanded_version.platform will be empty/missing.
        $expanded_versions = $versions_to_build
      }
      
      # Display build orders with grouped output
      print "=== Build Order ==="
      print ""
      
      # Initialize graph cache (shared across all versions for performance)
      mut graph_cache = {}
      
      for $idx in 0..<($expanded_versions | length) {
        let expanded_version = ($expanded_versions | get $idx)
        
        # Extract platform once (for single-platform services, expanded_version.platform may not exist)
        let version_platform = (try { $expanded_version.platform } catch { "" })
        
        # Format version/platform label
        let version_label = (if $has_platforms_manifest and ($version_platform | str length) > 0 {
          $"Version: ($expanded_version.name) (($version_platform))"
        } else {
          $"Version: ($expanded_version.name)"
        })
        
        print $version_label
        
        # Show build order for this version/platform with error handling and cache updates
        # Note: Continue on error (graceful degradation) - matches Decision #6
        # This allows displaying build orders for other versions even if one fails
        try {
          let result = (show-build-order-for-version $service $expanded_version $version_platform $platforms_manifest $info $graph_cache)
          $graph_cache = $result.cache  # Update cache for next iteration
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Could not determine build order: ($error_msg)"
          # Continue to next version (graceful degradation)
        }
        
        # Add blank line between versions (except last)
        if $idx < (($expanded_versions | length) - 1) {
          print ""
        }
      }
      
      return
    }
  }
  
  if not $has_platforms_manifest and ($versions | str length) > 0 {
    for v in ($versions | split row "," | each {|x| $x | str trim} | where ($it | str length) > 0) {
      if ($v | str contains "-") {
        let parts = ($v | split row "-")
        if ($parts | length) > 1 {
          let potential_platform = ($parts | last)
          if ($potential_platform =~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            error make { 
              msg: ($"Version '($v)' in --versions flag contains platform suffix '-($potential_platform)' but service '($service)' has no platforms manifest.\n\n" +
                    "Platform suffixes are only valid for multi-platform services.\n" +
                    "Options:\n" +
                    "1. Remove the platform suffix: --versions ($parts | drop | str join "-")\n" +
                    "2. Create a platforms manifest: services/($service)/platforms.nuon\n" +
                    "3. If this is a valid version name (not a platform suffix), use it as-is in your versions.nuon manifest")
            }
          }
        }
      }
    }
  }
  
  mut detected_platforms_from_versions = []
  if $has_platforms_manifest and ($versions | str length) > 0 {
    for v in ($versions | split row "," | each {|x| $x | str trim} | where ($it | str length) > 0) {
      let stripped = (try {
        strip-platform-suffix $v $platforms_manifest
      } catch {|err|
        error make { msg: $"Invalid version format '($v)': ($err.msg)" }
      })
      
      if ($stripped.platform_name | str length) > 0 {
        if not ($stripped.platform_name in $detected_platforms_from_versions) {
          $detected_platforms_from_versions = ($detected_platforms_from_versions | append $stripped.platform_name)
        }
        
        # Validate platform exists
        let platform_names = (get-platform-names $platforms_manifest)
        if not ($stripped.platform_name in $platform_names) {
          let available = ($platform_names | str join ", ")
          error make { msg: $"Version suffix platform '($stripped.platform_name)' not found in platforms manifest. Available: ($available)" }
        }
      }
    }
    
    # Check conflict with --platform flag
    if not ($detected_platforms_from_versions | is-empty) and ($platform | str length) > 0 {
      if not ($platform in $detected_platforms_from_versions) {
        let detected = ($detected_platforms_from_versions | str join ", ")
        error make { msg: $"--platform '($platform)' conflicts with detected platforms from --versions: ($detected)" }
      }
    }
  }
  
  # Multi-version build mode
  # See docs/guides/multi-version-builds.md for details
  if $all_versions_val or ($versions | str length) > 0 or $latest_only_val {
    if not $has_versions_manifest {
      error make { 
        msg: ($"Service '($service)' does not have a version manifest. Cannot build multiple versions.\n\n" +
              "Multi-version builds require a version manifest.\n" +
              "To fix:\n" +
              "1. Create services/($service)/versions.nuon\n" +
              "2. Define at least one version with a 'default' field\n" +
              "3. See docs/guides/multi-version-builds.md for examples")
      }
    }
    
    let filter_result = (filter-versions $versions_manifest $platforms_manifest --all=$all_versions_val --versions=$versions --latest-only=$latest_only_val)
    # Apply defaults to each version spec (filter-versions returns raw specs without defaults)
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
        ($platform | str length) == 0 or $item.platform == $platform
      } | where {|item|
        ($detected_platforms_from_filter | is-empty) or ($item.platform in $detected_platforms_from_filter)
      })
      
      if ($expanded_versions | is-empty) {
        print "No versions to build after platform filtering."
        return
      }
      
      print $"\n=== Building ($expanded_versions | length) version\(s\) of ($service) ==="
      print ""
      
      mut successes = []
      mut failures = []
      mut skipped = []
      
      for expanded_version in $expanded_versions {
        let build_label = $"($service):($expanded_version.name)-($expanded_version.platform)"
        print $"\n--- Building ($build_label) ---"
        
        let result = (try {
          let build_result = (build-single-version $service $expanded_version $push_val $latest_val $extra_tag $provenance_val $progress $info $meta $sha_cache $expanded_version.platform $default_platform $platforms_manifest $cache_bust $no_cache $no_auto_build_deps $push_deps $tag_deps)
          $sha_cache = $build_result.sha_cache  # Update cache for next build
          print $"OK: Successfully built ($build_label)"
          {success: true, label: $build_label}
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          {success: false, label: $build_label, error: $error_msg}
        })
        
        if $result.success {
          $successes = ($successes | append {label: $result.label, success: true})
        } else {
          $failures = ($failures | append {label: $result.label, success: false, error: $result.error})
          
          if $fail_fast {
            break
          }
        }
      }
      
      print-build-summary $successes $failures $skipped
      
      if ($failures | length) > 0 {
        exit 1
      }
      
      return
    } else {
      print $"\n=== Building ($versions_to_build | length) version\(s\) of ($service) ==="
      print ""
      
      mut successes = []
      mut failures = []
      mut skipped = []
      
      for version_spec in $versions_to_build {
        let build_label = $"($service):($version_spec.name)"
        print $"\n--- Building ($build_label) ---"
        
        let result = (try {
          let build_result = (build-single-version $service $version_spec $push_val $latest_val $extra_tag $provenance_val $progress $info $meta $sha_cache "" "" null $cache_bust $no_cache $no_auto_build_deps $push_deps $tag_deps)
          $sha_cache = $build_result.sha_cache  # Update cache for next build
          print $"OK: Successfully built ($build_label)"
          {success: true, label: $build_label}
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          {success: false, label: $build_label, error: $error_msg}
        })
        
        if $result.success {
          $successes = ($successes | append {label: $result.label, success: true})
        } else {
          $failures = ($failures | append {label: $result.label, success: false, error: $result.error})
          
          if $fail_fast {
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
  
  if not $has_versions_manifest {
    error make { 
      msg: ($"Service '($service)' does not have a version manifest. All services must have version manifests.\n\n" +
            "To fix:\n" +
            "1. Create services/($service)/versions.nuon\n" +
            "2. Define at least one version with a 'default' field\n" +
            "3. See docs/guides/multi-version-builds.md for examples")
    }
  }
  
  let version_resolved = (resolve-version-name $version $versions_manifest $platforms_manifest $version_suffix_info)
  
  # Get version spec
  let version_spec = (get-version-or-null $versions_manifest $version_resolved.base_name)
  
  if $version_spec == null {
    # Get available versions for helpful error message
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
      msg: ($"Version '($version_resolved.base_name)' not found in manifest for service '($service)'.\n\n" +
            $"Available versions: ($available_versions)\n" +
            "Options:\n" +
            $"1. Use one of the available versions: --version ($first_version)\n" +
            $"2. Add the version to services/($service)/versions.nuon\n" +
            "3. Check for typos in the version name")
    }
  }
  
  # Platform expansion if platforms manifest exists
  if $has_platforms_manifest {
    mut expanded_versions = (expand-version-to-platforms $version_spec $platforms_manifest $default_platform)
    
    # Apply filters: --platform flag, detected platform from --version suffix
    $expanded_versions = ($expanded_versions | where {|item|
      ($platform | str length) == 0 or $item.platform == $platform
    } | where {|item|
      ($version_resolved.detected_platform | str length) == 0 or $item.platform == $version_resolved.detected_platform
    })
    
    if ($expanded_versions | is-empty) {
      print "No versions to build after platform filtering."
      return
    }
    
    for expanded_version in $expanded_versions {
      let build_result = (build-single-version $service $expanded_version $push_val $latest_val $extra_tag $provenance_val $progress $info $meta $sha_cache $expanded_version.platform $default_platform $platforms_manifest $cache_bust $no_cache $no_auto_build_deps $push_deps $tag_deps)
      $sha_cache = $build_result.sha_cache  # Update cache for next build
    }
  } else {
    # Single-platform build (no platforms manifest)
    let build_result = (build-single-version $service $version_spec $push_val $latest_val $extra_tag $provenance_val $progress $info $meta $sha_cache "" "" null $cache_bust $no_cache $no_auto_build_deps $push_deps $tag_deps)
    $sha_cache = $build_result.sha_cache  # Update cache (though this is last build, cache update not needed)
  }
}

# Build all services in dependency order
def build-all-services [
  push_val: bool,
  latest_val: bool,
  extra_tag: string,
  provenance_val: bool,
  progress: string,
  info: record,
  meta: record,
  sha_cache: record,  # Cache for source SHA extraction (shared across services) - passed by value, updated via return
  all_versions: bool,
  latest_only: bool,
  platform: string,
  cache_bust_override: string,
  no_cache: bool,
  no_auto_build_deps: bool,
  push_deps: bool,
  tag_deps: bool,
  fail_fast: bool,
  show_build_order: bool,
  matrix_json: bool
] {
  use ./lib/services.nu [list-service-names]
  use ./lib/manifest.nu [check-versions-manifest-exists load-versions-manifest get-default-version]
  use ./lib/platforms.nu [check-platforms-manifest-exists load-platforms-manifest get-default-platform expand-version-to-platforms]
  use ./lib/matrix.nu [generate-multi-service-matrix]
  use ./lib/build-order.nu [build-dependency-graph topological-sort-dfs]
  use ./lib/build-ops.nu [load-service-config]
  
  # Discover all services
  let all_service_names = (list-service-names)
  
  if ($all_service_names | is-empty) {
    print "No services found."
    return
  }
  
  # Handle matrix JSON generation
  if $matrix_json {
    # Filter services to those with version manifests
    let services_with_manifests = ($all_service_names | where {|svc|
      check-versions-manifest-exists $svc
    })
    
    if ($services_with_manifests | is-empty) {
      print "No services with version manifests found."
      return
    }
    
    # Generate matrix for all services (respects version and platform flags)
    # Note: generate-multi-service-matrix generates all versions, so we need to filter
    let full_matrix = (generate-multi-service-matrix $services_with_manifests)
    
    # Filter matrix entries based on version flags
    mut filtered_entries = $full_matrix.include
    
    if $latest_only {
      # Filter to only latest versions
      $filtered_entries = ($filtered_entries | where {|entry|
        (try { $entry.latest } catch { false }) == true
      })
    } else if not $all_versions {
      # Filter to default versions only (if not --all-versions)
      # For each service, keep only entries with default version
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
    # else: --all-versions, keep all entries
    
    # Filter by platform if specified
    if ($platform | str length) > 0 {
      $filtered_entries = ($filtered_entries | where {|entry|
        $entry.platform == $platform
      })
    }
    
    # Return filtered matrix
    let filtered_matrix = {include: $filtered_entries}
    print ($filtered_matrix | to json)
    return
  }
  
  print $"=== Building All Services ==="
  let service_count = ($all_service_names | length | into string)
  print $"Found ($service_count) service\(s\)"
  print ""
  
  # Resolve versions and platforms for each service
  # Use reduce to avoid Nushell for loop scope bug
  let service_builds = ($all_service_names | reduce --fold [] {|item, acc|
    let service_name = $item
    
    # Check if service has versions manifest (required)
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
      
      # Resolve versions to build
      let versions_to_build = (if $all_versions {
        # Build all versions - apply defaults to each version spec
        $versions_manifest.versions | each {|v| apply-version-defaults $versions_manifest $v}
      } else if $latest_only {
        # Build only latest versions - apply defaults to each version spec
        $versions_manifest.versions | where {|v| try { $v.latest == true } catch { false }} | each {|v| apply-version-defaults $versions_manifest $v}
      } else {
        # Build default version only - use get-version-spec which applies defaults
        let default_version_name = (get-default-version $versions_manifest)
        let default_version_spec = (get-version-spec $versions_manifest $default_version_name)
        [$default_version_spec]
      })
      
      if ($versions_to_build | is-empty) {
        print $"WARNING: No versions to build for service '($service_name)'. Skipping."
        $acc
      } else {
        # Expand to platforms if multi-platform
        if $has_platforms and $platforms_manifest != null {
          let default_platform = (get-default-platform $platforms_manifest)
          
          # Expand each version to platforms
          let expanded = ($versions_to_build | reduce --fold [] {|ver_item, ver_acc|
            let platform_variants = (expand-version-to-platforms $ver_item $platforms_manifest $default_platform)
            $ver_acc | append $platform_variants
          })
          
          # Filter by --platform if specified
          let filtered_expanded = (if ($platform | str length) > 0 {
            $expanded | where {|v| $v.platform == $platform}
          } else {
            $expanded
          })
          
          if ($filtered_expanded | is-empty) {
            print $"WARNING: No platform variants to build for service '($service_name)'. Skipping."
            $acc
          } else {
            # Add to service_builds
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
          # Single-platform service
          if ($platform | str length) > 0 {
            # Platform specified but service has no platforms manifest - skip
            print $"WARNING: Service '($service_name)' has no platforms manifest but --platform specified. Skipping."
            $acc
          } else {
            # Add to service_builds
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
  # Use reduce to avoid Nushell for loop scope bug
  let graph_result = ($service_builds | reduce --fold {nodes: [], edges: []} {|item, acc|
    let service = $item.service
    let version_spec = $item.version_spec
    let plat = $item.platform
    let platforms_manifest = $item.platforms_manifest
    
    # For --show-build-order, handle errors gracefully
    let graph = (if $show_build_order {
      try {
        # Load service config
        let cfg = (load-service-config $service $version_spec $plat $platforms_manifest)
        # Build dependency graph for this service:version:platform
        build-dependency-graph $service $version_spec $cfg $plat $platforms_manifest false $info
      } catch {|err|
        # If we can't build the graph for this service, skip it but warn
        print $"WARNING: Could not build dependency graph for ($service):($version_spec.name): ($err.msg)"
        {nodes: [], edges: []}
      }
    } else {
      # Load service config
      let cfg = (load-service-config $service $version_spec $plat $platforms_manifest)
      # Build dependency graph for this service:version:platform
      build-dependency-graph $service $version_spec $cfg $plat $platforms_manifest false $info
    })
    
    # Merge nodes (deduplicate)
    let merged_nodes = ($graph.nodes | reduce --fold $acc.nodes {|node_item, node_acc|
      if not ($node_item in $node_acc) {
        $node_acc | append $node_item
      } else {
        $node_acc
      }
    })
    
    # Merge edges (deduplicate)
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
    
    # Also add the service itself as a node if not already present
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
  if $show_build_order {
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
  
  # Execute builds in topological order
  # Use reduce to avoid Nushell for loop scope bug
  # Include cache in accumulator to avoid mut variable capture issues
  let build_result = ($build_order | reduce --fold {built_nodes: [], successes: [], failures: [], skipped: [], cache: $sha_cache} {|item, acc|
    let node = $item
    
    # Check if already built (defensive check)
    if $node in $acc.built_nodes {
      $acc  # Return accumulator unchanged (includes cache)
    } else {
      # Parse node: service:version or service:version:platform
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
        
        # Check if this node is in our service_builds list (target service vs dependency)
        let is_target_service = ($service_builds | any {|svc_item|
          let item_node = (if ($svc_item.platform | str length) > 0 {
            $"($svc_item.service):($svc_item.version_spec.name):($svc_item.platform)"
          } else {
            $"($svc_item.service):($svc_item.version_spec.name)"
          })
          $item_node == $node
        })
        
        # Resolve version_spec for this node
        let node_version_spec = (resolve-dependency-version-spec $node $node_platform)
        
        # Check if dependency has platforms manifest
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
        
        # Determine flags for this build
        let node_push = (if $is_target_service { $push_val } else { $push_deps })
        let node_latest = (if $is_target_service {
          $latest_val
        } else {
          if $tag_deps { $latest_val } else { false }
        })
        let node_extra_tag = (if $is_target_service {
          $extra_tag
        } else {
          if $tag_deps { $extra_tag } else { "" }
        })
        
        # Re-detect info and meta for this build
        let node_info = (get-registry-info)
        let node_meta = (detect-build)
        
        # Build label for reporting
        let build_label = (if ($node_platform | str length) > 0 {
          $"($node_service):($node_version_spec.name)-($node_platform)"
        } else {
          $"($node_service):($node_version_spec.name)"
        })
        
        print $"\n--- Building ($build_label) ---"
        
        # Execute build (use cache from accumulator)
        let build_result = (try {
          # Always pass no_auto_build_deps=true because dependencies are handled by build order
          build-single-version $node_service $node_version_spec $node_push $node_latest $node_extra_tag $provenance_val $progress $node_info $node_meta $acc.cache $node_platform $node_default_platform $node_platforms_manifest $cache_bust_override $no_cache true $push_deps $tag_deps
        } catch {|err|
          let error_msg = (try { $err.msg } catch { "Unknown error" })
          print $"ERROR: Failed to build ($build_label)"
          print $"  Error: ($error_msg)"
          error make { msg: $error_msg }
        })
        let result = {success: true, label: $build_label}
        print $"OK: Successfully built ($build_label)"
        
        # Track result and update cache in accumulator
        let new_built_nodes = ($acc.built_nodes | append $node)
        
        if $result.success {
          {
            built_nodes: $new_built_nodes,
            successes: ($acc.successes | append {label: $result.label, success: true}),
            failures: $acc.failures,
            skipped: $acc.skipped,
            cache: $build_result.sha_cache  # Update cache in accumulator
          }
        } else {
          # If fail-fast, we'll break in the outer function
          # For now, just collect the failure
          
          # Mark dependents as skipped
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
          
          # Add dependents to built_nodes to prevent building them
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
            cache: $acc.cache  # Keep cache unchanged on failure
          }
        }
      }
    }
  })
  
  # Check if we should fail-fast and exit early
  # Note: We can't break from reduce, so we'll check after
  # For a proper fail-fast, we'd need to use a different approach
  # For now, continue-on-failure is the default behavior
  
  # Print summary
  print-build-summary $build_result.successes $build_result.failures $build_result.skipped
  
  # Exit with error if any failures
  if ($build_result.failures | length) > 0 {
    exit 1
  }
}

# Print machine-parseable build summary
def print-build-summary [
  successes: list,
  failures: list,
  skipped: list
] {
  let success_count = ($successes | length)
  let failure_count = ($failures | length)
  let skipped_count = ($skipped | length)
  let total = $success_count + $failure_count + $skipped_count
  
  # Calculate status
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

# Filter build order to exclude target service (dependencies only)
def filter-to-dependencies-only [
  build_order: list,
  target_node: string
] {
  $build_order | where {|node| $node != $target_node}
}

# Resolve dependency version_spec from node key
# Returns version_spec record
def resolve-dependency-version-spec [
  dep_node: string,
  dep_platform: string
] {
  # Parse node key: service:version or service:version:platform
  let parts = ($dep_node | split row ":")
  if ($parts | length) < 2 {
    error make { msg: $"Invalid dependency node format: '($dep_node)'. Expected 'service:version' or 'service:version:platform'" }
  }
  
  let dep_service = ($parts | get 0)
  let dep_version_name = ($parts | get 1)
  
  # Check if versions manifest exists
  if not (check-versions-manifest-exists $dep_service) {
    error make { msg: $"Dependency service '($dep_service)' does not have a version manifest" }
  }
  
  # Load versions manifest
  let dep_versions_manifest = (load-versions-manifest $dep_service)
  
  # Check if platforms manifest exists
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
  
  # Strip platform suffix if present
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
  
  # Resolve version name
  let version_resolved = (resolve-version-name $base_version_name $dep_versions_manifest $dep_platforms_manifest null)
  
  # Get version_spec from manifest
  let version_spec = (get-version-or-null $dep_versions_manifest $version_resolved.base_name)
  if $version_spec == null {
    error make { msg: $"Version '($version_resolved.base_name)' not found in manifest for dependency service '($dep_service)'" }
  }
  
  # Expand to platform if needed
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
def build-single-version [
  service: string,
  version_spec: record,
  push_val: bool,
  latest_val: bool,
  extra_tag: string,
  provenance_val: bool,
  progress: string,
  info: record,
  meta: record,
  sha_cache: record,  # Cache for source SHA extraction (shared across services) - passed by value, returned updated
  platform: string = "",
  default_platform: string = "",
  platforms: any = null,
  cache_bust_override: string = "",
  no_cache: bool = false,
  no_auto_build_deps: bool = false,
  push_deps: bool = false,
  tag_deps: bool = false
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
  
  if $meta.build_type == "skip" {
    print "No build triggered (no release tag and no dev/stage token)." 
    return
  }
  
  # Reject local sources in CI/production builds (must happen before SHA extraction)
  # Cache source_types for use in build arg generation and other tasks
  let cfg_sources = (try { $cfg.sources } catch { {} })
  let source_types = (if not ($cfg_sources | is-empty) {
    detect-all-source-types $cfg_sources
  } else {
    {}
  })
  
  if not ($cfg_sources | is-empty) {
    let local_sources = ($source_types | columns | where {|k| ($source_types | get $k) == "local"})
    if ($local_sources | length) > 0 and $meta.build_type != "local" {
      error make {
        msg: ($"Error: Local sources are not allowed in CI builds. Use git sources instead.\n" +
              $"Local sources found: [($local_sources | str join ', ')]")
      }
    }
  }
  
  # Validate after merge to catch dependencies in version overrides
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
  
  let is_local = ($meta.build_type == "local")
  let version_tag = $version_spec.name
  
  # Track cache updates in function scope
  mut current_cache = $sha_cache
  
  # Extract source SHAs before generating labels
  # Cache is shared across all services in build session
  # Filter to only git sources (skip local sources)
  let source_shas_result = (if (try { $cfg.sources } catch { {} } | is-empty) {
    {shas: {}, cache: $current_cache}  # Return cache unchanged
  } else {
    use ./lib/sources.nu [extract-source-shas]
    # Filter sources to only git sources (exclude local sources)
    let git_sources = (if not ($source_types | is-empty) {
      ($cfg_sources | columns | where {|k| ($source_types | get $k | default "git") == "git"} | reduce --fold {} {|k, acc|
        $acc | upsert $k ($cfg_sources | get $k)
      })
    } else {
      # If source_types not available, filter by checking for path field
      ($cfg_sources | columns | where {|k|
        let source = ($cfg_sources | get $k)
        not ("path" in ($source | columns))
      } | reduce --fold {} {|k, acc|
        $acc | upsert $k ($cfg_sources | get $k)
      })
    })
    
    # If all sources are local, skip SHA extraction entirely
    if ($git_sources | is-empty) {
      # All sources are local - return empty shas, merge local sources with empty SHAs
      let local_shas = ($cfg_sources | columns | reduce --fold {} {|k, acc|
        let sha_key = ($"($k | str upcase)_SHA")
        $acc | upsert $sha_key ""
      })
      {shas: $local_shas, cache: $current_cache}
    } else {
      # Extract SHAs for git sources only
      let git_shas_result = (extract-source-shas $git_sources $service $current_cache)
      # Merge with empty SHAs for local sources
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
  # Update cache for this function's scope
  $current_cache = ($current_cache | merge $source_shas_result.cache)

  # Generate labels with source SHAs
  let tags = (generate-tags $service $version_spec $is_local $info $current_platform $default_platform)
  let labels = (generate-labels $service $meta $cfg $source_shas $source_types)
  
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
  
  # Auto-build dependencies if enabled
  if not $no_auto_build_deps {
    # Build dependency graph
    let graph = (build-dependency-graph $service $version_spec $cfg $current_platform $platforms $is_local $info)
    
    # Perform topological sort
    let build_order = (topological-sort-dfs $graph)
    
    # Filter to dependencies only (exclude target service)
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
      
      # Loop through each dependency node
      for dep_node in $dep_build_order {
        # Parse dependency node to extract service, version, platform
        let dep_parts = ($dep_node | split row ":")
        let dep_service = ($dep_parts | get 0)
        let dep_version_name = ($dep_parts | get 1)
        let dep_platform = (if ($dep_parts | length) > 2 { $dep_parts | get 2 } else { "" })
        
        # Re-detect info and meta for dependency
        let dep_info = (get-registry-info)
        let dep_meta = (detect-build)
        
        # Add cache_bust_override to dep_meta if set
        if ($cache_bust_override | str length) > 0 {
          # Note: meta is read-only, we'll pass cache_bust_override separately
        }
        
        # Resolve dependency version_spec
        let dep_version_spec = (resolve-dependency-version-spec $dep_node $dep_platform)
        
        # Check if dependency has platforms manifest
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
        
        # Get dependency default platform
        let dep_default_platform = (if $dep_has_platforms {
          get-default-platform $dep_platforms_manifest
        } else {
          ""
        })
        
        # Determine dep_push, dep_latest, dep_extra_tag based on flags
        let dep_push = $push_deps
        let dep_latest = (if $tag_deps { $latest_val } else { false })
        let dep_extra_tag = (if $tag_deps { $extra_tag } else { "" })
        
        # Build dependency recursively (with no_auto_build_deps=true to prevent infinite recursion)
        let dep_label = (if ($dep_platform | str length) > 0 {
          $"($dep_service):($dep_version_spec.name)-($dep_platform)"
        } else {
          $"($dep_service):($dep_version_spec.name)"
        })
        
        try {
          let build_result = (build-single-version $dep_service $dep_version_spec $dep_push $dep_latest $dep_extra_tag $provenance_val $progress $dep_info $dep_meta $current_cache $dep_platform $dep_default_platform $dep_platforms_manifest $cache_bust_override $no_cache true $push_deps $tag_deps)
          $current_cache = $build_result.sha_cache  # Update cache for next dependency
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
  
  # Resolve dependencies (get image references for build args)
  # If auto-build is enabled, dependencies are already built, so this just gets the references
  let deps_resolved = (resolve-dependencies $cfg $version_tag $is_local $info $current_platform $platforms)
  if $is_local {
    for dep_image in ($deps_resolved | values) {
      print $"Loading dependency image '($dep_image)' into buildx builder..."
      let loaded = (load-image-into-builder $dep_image)
      if not $loaded {
        print $"Warning: Failed to load '($dep_image)' into buildx builder. Build may fail."
      }
    }
  }
  
  let tls_context = (prepare-tls-context $service $context $tls_meta.enabled $tls_meta.mode)
  
  # Prepare local sources context (copy local sources to build context)
  let repo_root = (get-repo-root)
  let local_source_paths = (if not ($cfg_sources | is-empty) {
    prepare-local-sources-context $service $context $cfg_sources $source_types $repo_root
  } else {
    {}
  })
  
  # Generate build args (includes source SHAs for potential Dockerfile use)
  # local_source_paths contains resolved paths (relative to context root) for local sources
  let build_args = (generate-build-args $version_tag $cfg $meta $deps_resolved $tls_meta $cache_bust_override $no_cache $source_shas $source_types $local_source_paths)
  
  build --context $context --dockerfile $dockerfile --platforms $meta.platforms --tags $tags --build-args $build_args --labels $labels --progress $progress $push_val $provenance_val $is_local
  
  cleanup-tls-context $context $tls_context
  
  # Return updated cache for caller
  {sha_cache: $current_cache}
}
