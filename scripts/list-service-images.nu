#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# CLI wrapper to list canonical image references for a service
# Used by GitHub Actions to determine which images to save to cache

use ./lib/manifest.nu [check-versions-manifest-exists load-versions-manifest]
use ./lib/platforms.nu [check-platforms-manifest-exists load-platforms-manifest]
use ./lib/pull.nu [compute-canonical-image-ref]
use ./lib/registry/registry-info.nu [get-registry-info]

# List all canonical image references for a service
# Outputs one image reference per line for shell consumption
def main [
  --service: string  # Service name to list images for
] {
  if ($service | str length) == 0 {
    print --stderr "ERROR: --service is required"
    exit 1
  }

  # Check if service has versions manifest
  if not (check-versions-manifest-exists $service) {
    print --stderr $"ERROR: Service '($service)' does not have a versions manifest"
    exit 1
  }

  # Load versions manifest
  let versions_manifest = (load-versions-manifest $service)
  let versions = (try { $versions_manifest.versions } catch { [] })

  if ($versions | is-empty) {
    print --stderr $"WARNING: Service '($service)' has no versions defined"
    exit 0
  }

  # Check if service has platforms
  let has_platforms = (check-platforms-manifest-exists $service)
  let platforms_manifest = (if $has_platforms {
    try { load-platforms-manifest $service } catch { null }
  } else {
    null
  })

  # Get registry info for CI environment detection
  let registry_info = (get-registry-info)
  let is_local = ($registry_info.ci_platform == "local")

  # Enumerate all version+platform combinations
  mut image_refs = []

  for version_spec in $versions {
    let version_name = $version_spec.name

    if $has_platforms and $platforms_manifest != null {
      # Multi-platform service: enumerate all platforms
      let platforms = (try { $platforms_manifest.platforms } catch { [] })
      for platform_spec in $platforms {
        let platform_name = $platform_spec.name
        let node = $"($service):($version_name):($platform_name)"
        let ref = (compute-canonical-image-ref $node $registry_info $is_local)
        $image_refs = ($image_refs | append $ref)
      }
    } else {
      # Single-platform service
      let node = $"($service):($version_name)"
      let ref = (compute-canonical-image-ref $node $registry_info $is_local)
      $image_refs = ($image_refs | append $ref)
    }
  }

  # Deduplicate and print one per line
  let unique_refs = ($image_refs | uniq)
  for ref in $unique_refs {
    print $ref
  }
}
