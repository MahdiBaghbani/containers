#!/usr/bin/env nu

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

# CI helper: Load cached dependency tarballs for a consumer service
# Called by build-service.yml to load images from dependency service caches

use ./lib/dep-cache.nu [read-manifest get-image-tarball-path]
use ./lib/ci-deps.nu [get-direct-dependency-services]

# Get Docker image ID for a given image reference
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

export def main [
    --service: string  # Consumer service name to load dependency tarballs for
] {
    if ($service | str length) == 0 {
        print --stderr "ERROR: --service is required"
        exit 1
    }

    print $"Loading dependency images for service: ($service)"

    # Get all dependency services
    let dep_services = (get-direct-dependency-services $service)

    if ($dep_services | is-empty) {
        print "No dependencies found for this service."
        return
    }

    print $"Found ($dep_services | length) dependency service\(s\): ($dep_services | str join ', ')"

    mut total_loaded = 0
    mut total_skipped = 0
    mut total_failed = 0
    mut missing_manifests = []

    # Load tarballs from each dependency service's cache
    for dep_service in $dep_services {
        print ""
        print $"--- Processing dependency: ($dep_service) ---"

        let manifest = (read-manifest $dep_service)

        if $manifest == null {
            print $"WARNING: No manifest found for '($dep_service)'"
            $missing_manifests = ($missing_manifests | append $dep_service)
            continue
        }

        let image_ids = ($manifest.images | columns)

        if ($image_ids | is-empty) {
            print $"No images in manifest for '($dep_service)'"
            continue
        }

        for image_id in $image_ids {
            let tarball_path = (get-image-tarball-path $dep_service $image_id)

            if not ($tarball_path | path exists) {
                print $"WARNING: Tarball not found: ($tarball_path | path basename)"
                $total_failed = $total_failed + 1
                continue
            }

            # Check if image already loaded
            let existing = (get-docker-image-id $image_id)
            if ($existing | str length) > 0 {
                print $"Skipping ($image_id | str substring 0..16)... \(already loaded\)"
                $total_skipped = $total_skipped + 1
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
                $total_loaded = $total_loaded + 1
            } else {
                print $"ERROR: Failed to load ($image_id | str substring 0..16)...: ($load_result.error)"
                $total_failed = $total_failed + 1
            }
        }
    }

    print ""
    print "=== Dependency Load Summary ==="
    print $"Loaded: ($total_loaded)"
    print $"Skipped \(already present\): ($total_skipped)"
    print $"Failed: ($total_failed)"

    if not ($missing_manifests | is-empty) {
        print $"Missing manifests: ($missing_manifests | str join ', ')"
        print "  (These dependencies will be built if needed)"
    }

    if $total_failed > 0 {
        print ""
        print "WARNING: Some images failed to load. Build will proceed but may need to rebuild dependencies."
    }
}
