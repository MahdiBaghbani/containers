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

# write-manifest, read-manifest, and missing-manifest returns.

use ../../lib/build/cache.nu [write-manifest read-manifest]
use ../lib.nu [run-test]
use ./_fixtures.nu [make-roundtrip-service rm-tmp]

export def manifest-roundtrip-tests [verbose: bool] {
    [
        (run-test "write-manifest + read-manifest round-trip" {
            let fx = (make-roundtrip-service)
            let test_svc = $fx.test_svc
            let cache_dir = $fx.cache_dir

            let node_image_map = {
                nodes: {"svc:v1:prod": "sha256:aaa", "svc:v1:dev": "sha256:bbb"},
                images: {
                    "sha256:aaa": {refs: ["reg/svc:v1-prod"], owner_service: $test_svc},
                    "sha256:bbb": {refs: ["reg/svc:v1-dev"], owner_service: $test_svc}
                }
            }

            try {
                write-manifest $test_svc $node_image_map
            } catch {|err|
                rm-tmp $cache_dir
                error make {msg: $err.msg}
            }

            let manifest = (try {
                read-manifest $test_svc
            } catch {|err|
                rm-tmp $cache_dir
                error make {msg: $err.msg}
            })

            rm-tmp $cache_dir

            if $manifest == null {
                error make {msg: "read-manifest returned null after write-manifest"}
            }
            if $manifest.owner_service != $test_svc {
                error make {msg: $"owner_service mismatch: ($manifest.owner_service)"}
            }
            let nodes = $manifest.nodes
            if ($nodes | get "svc:v1:prod") != "sha256:aaa" {
                error make {msg: "node svc:v1:prod not found or wrong image_id"}
            }
            if ($nodes | get "svc:v1:dev") != "sha256:bbb" {
                error make {msg: "node svc:v1:dev not found or wrong image_id"}
            }
            let img = ($manifest.images | get "sha256:aaa")
            if $img.owner_service != $test_svc {
                error make {msg: $"image owner_service mismatch: ($img.owner_service)"}
            }
            true
        } $verbose)
        (run-test "read-manifest: missing manifest returns null" {
            let manifest = (read-manifest "__no-such-svc-xyzzy__")
            $manifest == null
        } $verbose)
    ]
}
