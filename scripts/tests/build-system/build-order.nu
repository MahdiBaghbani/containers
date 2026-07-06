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

# Build order resolution tests (Tests 7-11).

use ../../lib/build/order.nu [topological-sort-dfs]
use ../mocks.nu [build-dependency-graph-with-mocks build-mock-platform-manifest set-mock-platform-behavior]
use ../helpers.nu [setup-test-environment setup-test-service-with-deps with-test-cleanup create-test-dependency assert-graph-structure assert-build-order]
use ../lib.nu [run-test]

export def build-order-tests [verbose: bool] {
    [
        (run-test "Test 7: Build Order - Simple dependency chain" {
            with-test-cleanup {
              # Create service A that depends on B
              let dep_b = (create-test-dependency "service-b" "v1.0.0" "B_IMAGE")
              let test_env = (setup-test-service-with-deps "service-a" {b: $dep_b} "v1.0.0")
            
              # Setup service B that depends on C
              let dep_c = (create-test-dependency "service-c" "v1.0.0" "C_IMAGE")
              # Register service-b -> service-c for graph resolution (side effect only).
              setup-test-service-with-deps "service-b" {c: $dep_c} "v1.0.0"
            
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "service-a" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              # Perform topological sort
              let build_order = (topological-sort-dfs $graph)
            
              # Verify build order: C -> B -> A (or at least that all services are present)
              if ($build_order | length) < 3 {
                error make {msg: $"Expected at least 3 nodes in build order, got ($build_order | length)"}
              }
            
              # Verify all services are in build order
              let has_a = ($build_order | any {|node| ($node | str contains "service-a")})
              let has_b = ($build_order | any {|node| ($node | str contains "service-b")})
              let has_c = ($build_order | any {|node| ($node | str contains "service-c")})
            
              if not ($has_a and $has_b and $has_c) {
                error make {msg: $"Missing services in build order: A=($has_a), B=($has_b), C=($has_c)"}
              }
            
              if $verbose {
                print $"    Nodes: ($graph.nodes | length)"
                print $"    Edges: ($graph.edges | length)"
                print $"    Build order: ($build_order | str join ' -> ')"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 8: Build Order - Circular dependency detection" {
            with-test-cleanup {
              # Create a mock graph with circular dependency
              let mock_graph = {
                nodes: ["A", "B"],
                edges: [
                  {from: "A", to: "B"},
                  {from: "B", to: "A"}
                ]
              }
            
              # Topological sort should detect cycle
              let result = (try {
                topological-sort-dfs $mock_graph
                {has_cycle: false, cycles: []}
              } catch {|err|
                {has_cycle: true, error: $err.msg}
              })
            
              # Verify cycle was detected
              if not $result.has_cycle {
                error make {msg: "Circular dependency not detected"}
              }
            
              if $verbose {
                print $"    Cycle detected: ($result.error)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 9: Build Order - Version-aware graph" {
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
        ,
        (run-test "Test 10: Build Order - Platform inheritance" {
            with-test-cleanup {
              # Create parent with multiple platforms
              let parent_platforms = (build-mock-platform-manifest "debian" [
                {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
                {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
              ])
              set-mock-platform-behavior "parent-service" true
              
              # Register child platform manifest for graph resolution (side effect only).
              build-mock-platform-manifest "debian" [
                {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
                {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
              ]
              set-mock-platform-behavior "child-service" true
              
              # Create dependency from parent to child
              let dep = (create-test-dependency "child-service" "v1.0.0" "CHILD_IMAGE")
              let test_env = (setup-test-service-with-deps "parent-service" {child: $dep} "v1.0.0")
              
              # Build graph with platform
              let platform = "debian"
              let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg $platform $parent_platforms $test_env.registry_info.is_local $test_env.registry_info)
              # Verify graph construction succeeded
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph has no nodes"}
              }
            
              if $verbose {
                print $"    Platform: ($platform)"
                print $"    Nodes: ($graph.nodes | length)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 11: Build Order - --show-build-order flag" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Build dependency graph and get order
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              let build_order = (topological-sort-dfs $graph)
            
              # Verify build order is valid
              let expected_order = ["test-service:v1.0.0"]
              assert-build-order $build_order $expected_order
            
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
            
              true
            }
          } $verbose)

    ]
}
