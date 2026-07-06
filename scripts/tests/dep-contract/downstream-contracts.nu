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

# Hash path and resolve-dependencies downstream contract tests.

use ../../lib/build/dependencies.nu [resolve-dependencies]
use ../../lib/build/hash.nu [collect-dep-hashes]
use ../../lib/build/order.nu [topological-sort-dfs]
use ../mocks.nu [
    build-dependency-graph-with-mocks
    set-mock-platform-behavior
]
use ../helpers.nu [setup-test-service-with-deps with-test-cleanup]
use ../lib.nu [run-test]
use ./_fixtures.nu [create-temp-service-platforms remove-temp-service]

export def downstream-contracts-tests [verbose: bool] {
    [
        (run-test "hash path: collect-dep-hashes consumes exact graph node key" {
            with-test-cleanup {
                set-mock-platform-behavior "dc-hp" true
                set-mock-platform-behavior "dc-hd" true

                let deps = {
                    "dep-slot": {
                        service: "dc-hd",
                        version: "v1.0.0-debian",
                        build_arg: "BASE_IMAGE"
                    }
                }
                let test_env = (setup-test-service-with-deps "dc-hp" $deps "v1.0.0")

                let graph = (build-dependency-graph-with-mocks
                    "dc-hp"
                    $test_env.version_spec
                    $test_env.merged_cfg
                    "debian"
                    $test_env.platforms
                    true
                    {})

                let build_order = (topological-sort-dfs $graph)

                let dep_node_key = "dc-hd:v1.0.0:debian"
                let parent_node  = "dc-hp:v1.0.0:debian"

                if not ($dep_node_key in $build_order) {
                    error make {msg: $"dep node '($dep_node_key)' missing from build_order: ($build_order | str join ', ')"}
                }

                # Simulate dep hashed first (correct topological order)
                let computed_hashes = {$dep_node_key: "abc123defdep"}

                # collect-dep-hashes must find and return the dep hash using the
                # exact node key from the graph - not a re-derived variant
                let dep_hashes = (collect-dep-hashes $parent_node [$dep_node_key] $computed_hashes $build_order)
                if ($dep_hashes | get $dep_node_key) != "abc123defdep" {
                    error make {msg: $"collect-dep-hashes did not find hash for '($dep_node_key)'"}
                }

                # Sanity: a tag-format key ("dc-hd:v1.0.0-debian") is a different
                # string from the node-key format ("dc-hd:v1.0.0:debian"). If the
                # hash graph accidentally used the tag format, the hash lookup
                # would return an empty record (key absent from computed_hashes).
                let wrong_key = "dc-hd:v1.0.0-debian"
                let wrong_hashes = (collect-dep-hashes $parent_node [$wrong_key] $computed_hashes $build_order)
                if not ($wrong_hashes | is-empty) {
                    error make {msg: $"Tag-format key '($wrong_key)' should not resolve to a hash; got: ($wrong_hashes | to nuon)"}
                }

                if $verbose {
                    print $"    dep_node_key: ($dep_node_key)"
                    print $"    dep_hashes:   ($dep_hashes | to nuon)"
                }
                true
            }
        } $verbose)
    ,
        (run-test "resolve-dependencies: image ref tag consistent with node key version-platform" {
            let svc = "__dc-resolv__"
            create-temp-service-platforms $svc

            let stub_dir = (^mktemp -d | str trim)
            "#!/bin/sh\nexit 0" | save -f $"($stub_dir)/docker"
            ^chmod +x $"($stub_dir)/docker"

            let result = (try {
                $env.PATH = ([$stub_dir] | append $env.PATH)
                let service_config = {
                    dependencies: {
                        "dep-slot": {
                            service: $svc,
                            version: "v1.0.0-debian",
                            build_arg: "BASE_IMAGE"
                        }
                    }
                }
                let registry_info = {ci_platform: "local", is_local: true}
                resolve-dependencies $service_config "v1.0.0" true $registry_info "debian"
            } catch {|err|
                remove-temp-service $svc
                try { rm -rf $stub_dir } catch {}
                error make {msg: $err.msg}
            })

            remove-temp-service $svc
            try { rm -rf $stub_dir } catch {}

            if not ("BASE_IMAGE" in ($result | columns)) {
                error make {msg: $"Expected 'BASE_IMAGE' key in resolved deps, got: ($result | to nuon)"}
            }
            let image_ref = ($result | get "BASE_IMAGE")
            # For is_local=true, construct-image-ref returns "service:tag"
            # Tag is "v1.0.0-debian" = version-platform, consistent with the
            # node key format "svc:v1.0.0:debian" (same version/platform pair)
            let expected_suffix = $"($svc):v1.0.0-debian"
            if not ($image_ref | str ends-with $expected_suffix) {
                error make {msg: $"Expected image ref ending '($expected_suffix)', got '($image_ref)'"}
            }

            # Verify the version-platform tag matches the node key parts
            # node_key = "svc:v1.0.0:debian" -> parts [svc, v1.0.0, debian]
            # tag = "v1.0.0-debian" = parts[1] + "-" + parts[2]
            let tag_part = ($image_ref | split row ":" | last)
            let expected_tag = "v1.0.0-debian"
            if $tag_part != $expected_tag {
                error make {msg: $"Expected tag '($expected_tag)', got '($tag_part)'"}
            }

            if $verbose {
                print $"    image_ref: ($image_ref)"
                print $"    tag:       ($tag_part)"
            }
            true
        } $verbose)
    ]
}
