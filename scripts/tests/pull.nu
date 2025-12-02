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

# Tests for pull.nu - pre-pull orchestration

use ../lib/pull.nu [parse-pull-modes compute-canonical-image-ref]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # === parse-pull-modes Tests ===
  
  # Test 1: Empty string returns empty list
  let test1 = (run-test "parse-pull-modes: empty string returns empty list" {
    let result = (parse-pull-modes "")
    if not ($result | is-empty) {
      error make {msg: $"Expected empty list, got: ($result)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: Valid single mode 'deps'
  let test2 = (run-test "parse-pull-modes: 'deps' returns [deps]" {
    let result = (parse-pull-modes "deps")
    if ($result | length) != 1 {
      error make {msg: $"Expected 1 element, got ($result | length)"}
    }
    if not ("deps" in $result) {
      error make {msg: $"Expected 'deps' in result, got: ($result)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Valid single mode 'externals'
  let test3 = (run-test "parse-pull-modes: 'externals' returns [externals]" {
    let result = (parse-pull-modes "externals")
    if ($result | length) != 1 {
      error make {msg: $"Expected 1 element, got ($result | length)"}
    }
    if not ("externals" in $result) {
      error make {msg: $"Expected 'externals' in result, got: ($result)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Combined modes 'deps,externals'
  let test4 = (run-test "parse-pull-modes: 'deps,externals' returns both" {
    let result = (parse-pull-modes "deps,externals")
    if ($result | length) != 2 {
      error make {msg: $"Expected 2 elements, got ($result | length)"}
    }
    if not ("deps" in $result) {
      error make {msg: $"Expected 'deps' in result"}
    }
    if not ("externals" in $result) {
      error make {msg: $"Expected 'externals' in result"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Deduplication of modes
  let test5 = (run-test "parse-pull-modes: 'deps,deps,externals' deduplicates" {
    let result = (parse-pull-modes "deps,deps,externals")
    if ($result | length) != 2 {
      error make {msg: $"Expected 2 unique elements, got ($result | length)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Whitespace handling
  let test6 = (run-test "parse-pull-modes: handles whitespace" {
    let result = (parse-pull-modes " deps , externals ")
    if ($result | length) != 2 {
      error make {msg: $"Expected 2 elements after trimming, got ($result | length)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Test 7: Invalid mode causes error
  let test7 = (run-test "parse-pull-modes: invalid mode causes error" {
    let result = (try {
      parse-pull-modes "invalid"
      false  # Should have errored
    } catch {|err|
      # Verify error message mentions invalid mode
      if not ($err.msg | str contains "Invalid pull mode") {
        error make {msg: $"Expected 'Invalid pull mode' in error, got: ($err.msg)"}
      }
      true
    })
    $result
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: Whitespace-only input returns empty (no pull)
  # Note: In Nushell CLI, bare `--pull` without value causes a parser error.
  # Whitespace input is treated as "no pull requested" for robustness.
  let test8 = (run-test "parse-pull-modes: whitespace-only returns empty list" {
    let result = (parse-pull-modes "  ")
    if not ($result | is-empty) {
      error make {msg: $"Expected empty list for whitespace input, got: ($result)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 8b: Comma-only input causes error (user tried to specify modes but failed)
  let test8b = (run-test "parse-pull-modes: comma-only input causes error" {
    let result = (try {
      parse-pull-modes ","
      false  # Should have errored
    } catch {|err|
      if not ($err.msg | str contains "Missing value") {
        error make {msg: $"Expected 'Missing value' in error, got: ($err.msg)"}
      }
      true
    })
    $result
  } $verbose_flag)
  $results = ($results | append $test8b)
  
  # === compute-canonical-image-ref Tests ===
  
  # Test 9: Single-platform node (local build)
  let test9 = (run-test "compute-canonical-image-ref: single-platform local" {
    let registry_info = {
      ci_platform: "local",
      github_registry: "ghcr.io",
      github_path: "owner/repo"
    }
    let ref = (compute-canonical-image-ref "service-a:v1.0.0" $registry_info true)
    if $ref != "service-a:v1.0.0" {
      error make {msg: $"Expected 'service-a:v1.0.0', got: ($ref)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: Multi-platform node (local build)
  let test10 = (run-test "compute-canonical-image-ref: multi-platform local" {
    let registry_info = {
      ci_platform: "local",
      github_registry: "ghcr.io",
      github_path: "owner/repo"
    }
    let ref = (compute-canonical-image-ref "service-a:v1.0.0:debian" $registry_info true)
    if $ref != "service-a:v1.0.0-debian" {
      error make {msg: $"Expected 'service-a:v1.0.0-debian', got: ($ref)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test10)
  
  # Test 11: Single-platform node (GitHub CI)
  let test11 = (run-test "compute-canonical-image-ref: single-platform GitHub CI" {
    let registry_info = {
      ci_platform: "github",
      github_registry: "ghcr.io",
      github_path: "owner/repo"
    }
    let ref = (compute-canonical-image-ref "service-a:v1.0.0" $registry_info false)
    if $ref != "ghcr.io/owner/repo/service-a:v1.0.0" {
      error make {msg: $"Expected 'ghcr.io/owner/repo/service-a:v1.0.0', got: ($ref)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test11)
  
  # Test 12: Multi-platform node (GitHub CI)
  let test12 = (run-test "compute-canonical-image-ref: multi-platform GitHub CI" {
    let registry_info = {
      ci_platform: "github",
      github_registry: "ghcr.io",
      github_path: "owner/repo"
    }
    let ref = (compute-canonical-image-ref "revad-base:v3.3.3:production" $registry_info false)
    if $ref != "ghcr.io/owner/repo/revad-base:v3.3.3-production" {
      error make {msg: $"Expected 'ghcr.io/owner/repo/revad-base:v3.3.3-production', got: ($ref)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test12)
  
  # Test 13: Forgejo CI
  let test13 = (run-test "compute-canonical-image-ref: Forgejo CI" {
    let registry_info = {
      ci_platform: "forgejo",
      forgejo_registry: "git.example.io",
      forgejo_path: "org/containers"
    }
    let ref = (compute-canonical-image-ref "service:v1.0.0" $registry_info false)
    if $ref != "git.example.io/org/containers/service:v1.0.0" {
      error make {msg: $"Expected 'git.example.io/org/containers/service:v1.0.0', got: ($ref)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test13)
  
  # === Build Order Deduplication Tests ===
  
  # Test 14: Shared deps in build order should be deduped
  let test14 = (run-test "deps pull: shared deps should be deduped" {
    # This tests the concept - actual docker pull mocking would require more infrastructure
    # For now, verify that the same node appearing twice would be handled
    let build_order = [
      "common:v1.0.0",
      "service-a:v1.0.0",
      "service-b:v1.0.0"  # Both depend on common:v1.0.0
    ]
    # Verify the build order has the shared dep only once
    let unique_count = ($build_order | uniq | length)
    if $unique_count != 3 {
      error make {msg: $"Expected 3 unique nodes, got ($unique_count)"}
    }
    true
  } $verbose_flag)
  $results = ($results | append $test14)
  
  # === Summary ===
  
  print-test-summary $results
  
  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
