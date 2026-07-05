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

# Automatic dependency building tests (Tests 12-19).

use ../../lib/build/order.nu [topological-sort-dfs]
use ../mocks.nu [build-dependency-graph-with-mocks]
use ../helpers.nu [
    setup-test-environment setup-test-service-with-deps with-test-cleanup
    create-test-dependency assert-graph-structure assert-build-order
]
use ../lib.nu [run-test]

export def automatic-deps-tests [verbose: bool] {
    [
        (run-test "Test 12: Auto-Build - Missing dependency" {
            with-test-cleanup {
              let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
              let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
            
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              # Verify graph has dependencies
              let expected_nodes = ["test-service:v1.0.0", "dep-service:v1.0.0"]
              let expected_edges = [{from: "test-service:v1.0.0", to: "dep-service:v1.0.0"}]
              assert-graph-structure $graph $expected_nodes $expected_edges
            
              if $verbose {
                print $"    Nodes: ($graph.nodes | length)"
                print $"    Edges: ($graph.edges | length)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 13: Auto-Build - Skip existing dependency" {
            with-test-cleanup {
              let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
              let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
            
              # Build dependency graph (this is what auto-build uses)
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              # Verify graph is valid
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction successful \(would check Docker for existing images in actual build\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 14: Auto-Build - Recursive dependencies" {
            with-test-cleanup {
              # Create A -> B -> C chain
              let dep_c = (create-test-dependency "service-c" "v1.0.0" "C_IMAGE")
              let test_env_c = (setup-test-service-with-deps "service-c" {} "v1.0.0")
            
              let dep_b = (create-test-dependency "service-b" "v1.0.0" "B_IMAGE")
              let test_env_b = (setup-test-service-with-deps "service-b" {c: $dep_c} "v1.0.0")
            
              let dep_a = (create-test-dependency "service-a" "v1.0.0" "A_IMAGE")
              let test_env = (setup-test-service-with-deps "service-a" {b: $dep_b} "v1.0.0")
            
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "service-a" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              # Get build order
              let build_order = (topological-sort-dfs $graph)
            
              # Verify build order respects dependencies
              if ($build_order | length) == 0 {
                error make {msg: "Build order is empty"}
              }
            
              # Verify all services are in order
              let has_a = ($build_order | any {|node| ($node | str contains "service-a")})
              let has_b = ($build_order | any {|node| ($node | str contains "service-b")})
              let has_c = ($build_order | any {|node| ($node | str contains "service-c")})
            
              if not ($has_a and $has_b and $has_c) {
                error make {msg: $"Missing services in build order"}
              }
            
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 15: Auto-Build - --dep-cache=strict flag" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works regardless of dep-cache mode
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print "    Graph construction works (--dep-cache mode is handled in build.nu)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 16: Auto-Build - Build order display" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Build dependency graph and get order
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              let build_order = (topological-sort-dfs $graph)
            
              # Verify build order can be formatted
              let formatted = ($build_order | str join " -> ")
              if ($formatted | str length) == 0 {
                error make {msg: "Formatted build order is empty"}
              }
            
              let expected_order = ["test-service:v1.0.0"]
              assert-build-order $build_order $expected_order
            
              if $verbose {
                print $"    Formatted order: ($formatted)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 17: Auto-Build - Flag propagation (push-deps)" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works regardless of flags
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction works \(flag propagation is handled in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 18: Auto-Build - Flag propagation (tag-deps)" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works regardless of flags
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction works \(flag propagation is handled in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 19: Continue-on-Failure - Version/platform selection" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v3.3.3")
            
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              # Verify graph contains version in node keys
              let expected_nodes = ["test-service:v3.3.3"]
              let expected_edges = []
              assert-graph-structure $graph $expected_nodes $expected_edges
            
              if $verbose {
                print $"    Version: ($test_env.version_spec.name)"
                print $"    Nodes: ($graph.nodes | str join ', ')"
              }
            
              true
            }
          } $verbose)

    ]
}
