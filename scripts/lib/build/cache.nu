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

use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]
use ../platforms/core.nu [check-platforms-manifest-exists load-platforms-manifest get-platform-names]
use ../registries/info.nu [get-registry-info]

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
