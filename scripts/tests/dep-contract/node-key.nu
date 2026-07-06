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

# resolve-dep-node and graph-order contract tests.

use ../../lib/build/dependencies.nu [resolve-dep-node]
use ../../lib/build/order.nu [topological-sort-dfs]
use ../mocks.nu [
    build-dependency-graph-with-mocks
    set-mock-platform-behavior
]
use ../helpers.nu [setup-test-service-with-deps with-test-cleanup]
use ../lib.nu [run-test]
use ./_fixtures.nu [create-temp-service-platforms remove-temp-service]

export def node-key-tests [verbose: bool] {
    [
        (run-test "resolve-dep-node: explicit platform-suffix version produces correct node key" {
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

            if $verbose {
                print $"    node_key:   ($result.node_key)"
                print $"    tag format: ($tag_format)"
            }
            true
        } $verbose)
    ,
        (run-test "resolve-dep-node: inherited platform propagates into node key" {
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

            if $verbose {
                print $"    node_key: ($result.node_key)"
            }
            true
        } $verbose)
    ,
        (run-test "graph order: dep_key != service - node uses dep_config.service" {
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

                if $verbose {
                    print $"    graph.nodes:  ($graph.nodes | str join ', ')"
                    print $"    build_order:  ($build_order | str join ' -> ')"
                }
                true
            }
        } $verbose)
    ]
}
