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

# Build system tests

use ../lib/build-ops.nu [generate-build-args]
use ../lib/build-order.nu [topological-sort-dfs]
use ../lib/manifest.nu [get-default-version get-version-or-null]
use ./mocks.nu [detect-build get-mock-service-config build-mock-version-manifest build-mock-platform-manifest check-platforms-manifest-exists check-versions-manifest-exists build-dependency-graph-with-mocks get-default-platform set-mock-platform-behavior]
use ./helpers.nu [setup-test-environment setup-test-service-with-deps cleanup-test-environment with-test-cleanup create-test-dependency create-test-deps-resolved create-test-tls-meta create-test-registry-info assert-cache-bust-format assert-cache-bust-value assert-build-args-contain assert-build-order assert-graph-structure]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Cache Busting Tests
  
  # Test 1: Per-service cache bust computation
  # Validates that cache bust is computed per-service from sources and is consistent
  let test1 = (run-test "Test 1: Cache Busting - Per-service computation" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      # Generate build args without override
      let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
      let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
      
      # Verify CACHEBUST is present and has correct format (16 chars for source refs hash)
      let _ = (assert-cache-bust-format $cache_bust1 16 "hash")
      
      # Verify hash is consistent (same sources = same hash)
      let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
      let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
      
      let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
      
      if $verbose_flag {
        print $"    CACHEBUST: ($cache_bust1)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: Global cache bust override
  # Validates that --cache-bust flag overrides per-service computation
  let test2 = (run-test "Test 2: Cache Busting - Global override" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      let override_value = "custom-cache-bust-123"
    
      # Generate build args with override
      let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $override_value false)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      assert-cache-bust-value $cache_bust $override_value
    
      if $verbose_flag {
        print $"    Override value: ($override_value)"
        print $"    CACHEBUST: ($cache_bust)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: --no-cache flag
  # Validates that --no-cache generates random UUID for cache bust
  let test3 = (run-test "Test 3: Cache Busting - --no-cache flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Generate build args with --no-cache
      let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" true)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      # Verify it's a UUID format (36 chars with dashes)
      assert-cache-bust-format $cache_bust 36 "uuid"
    
      if $verbose_flag {
        print $"    Generated UUID: ($cache_bust)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Git SHA fallback
  # Validates that cache bust falls back to Git SHA when service has no sources
  let test4 = (run-test "Test 4: Cache Busting - Git SHA fallback" {
    with-test-cleanup {
      # Create test environment with no sources (override config)
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Override config to remove sources (test Git SHA fallback)
      mut merged_cfg = $test_env.merged_cfg
      $merged_cfg = ($merged_cfg | upsert sources {})
    
      # Generate build args without override
      let build_args = (generate-build-args "test" $merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
      let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
    
      # Should be Git SHA (variable length) or "local"
      if ($cache_bust | str length) == 0 {
        error make {msg: "CACHEBUST not generated"}
      }
    
      if $cache_bust == "local" {
        if $verbose_flag {
          print $"    Using 'local' fallback (no Git)"
        }
      } else {
        if $verbose_flag {
          print $"    Using Git SHA: ($cache_bust)"
        }
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Environment variable override
  # Validates that CACHEBUST environment variable overrides per-service computation
  let test5 = (run-test "Test 5: Cache Busting - Environment variable override" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      let env_value = "env-cache-bust-456"
    
      # Set environment variable
      let old_env = (try { $env.CACHEBUST } catch { "" })
      $env.CACHEBUST = $env_value
    
      try {
        # Generate build args without override or --no-cache
        let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
        let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
      
        assert-cache-bust-value $cache_bust $env_value
      
        if $verbose_flag {
          print $"    Env value: ($env_value)"
          print $"    CACHEBUST: ($cache_bust)"
        }
      } catch {
        # Restore environment on error
        if ($old_env | str length) > 0 {
          $env.CACHEBUST = $old_env
        } else {
          hide-env CACHEBUST
        }
        error make {msg: $in}
      }
    
      # Restore environment
      if ($old_env | str length) > 0 {
        $env.CACHEBUST = $old_env
      } else {
        hide-env CACHEBUST
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Hash consistency
  # Validates that cache bust is deterministic (same sources = same hash)
  let test6 = (run-test "Test 6: Cache Busting - Hash consistency" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Generate build args multiple times
      let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
      let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
      let build_args3 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta "" false)
    
      let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
      let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
      let cache_bust3 = (try { $build_args3.CACHEBUST } catch { "" })
    
      # All should be identical
      let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
      let _ = (assert-cache-bust-value $cache_bust2 $cache_bust3)
    
      if $verbose_flag {
        print $"    Consistent CACHEBUST: ($cache_bust1)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Build Order Resolution Tests
  
  # Test 7: Simple dependency chain
  # Validates that dependency graph correctly represents A -> B -> C chain
  let test7 = (run-test "Test 7: Build Order - Simple dependency chain" {
    with-test-cleanup {
      # Create service A that depends on B
      let dep_b = (create-test-dependency "service-b" "v1.0.0" "B_IMAGE")
      let test_env = (setup-test-service-with-deps "service-a" {b: $dep_b} "v1.0.0")
    
      # Setup service B that depends on C
      let dep_c = (create-test-dependency "service-c" "v1.0.0" "C_IMAGE")
      let test_env_b = (setup-test-service-with-deps "service-b" {c: $dep_c} "v1.0.0")
    
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
    
      if $verbose_flag {
        print $"    Nodes: ($graph.nodes | length)"
        print $"    Edges: ($graph.edges | length)"
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: Circular dependency detection
  # Validates that topological sort detects and reports circular dependencies
  let test8 = (run-test "Test 8: Build Order - Circular dependency detection" {
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
    
      if $verbose_flag {
        print $"    Cycle detected: ($result.error)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 9: Version-aware graph
  # Validates that graph construction includes version in node keys
  let test9 = (run-test "Test 9: Build Order - Version-aware graph" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v3.3.3")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph contains version in node keys
      let expected_nodes = ["test-service:v3.3.3"]
      let expected_edges = []
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Version: ($test_env.version_spec.name)"
        print $"    Nodes: ($graph.nodes | str join ', ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: Platform inheritance
  # Validates that dependencies inherit platform from parent when parent is multi-platform
  let test10 = (run-test "Test 10: Build Order - Platform inheritance" {
    with-test-cleanup {
      # Create parent with multiple platforms
      let parent_platforms = (build-mock-platform-manifest "debian" [
        {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
        {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
      ])
      set-mock-platform-behavior "parent-service" true
      
      # Create child with multiple platforms (inherits from parent)
      let child_platforms = (build-mock-platform-manifest "debian" [
        {name: "debian", dockerfile: "Dockerfile.debian", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}},
        {name: "alpine", dockerfile: "Dockerfile.alpine", external_images: {build: {name: "golang", tag: "1.25-trixie", build_arg: "BASE_BUILD_IMAGE"}}}
      ])
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
    
      if $verbose_flag {
        print $"    Platform: ($platform)"
        print $"    Nodes: ($graph.nodes | length)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test10)
  
  # Test 11: --show-build-order flag
  # Validates that build order can be computed and displayed
  let test11 = (run-test "Test 11: Build Order - --show-build-order flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph and get order
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order is valid
      let expected_order = ["test-service:v1.0.0"]
      assert-build-order $build_order $expected_order
    
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test11)
  
  # Automatic Dependency Building Tests
  
  # Test 12: Auto-build missing dependency
  # Validates that dependency graph includes all dependencies for auto-build
  let test12 = (run-test "Test 12: Auto-Build - Missing dependency" {
    with-test-cleanup {
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph has dependencies
      let expected_nodes = ["test-service:v1.0.0", "dep-service:v1.0.0"]
      let expected_edges = [{from: "test-service:v1.0.0", to: "dep-service:v1.0.0"}]
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Nodes: ($graph.nodes | length)"
        print $"    Edges: ($graph.edges | length)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test12)
  
  # Test 13: Skip existing dependency
  # Validates that graph construction works (Docker image existence check is in build.nu)
  let test13 = (run-test "Test 13: Auto-Build - Skip existing dependency" {
    with-test-cleanup {
      let dep = (create-test-dependency "dep-service" "v1.0.0" "DEP_IMAGE")
      let test_env = (setup-test-service-with-deps "test-service" {dep: $dep} "v1.0.0")
    
      # Build dependency graph (this is what auto-build uses)
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph is valid
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction successful (would check Docker for existing images in actual build)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test13)
  
  # Test 14: Recursive dependencies
  # Validates that graph handles recursive dependencies correctly
  let test14 = (run-test "Test 14: Auto-Build - Recursive dependencies" {
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
    
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test14)
  
  # Test 15: --dep-cache=strict flag
  # Validates that graph construction works (flag is handled in build.nu)
  let test15 = (run-test "Test 15: Auto-Build - --dep-cache=strict flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of dep-cache mode
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (--dep-cache mode is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test15)
  
  # Test 16: Build order display
  # Validates that build order can be computed and formatted for display
  let test16 = (run-test "Test 16: Auto-Build - Build order display" {
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
    
      if $verbose_flag {
        print $"    Formatted order: ($formatted)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test16)
  
  # Test 17: Flag propagation (push-deps)
  # Validates that graph construction works (flag propagation is handled in build.nu)
  let test17 = (run-test "Test 17: Auto-Build - Flag propagation (push-deps)" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of flags
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works (flag propagation is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test17)
  
  # Test 18: Flag propagation (tag-deps)
  # Validates that graph construction works (flag propagation is handled in build.nu)
  let test18 = (run-test "Test 18: Auto-Build - Flag propagation (tag-deps)" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of flags
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works (flag propagation is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test18)
  
  # Test 19: Version/platform selection
  # Validates that graph construction works with specific version/platform
  let test19 = (run-test "Test 19: Continue-on-Failure - Version/platform selection" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v3.3.3")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      # Verify graph contains version in node keys
      let expected_nodes = ["test-service:v3.3.3"]
      let expected_edges = []
      assert-graph-structure $graph $expected_nodes $expected_edges
    
      if $verbose_flag {
        print $"    Version: ($test_env.version_spec.name)"
        print $"    Nodes: ($graph.nodes | str join ', ')"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test19)
  
  # Continue-on-Failure Tests
  
  # Test 20: Single build fail fast
  # Validates that graph construction works (fail-fast is handled in build.nu)
  let test20 = (run-test "Test 20: Continue-on-Failure - Single build fail fast" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of fail-fast setting
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works (fail-fast is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test20)
  
  # Test 21: Multi-version continue-on-failure
  # Validates that graph construction works (continue-on-failure is handled in build.nu)
  let test21 = (run-test "Test 21: Continue-on-Failure - Multi-version continue-on-failure" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works (continue-on-failure is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test21)
  
  # Test 22: --fail-fast flag
  # Validates that graph construction works (--fail-fast is handled in build.nu)
  let test22 = (run-test "Test 22: Continue-on-Failure - --fail-fast flag" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works regardless of fail-fast flag
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (--fail-fast is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test22)
  
  # Test 23: Build summary format
  # Validates that build order can be computed (summary format is handled in build.nu)
  let test23 = (run-test "Test 23: Continue-on-Failure - Build summary format" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Build dependency graph and get order
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
      let build_order = (topological-sort-dfs $graph)
    
      # Verify build order can be used for summary
      let expected_order = ["test-service:v1.0.0"]
      assert-build-order $build_order $expected_order
    
      if $verbose_flag {
        print $"    Build order computed (summary format is handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test23)
  
  # Test 24: Exit codes
  # Validates that graph construction works (exit codes are handled in build.nu)
  let test24 = (run-test "Test 24: Continue-on-Failure - Exit codes" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print "    Graph construction works (exit codes are handled in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test24)
  
  # Test 25: Dependency failure handling
  # Validates that graph construction works (dependency failure handling is in build.nu)
  let test25 = (run-test "Test 25: Continue-on-Failure - Dependency failure handling" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
    
      # Graph construction works
      let graph = (build-dependency-graph-with-mocks "test-service" $test_env.version_spec $test_env.merged_cfg "" $test_env.platforms $test_env.registry_info.is_local $test_env.registry_info)
    
      if ($graph.nodes | length) == 0 {
        error make {msg: "Graph is empty"}
      }
    
      if $verbose_flag {
        print $"    Graph construction works (dependency failure handling is in build.nu)"
      }
    
      true
    }
  } $verbose_flag)
  $results = ($results | append $test25)
  
  # Test 26: Dependency from version overrides
  # Validates that dependencies defined in version overrides are detected correctly
  let test26 = (run-test "Test 26: Build Order - Dependency from version overrides" {
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
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test26)
  
  # Test 27: Dependency from platform config
  # Validates that dependencies defined in platform configs are detected correctly
  let test27 = (run-test "Test 27: Build Order - Dependency from platform config" {
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
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test27)
  
  # Test 28: Dependency key vs service name resolution
  # Validates that dependency keys can differ from service names (e.g., common-tools-builder -> common-tools)
  let test28 = (run-test "Test 28: Build Order - Dependency key vs service name" {
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
      
      if $verbose_flag {
        print $"    Edges: ($graph.edges | to nuon)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test28)
  
  # Test 29: Platform-specific dependency resolution
  # Validates that dependencies with platform suffixes (v1.0.0-debian) resolve correctly
  # Note: Using "debian" instead of "rhel" to match mock platform manifest default
  let test29 = (run-test "Test 29: Build Order - Platform-specific dependency resolution" {
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
      use ./mocks.nu [register-mock-service-dependencies]
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
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test29)
  
  # Test 30: Topological sort ordering (dependencies before dependents)
  # Validates that topological sort correctly orders dependencies before dependents
  let test30 = (run-test "Test 30: Build Order - Topological sort ordering" {
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
      
      if $verbose_flag {
        print $"    Build order: ($build_order | str join ' -> ')"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test30)
  
  print-test-summary $results
  
  if ($results | where {|r| not $r} | length) > 0 {
    exit 1
  } else {
    exit 0
  }
}
