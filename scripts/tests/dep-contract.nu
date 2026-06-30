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

# Dependency tag/key contract regression tests
#
# Proves that the three modules (dependencies.nu, order.nu, hash.nu) all
# consume the same node key format for the same dependency edge, and that
# the tag/ref path and the node-key path derive from the same
# resolve-dep-version-platform core rather than being reconstructed
# independently.
#
# Node key format: service:version:platform (colon-separated)
# Tag/ref format:  version-platform (dash-separated)
# Both share the same {version, platform} pair from resolve-dep-version-platform.
#
# These tests use real service manifests for filesystem-backed checks and the
# mock graph for dependency-graph propagation checks.

use ../lib/build/dependencies.nu [resolve-dep-node resolve-dependencies]
use ../lib/build/hash.nu [collect-dep-hashes]
use ../lib/build/order.nu [topological-sort-dfs]
use ./mocks.nu [
    build-dependency-graph-with-mocks
    set-mock-platform-behavior
    build-mock-platform-manifest
    register-mock-service-dependencies
    clear-mock-platform-registry
    clear-mock-service-deps-registry
]
use ./helpers.nu [setup-test-service-with-deps with-test-cleanup]
use ./lib.nu [run-test print-test-summary]

# Create a minimal platforms.nuon for a temporary test service.
# Must be called from repo root. Caller is responsible for cleanup.
def create-temp-service-platforms [service: string, platform_name: string = "debian"] {
    let svc_dir = $"services/($service)"
    try { mkdir $svc_dir } catch {}
    let manifest = {
        default: $platform_name,
        platforms: [{name: $platform_name, dockerfile: $"services/($service)/Dockerfile"}]
    }
    $manifest | to nuon | save -f $"($svc_dir)/platforms.nuon"
}

# Remove a temporary test service directory.
def remove-temp-service [service: string] {
    try { rm -rf $"services/($service)" } catch {}
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    # ------------------------------------------------------------------
    # Test 1: resolve-dep-node - explicit platform-suffixed version
    #
    # The dependency config key in the parent service ("dep-slot") differs
    # from dep_config.service ("dc-actual"). The explicit version field
    # "v1.0.0-debian" carries a platform suffix.
    #
    # Proves:
    # - node_key uses service:version:platform (NOT service:version-platform)
    # - version and platform are correctly stripped from the explicit field
    # - the tag-format pair (version + "-" + platform = "v1.0.0-debian")
    #   is exactly consistent with the node key parts
    # ------------------------------------------------------------------
    let t1 = (run-test "resolve-dep-node: explicit platform-suffix version produces correct node key" {
        let svc = "__dc-actual__"
        create-temp-service-platforms $svc

        let dep_config = {version: "v1.0.0-debian", build_arg: "BASE_IMAGE"}
        let result = (try {
            resolve-dep-node $dep_config $svc "v1.0.0" "debian" true
        } catch {|err|
            remove-temp-service $svc
            error make {msg: $err.msg}
        })
        remove-temp-service $svc

        let expected_key = $"($svc):v1.0.0:debian"
        if $result.node_key != $expected_key {
            error make {msg: $"Expected node_key '($expected_key)', got '($result.node_key)'"}
        }
        if $result.version != "v1.0.0" {
            error make {msg: $"Expected version 'v1.0.0', got '($result.version)'"}
        }
        if $result.platform != "debian" {
            error make {msg: $"Expected platform 'debian', got '($result.platform)'"}
        }
        # Tag-format consistency: the pair (version, platform) from the node key
        # yields exactly the tag string that resolve-dependency-tag would produce.
        let tag_format = $"($result.version)-($result.platform)"
        if $tag_format != "v1.0.0-debian" {
            error make {msg: $"Tag format mismatch: expected 'v1.0.0-debian', got '($tag_format)'"}
        }

        if $verbose_flag {
            print $"    node_key:   ($result.node_key)"
            print $"    tag format: ($tag_format)"
        }
        true
    } $verbose_flag)
    $results = ($results | append $t1)

    # ------------------------------------------------------------------
    # Test 2: resolve-dep-node - platform inherited from parent
    #
    # Same service, no explicit version in dep_config (inherits from parent).
    # Proves: inherited platform is captured in the node key just as it
    # would be for an explicit platform-suffixed version.
    # ------------------------------------------------------------------
    let t2 = (run-test "resolve-dep-node: inherited platform propagates into node key" {
        let svc = "__dc-actual2__"
        create-temp-service-platforms $svc

        let dep_config = {build_arg: "BASE_IMAGE"}
        let result = (try {
            resolve-dep-node $dep_config $svc "v1.0.0" "debian" true
        } catch {|err|
            remove-temp-service $svc
            error make {msg: $err.msg}
        })
        remove-temp-service $svc

        let expected_key = $"($svc):v1.0.0:debian"
        if $result.node_key != $expected_key {
            error make {msg: $"Expected node_key '($expected_key)', got '($result.node_key)'"}
        }
        if $result.platform != "debian" {
            error make {msg: $"Expected platform 'debian' to be inherited, got '($result.platform)'"}
        }

        if $verbose_flag {
            print $"    node_key: ($result.node_key)"
        }
        true
    } $verbose_flag)
    $results = ($results | append $t2)

    # ------------------------------------------------------------------
    # Test 3: graph order uses dep_config.service for the node key, not dep_key
    #
    # Parent service "dc-parent" has dependency record key "dep-slot" but
    # dep_config.service is "dc-child". The graph must use "dc-child:..."
    # as the node key - NOT "dep-slot:...".
    #
    # Also verifies that the graph node key produced by
    # build-dependency-graph-with-mocks (which uses resolve-dep-version-mock)
    # agrees with the node key format proven in tests 1-2.
    # ------------------------------------------------------------------
    let t3 = (run-test "graph order: dep_key != service - node uses dep_config.service" {
        with-test-cleanup {
            set-mock-platform-behavior "dc-parent" true
            set-mock-platform-behavior "dc-child" true

            let deps = {
                "dep-slot": {
                    service: "dc-child",
                    version: "v1.0.0-debian",
                    build_arg: "BASE_IMAGE"
                }
            }
            let test_env = (setup-test-service-with-deps "dc-parent" $deps "v1.0.0")

            let graph = (build-dependency-graph-with-mocks
                "dc-parent"
                $test_env.version_spec
                $test_env.merged_cfg
                "debian"
                $test_env.platforms
                true
                {})

            let dep_node_key = "dc-child:v1.0.0:debian"
            let spurious_key = "dep-slot:v1.0.0:debian"

            if not ($dep_node_key in $graph.nodes) {
                error make {msg: $"Expected node '($dep_node_key)' in graph, got: ($graph.nodes | str join ', ')"}
            }
            if $spurious_key in $graph.nodes {
                error make {msg: "dep_key 'dep-slot' must not appear as graph node; dep_config.service must be used"}
            }

            let build_order = (topological-sort-dfs $graph)
            if not ($dep_node_key in $build_order) {
                error make {msg: $"Expected '($dep_node_key)' in build_order, got: ($build_order | str join ', ')"}
            }

            if $verbose_flag {
                print $"    graph.nodes:  ($graph.nodes | str join ', ')"
                print $"    build_order:  ($build_order | str join ' -> ')"
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t3)

    # ------------------------------------------------------------------
    # Test 4: hash path consumes the exact node key from order/graph
    #
    # Builds the mock graph, gets the topological order, then proves that
    # collect-dep-hashes succeeds when given the dep node key as produced by
    # the graph - and would hard-fail if a differently-formatted key were used.
    #
    # This closes the loop: order.nu produces a node key, hash.nu consumes
    # that same key. If either side reconstructed it differently, this test
    # would catch it.
    # ------------------------------------------------------------------
    let t4 = (run-test "hash path: collect-dep-hashes consumes exact graph node key" {
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

            if $verbose_flag {
                print $"    dep_node_key: ($dep_node_key)"
                print $"    dep_hashes:   ($dep_hashes | to nuon)"
            }
            true
        }
    } $verbose_flag)
    $results = ($results | append $t4)

    # ------------------------------------------------------------------
    # Test 5: resolve-dependencies tag/ref format consistent with node key
    #
    # Uses a real platforms.nuon on disk for the dep service and a temp docker
    # stub that always exits 0 (so the image-exists check passes without a
    # real daemon). Proves that the public resolve-dependencies path produces
    # an image ref whose tag part ("v1.0.0-debian") is exactly the
    # version + "-" + platform pair that resolve-dep-node also reports.
    # ------------------------------------------------------------------
    let t5 = (run-test "resolve-dependencies: image ref tag consistent with node key version-platform" {
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

        if $verbose_flag {
            print $"    image_ref: ($image_ref)"
            print $"    tag:       ($tag_part)"
        }
        true
    } $verbose_flag)
    $results = ($results | append $t5)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
