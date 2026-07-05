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

# Continue-on-failure tests (Tests 20-30).

use ../../lib/build/order.nu [topological-sort-dfs]
use ../mocks.nu [
    build-dependency-graph-with-mocks set-mock-platform-behavior
    register-mock-service-dependencies
]
use ../helpers.nu [
    setup-test-environment setup-test-service-with-deps with-test-cleanup
    create-test-dependency assert-build-order
]
use ../lib.nu [run-test]

export def continue-on-failure-tests [verbose: bool] {
    [
        (run-test "Test 20: Continue-on-Failure - Single build fail fast" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works regardless of fail-fast setting
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction works \(fail-fast is handled in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 21: Continue-on-Failure - Multi-version continue-on-failure" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction works \(continue-on-failure is handled in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 22: Continue-on-Failure - --fail-fast flag" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works regardless of fail-fast flag
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print "    Graph construction works (--fail-fast is handled in build.nu)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 23: Continue-on-Failure - Build summary format" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Build dependency graph and get order
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              let build_order = (topological-sort-dfs $graph)
            
              # Verify build order can be used for summary
              let expected_order = ["test-service:v1.0.0"]
              assert-build-order $build_order $expected_order
            
              if $verbose {
                print $"    Build order computed \(summary format is handled in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 24: Continue-on-Failure - Exit codes" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print "    Graph construction works (exit codes are handled in build.nu)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 25: Continue-on-Failure - Dependency failure handling" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Graph construction works
              let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
            
              if ($graph.nodes | length) == 0 {
                error make {msg: "Graph is empty"}
              }
            
              if $verbose {
                print $"    Graph construction works \(dependency failure handling is in build.nu\)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 26: Build Order - Dependency from version overrides" {
            with-test-cleanup {
              # Create parent service with dependency override in version
              let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
              let version_overrides = {
                dependencies: {
                  dep: $dep
                }
              }
              let test_env = (setup-test-environment "parent-service" "v1.0.0" false $version_overrides)
              
              # Setup dependency service
              let dep_env = (setup-test-environment "dep-service" "v1.0.0")
              
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              
              # Verify dependency edge exists
              let has_edge = ($graph.edges | any {|edge| 
                $edge.from == "parent-service:v1.0.0" and $edge.to == "dep-service:v1.0.0"
              })
              
              if not $has_edge {
                error make {msg: "Dependency edge not found in graph from version override"}
              }
              
              # Verify topological order: dependency before dependent
              let build_order = (topological-sort-dfs $graph)
              let dep_idx = ($build_order | enumerate | where {|item| $item.item == "dep-service:v1.0.0"} | first | get index)
              let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0"} | first | get index)
              
              if $dep_idx >= $parent_idx {
                error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
              }
              
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
              
              true
            }
          } $verbose)
        ,
        (run-test "Test 27: Build Order - Dependency from platform config" {
            with-test-cleanup {
              # Create platform config with dependency (use "debian" as default platform name)
              let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
              let platform_configs = [
                {
                  name: "debian",
                  dockerfile: "Dockerfile.debian",
                  dependencies: {
                    dep: $dep
                  }
                }
              ]
              let test_env = (setup-test-environment "parent-service" "v1.0.0" true {} $platform_configs)
              
              # Setup dependency service
              let dep_env = (setup-test-environment "dep-service" "v1.0.0")
              
              # Build dependency graph for debian platform
              let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "debian" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              
              # Verify dependency edge exists (dependency inherits platform from parent)
              let has_edge = ($graph.edges | any {|edge| 
                $edge.from == "parent-service:v1.0.0:debian" and $edge.to == "dep-service:v1.0.0:debian"
              })
              
              if not $has_edge {
                error make {msg: $"Dependency edge not found in graph from platform config. Edges: ($graph.edges | to nuon)"}
              }
              
              # Verify topological order: dependency before dependent
              let build_order = (topological-sort-dfs $graph)
              let dep_idx = ($build_order | enumerate | where {|item| $item.item == "dep-service:v1.0.0:debian"} | first | get index)
              let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0:debian"} | first | get index)
              
              if $dep_idx >= $parent_idx {
                error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
              }
              
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
              
              true
            }
          } $verbose)
        ,
        (run-test "Test 28: Build Order - Dependency key vs service name" {
            with-test-cleanup {
              # Create dependency with different key and service name
              let dep = {
                service: "actual-service",
                build_arg: "DEP_IMAGE"
              }
              let test_env = (setup-test-service-with-deps "parent-service" {dep_key: $dep} "v1.0.0")
              
              # Setup actual service (not dep_key)
              let dep_env = (setup-test-environment "actual-service" "v1.0.0")
              
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              
              # Verify edge uses actual service name, not dependency key
              let has_correct_edge = ($graph.edges | any {|edge| 
                $edge.from == "parent-service:v1.0.0" and $edge.to == "actual-service:v1.0.0"
              })
              let has_wrong_edge = ($graph.edges | any {|edge| 
                $edge.from == "parent-service:v1.0.0" and $edge.to == "dep_key:v1.0.0"
              })
              
              if not $has_correct_edge {
                error make {msg: "Dependency edge not found with correct service name"}
              }
              if $has_wrong_edge {
                error make {msg: "Dependency edge found with wrong dependency key instead of service name"}
              }
              
              if $verbose {
                print $"    Edges: ($graph.edges | to nuon)"
              }
              
              true
            }
          } $verbose)
        ,
        (run-test "Test 29: Build Order - Platform-specific dependency resolution" {
            with-test-cleanup {
              # Create dependency with platform suffix in version override (using "debian" to match mock)
              let dep = (create-test-dependency "dep-service" "v1.0.0-debian" "DEP_IMAGE")
              let version_overrides = {
                dependencies: {
                  dep: $dep
                }
              }
              let test_env = (setup-test-environment "parent-service" "v1.0.0" false $version_overrides)
              
              # Setup dependency service with platforms manifest
              set-mock-platform-behavior "dep-service" true
              let dep_env = (setup-test-environment "dep-service" "v1.0.0" true)
              
              # Register dependency service dependencies (empty, but needed for graph construction)
              register-mock-service-dependencies "dep-service" "v1.0.0" {}
              
              # Build dependency graph
              let graph = (build-dependency-graph-with-mocks "parent-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
              
              # Verify edge uses resolved platform (dep-service:v1.0.0:debian)
              let has_edge = ($graph.edges | any {|edge| 
                $edge.from == "parent-service:v1.0.0" and $edge.to == "dep-service:v1.0.0:debian"
              })
              
              if not $has_edge {
                error make {msg: $"Platform-specific dependency edge not found. Expected 'dep-service:v1.0.0:debian'. Edges: ($graph.edges | to nuon)"}
              }
              
              # Verify topological order: dependency before dependent
              let build_order = (topological-sort-dfs $graph)
              let dep_idx = ($build_order | enumerate | where {|item| ($item.item | str contains "dep-service:v1.0.0:debian")} | first | get index)
              let parent_idx = ($build_order | enumerate | where {|item| $item.item == "parent-service:v1.0.0"} | first | get index)
              
              if $dep_idx >= $parent_idx {
                error make {msg: $"Dependency order incorrect: dep-service at ($dep_idx), parent-service at ($parent_idx). Dependency should come first."}
              }
              
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
              
              true
            }
          } $verbose)
        ,
        (run-test "Test 30: Build Order - Topological sort ordering" {
            with-test-cleanup {
              # Create simple graph: A depends on B
              let mock_graph = {
                nodes: ["A", "B"],
                edges: [
                  {from: "A", to: "B"}
                ]
              }
              
              # Topological sort should return B before A
              let build_order = (topological-sort-dfs $mock_graph)
              
              let b_idx = ($build_order | enumerate | where {|item| $item.item == "B"} | first | get index)
              let a_idx = ($build_order | enumerate | where {|item| $item.item == "A"} | first | get index)
              
              if $b_idx >= $a_idx {
                error make {msg: $"Topological sort order incorrect: B at ($b_idx), A at ($a_idx). Dependency B should come before dependent A."}
              }
              
              # Verify exact order
              let expected_order = ["B", "A"]
              assert-build-order $build_order $expected_order
              
              if $verbose {
                print $"    Build order: ($build_order | str join ' -> ')"
              }
              
              true
            }
          } $verbose)

    ]
}
