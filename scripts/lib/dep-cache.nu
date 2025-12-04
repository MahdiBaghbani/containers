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

# Dep-cache module: single source of truth for CI dependency reuse
# See docs/concepts/build-system.md for dep-cache mode documentation

use ./manifest.nu [check-versions-manifest-exists load-versions-manifest]
use ./platforms.nu [check-platforms-manifest-exists load-platforms-manifest get-platform-names]
use ./pull.nu [compute-canonical-image-ref]
use ./registry/registry-info.nu [get-registry-info]

# Cache directory constants
const CACHE_BASE_DIR = "/tmp/docker-images"
const MANIFEST_FILENAME = "manifest.nuon"
const TARBALL_EXTENSION = ".tar.zst"
const MANIFEST_SCHEMA_VERSION = 1

# Valid dep-cache modes
# - off: disable hash-based skip; always build deps when auto-build enabled
# - soft: hash-based skip + auto-build on missing/stale (default for CI)
# - strict: hash-based validation, fail on missing/stale (no auto-build)
export const DEP_CACHE_MODES = ["off", "soft", "strict"]

# Get the cache directory for an owner service
export def get-owner-cache-dir [owner_service: string] {
    $"($CACHE_BASE_DIR)/($owner_service)"
}

# Get the tarball path for a specific image ID
export def get-image-tarball-path [owner_service: string, image_id: string] {
    let cache_dir = (get-owner-cache-dir $owner_service)
    # Docker image IDs include "sha256:" prefix - strip it for filename
    let safe_id = ($image_id | str replace "sha256:" "")
    $"($cache_dir)/($safe_id)($TARBALL_EXTENSION)"
}

# Get the manifest path for an owner service
export def get-manifest-path [owner_service: string] {
    let cache_dir = (get-owner-cache-dir $owner_service)
    $"($cache_dir)/($MANIFEST_FILENAME)"
}

# Get the cache key for GitHub Actions cache
# Format: images-{owner_service}-{ref}-{sha}
export def get-owner-cache-key [owner_service: string, ref: string, sha: string] {
    $"images-($owner_service)-($ref)-($sha)"
}

# Parse and validate dep-cache mode from CLI flag
# Returns validated mode or errors on invalid input
export def parse-dep-cache-mode [raw: string, is_local: bool] {
    # Empty string means no explicit mode - use defaults
    if ($raw | str trim | is-empty) {
        # Local builds default to "off" (always build, rely on Docker layer cache)
        # CI builds default to "soft" (hash-based skip + auto-build)
        if $is_local { "off" } else { "soft" }
    } else {
        let mode = ($raw | str trim | str downcase)
        if not ($mode in $DEP_CACHE_MODES) {
            let valid_list = ($DEP_CACHE_MODES | str join ", ")
            error make {
                msg: $"Invalid dep-cache mode '($mode)'. Valid modes: ($valid_list)"
            }
        }
        $mode
    }
}

# Get all dependency nodes for a service (all versions and platforms)
# Returns list of records: {service, version, platform, node_key, owner_service}
export def get-dep-nodes-for-service [
    service: string,
    registry_info: record,
    is_local: bool
] {
    # Check if service has versions manifest
    if not (check-versions-manifest-exists $service) {
        return []
    }

    let versions_manifest = (load-versions-manifest $service)
    let versions = (try { $versions_manifest.versions } catch { [] })

    if ($versions | is-empty) {
        return []
    }

    # Check if service has platforms
    let has_platforms = (check-platforms-manifest-exists $service)
    let platforms_manifest = (if $has_platforms {
        try { load-platforms-manifest $service } catch { null }
    } else {
        null
    })

    # Enumerate all version+platform combinations
    let nodes = ($versions | reduce --fold [] {|version_spec, acc|
        let version_name = $version_spec.name

        if $has_platforms and $platforms_manifest != null {
            # Multi-platform service: enumerate all platforms
            let platforms = (try { $platforms_manifest.platforms } catch { [] })
            let platform_nodes = ($platforms | reduce --fold [] {|platform_spec, inner_acc|
                let platform_name = $platform_spec.name
                let node_key = $"($service):($version_name):($platform_name)"
                $inner_acc | append {
                    service: $service,
                    version: $version_name,
                    platform: $platform_name,
                    node_key: $node_key,
                    owner_service: $service
                }
            })
            $acc | append $platform_nodes
        } else {
            # Single-platform service
            let node_key = $"($service):($version_name)"
            $acc | append {
                service: $service,
                version: $version_name,
                platform: "",
                node_key: $node_key,
                owner_service: $service
            }
        }
    })

    $nodes
}

# Get Docker image ID for a given image reference
# Returns the full SHA256 image ID or empty string if image doesn't exist
def get-docker-image-id [image_ref: string] {
    try {
        let result = (^docker image inspect $image_ref --format "{{.Id}}" | complete)
        if $result.exit_code == 0 {
            $result.stdout | str trim
        } else {
            ""
        }
    } catch {
        ""
    }
}

# Compute mapping from nodes to Docker image IDs
# Returns: {
#   nodes: {node_key: image_id},
#   images: {image_id: {refs: [ref1, ref2], owner_service: string}}
# }
export def compute-node-image-map [
    nodes: list,
    registry_info: record,
    is_local: bool
] {
    # Process each node to get its image ref and image ID
    let result = ($nodes | reduce --fold {nodes: {}, images: {}} {|node, acc|
        let node_key = $node.node_key
        let owner_service = $node.owner_service

        # Compute canonical image reference
        let image_ref = (compute-canonical-image-ref $node_key $registry_info $is_local)

        # Get Docker image ID
        let image_id = (get-docker-image-id $image_ref)

        if ($image_id | str length) == 0 {
            # Image doesn't exist - record empty mapping
            let updated_nodes = ($acc.nodes | upsert $node_key "")
            {nodes: $updated_nodes, images: $acc.images}
        } else {
            # Update node -> image_id mapping
            let updated_nodes = ($acc.nodes | upsert $node_key $image_id)

            # Update image_id -> refs mapping (aggregate refs for dedup)
            let existing_image = (try { $acc.images | get $image_id } catch { null })
            let updated_images = (if $existing_image == null {
                $acc.images | upsert $image_id {
                    refs: [$image_ref],
                    owner_service: $owner_service
                }
            } else {
                # Add ref to existing image entry if not already present
                let existing_refs = $existing_image.refs
                let new_refs = (if $image_ref in $existing_refs {
                    $existing_refs
                } else {
                    $existing_refs | append $image_ref
                })
                $acc.images | upsert $image_id {
                    refs: $new_refs,
                    owner_service: $owner_service
                }
            })

            {nodes: $updated_nodes, images: $updated_images}
        }
    })

    $result
}

# Write dep-cache manifest for an owner service
export def write-manifest [owner_service: string, node_image_map: record] {
    let manifest_path = (get-manifest-path $owner_service)
    let cache_dir = (get-owner-cache-dir $owner_service)

    # Ensure cache directory exists
    if not ($cache_dir | path exists) {
        mkdir $cache_dir
    }

    let manifest = {
        schema_version: $MANIFEST_SCHEMA_VERSION,
        owner_service: $owner_service,
        nodes: $node_image_map.nodes,
        images: $node_image_map.images
    }

    $manifest | to nuon | save -f $manifest_path
}

# Read dep-cache manifest for an owner service
# Returns manifest record or null if not found
export def read-manifest [owner_service: string] {
    let manifest_path = (get-manifest-path $owner_service)

    if not ($manifest_path | path exists) {
        return null
    }

    try {
        open $manifest_path
    } catch {
        null
    }
}

# Save tarballs for all images owned by a service (SHA-deduplicated)
# Called after successful build to produce per-image .tar.zst files
export def save-owner-tarballs [
    owner_service: string,
    registry_info: record,
    is_local: bool
] {
    # Get all nodes for this service
    let nodes = (get-dep-nodes-for-service $owner_service $registry_info $is_local)

    if ($nodes | is-empty) {
        print $"No nodes found for service '($owner_service)', skipping tarball save"
        return
    }

    # Compute node -> image ID mapping
    let node_image_map = (compute-node-image-map $nodes $registry_info $is_local)

    # Get unique image IDs (skip empty ones - missing images)
    let image_ids = ($node_image_map.images | columns)

    if ($image_ids | is-empty) {
        print $"No images found for service '($owner_service)', skipping tarball save"
        return
    }

    let cache_dir = (get-owner-cache-dir $owner_service)

    # Clear and recreate cache directory to remove stale tarballs from previous runs
    if ($cache_dir | path exists) {
        rm -rf $cache_dir
    }
    mkdir $cache_dir

    print $"=== Saving ($image_ids | length) image\(s\) for ($owner_service) ==="

    # Save each unique image ID as a tarball
    for image_id in $image_ids {
        let image_info = ($node_image_map.images | get $image_id)
        let refs = $image_info.refs
        let tarball_path = (get-image-tarball-path $owner_service $image_id)

        # Skip if tarball already exists (dedup within build session)
        if ($tarball_path | path exists) {
            print $"Skipping ($image_id | str substring 0..16)... (tarball exists)"
            continue
        }

        # Save image with all its refs/tags
        let refs_str = ($refs | str join " ")
        print $"Saving ($image_id | str substring 0..16)... with ($refs | length) ref\(s\)"

        let save_result = (try {
            # docker save outputs to stdout, pipe through zstd
            let cmd_result = (^docker save ...$refs | ^zstd -T0 -3 -o $tarball_path | complete)
            if $cmd_result.exit_code == 0 {
                {success: true, error: ""}
            } else {
                {success: false, error: (try { $cmd_result.stderr } catch { "Unknown error" })}
            }
        } catch {|err|
            {success: false, error: (try { $err.msg } catch { "Command failed" })}
        })

        if $save_result.success {
            print $"OK: Saved ($tarball_path | path basename)"
        } else {
            print $"ERROR: Failed to save ($image_id | str substring 0..16)...: ($save_result.error)"
        }
    }

    # Write manifest
    write-manifest $owner_service $node_image_map
    print $"Manifest written to ($cache_dir)/($MANIFEST_FILENAME)"
}

# Load tarballs from cache for an owner service
# Returns record with load metrics
export def load-owner-tarballs [owner_service: string] {
    let manifest = (read-manifest $owner_service)

    if $manifest == null {
        print $"No manifest found for '($owner_service)', skipping load"
        return {loaded: 0, skipped: 0, failed: 0}
    }

    let image_ids = ($manifest.images | columns)

    if ($image_ids | is-empty) {
        return {loaded: 0, skipped: 0, failed: 0}
    }

    print $"=== Loading ($image_ids | length) image\(s\) for ($owner_service) ==="

    mut loaded = 0
    mut skipped = 0
    mut failed = 0

    for image_id in $image_ids {
        let tarball_path = (get-image-tarball-path $owner_service $image_id)

        if not ($tarball_path | path exists) {
            print $"WARNING: Tarball not found for ($image_id | str substring 0..16)..."
            $failed = $failed + 1
            continue
        }

        # Check if image already loaded (skip dedup)
        let existing = (get-docker-image-id $image_id)
        if ($existing | str length) > 0 {
            print $"Skipping ($image_id | str substring 0..16)... \(already loaded\)"
            $skipped = $skipped + 1
            continue
        }

        # Load tarball
        let load_result = (try {
            let cmd_result = (^zstd -d -c $tarball_path | ^docker load | complete)
            if $cmd_result.exit_code == 0 {
                {success: true, error: ""}
            } else {
                {success: false, error: (try { $cmd_result.stderr } catch { "Unknown error" })}
            }
        } catch {|err|
            {success: false, error: (try { $err.msg } catch { "Command failed" })}
        })

        if $load_result.success {
            print $"OK: Loaded ($image_id | str substring 0..16)..."
            $loaded = $loaded + 1
        } else {
            print $"ERROR: Failed to load ($image_id | str substring 0..16)...: ($load_result.error)"
            $failed = $failed + 1
        }
    }

    {loaded: $loaded, skipped: $skipped, failed: $failed}
}
