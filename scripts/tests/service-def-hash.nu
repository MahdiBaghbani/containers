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

# Service definition hash stability tests
# These tests verify that hash computation is deterministic and stable
# Used to validate Phase 2 migration of service-def-hash.nu

use ../lib/build/hash.nu [compute-service-def-hash]
use ./helpers.nu [setup-test-environment cleanup-test-environment with-test-cleanup]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Test 1: Hash stability - same inputs produce same hash
  let test1 = (run-test "Test 1: Hash stability - same inputs produce same hash" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      # Create minimal source_shas and source_types
      let source_shas = {}
      let source_types = {}
      let dep_hashes = {}
      
      # Compute hash twice with identical inputs
      let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      
      if $hash1 != $hash2 {
        error make { msg: $"Hash mismatch: '($hash1)' != '($hash2)'" }
      }
      
      if $verbose_flag {
        print $"    Hash: ($hash1)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: Hash format - 64 character hex string (SHA256)
  let test2 = (run-test "Test 2: Hash format - 64 character SHA256 hex string" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      let source_shas = {}
      let source_types = {}
      let dep_hashes = {}
      
      let hash = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      
      # Hash should be 64 characters (full SHA256)
      if ($hash | str length) != 64 {
        error make { msg: $"Hash length is ($hash | str length), expected 64" }
      }
      
      # Hash should be lowercase hex
      if not ($hash =~ '^[0-9a-f]{64}$') {
        error make { msg: $"Hash '($hash)' is not valid lowercase hex" }
      }
      
      if $verbose_flag {
        print $"    Hash: ($hash) (length: ($hash | str length))"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Hash changes with different version
  let test3 = (run-test "Test 3: Hash changes with different version" {
    with-test-cleanup {
      let test_env1 = (setup-test-environment "test-service" "v1.0.0")
      let test_env2 = (setup-test-environment "test-service" "v2.0.0")
      
      let source_shas = {}
      let source_types = {}
      let dep_hashes = {}
      
      let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env1.merged_cfg $source_shas $source_types $dep_hashes)
      let hash2 = (compute-service-def-hash "test-service" "v2.0.0" "" $test_env2.merged_cfg $source_shas $source_types $dep_hashes)
      
      # Hashes should be different for different versions
      if $hash1 == $hash2 {
        error make { msg: $"Hashes should differ for different versions: '($hash1)'" }
      }
      
      if $verbose_flag {
        print $"    v1.0.0 hash: ($hash1)"
        print $"    v2.0.0 hash: ($hash2)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Hash changes with different service name
  let test4 = (run-test "Test 4: Hash changes with different service name" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      let source_shas = {}
      let source_types = {}
      let dep_hashes = {}
      
      let hash1 = (compute-service-def-hash "service-a" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      let hash2 = (compute-service-def-hash "service-b" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      
      # Hashes should be different for different service names
      if $hash1 == $hash2 {
        error make { msg: $"Hashes should differ for different services: '($hash1)'" }
      }
      
      if $verbose_flag {
        print $"    service-a hash: ($hash1)"
        print $"    service-b hash: ($hash2)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Hash includes dependency hashes
  let test5 = (run-test "Test 5: Hash includes dependency hashes" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      let source_shas = {}
      let source_types = {}
      let dep_hashes_empty = {}
      let dep_hashes_with_dep = { "dep-service:v1.0.0": "abc123def456" }
      
      let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes_empty)
      let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes_with_dep)
      
      # Hashes should be different when dependency hashes change
      if $hash1 == $hash2 {
        error make { msg: $"Hashes should differ when dependency hashes change: '($hash1)'" }
      }
      
      if $verbose_flag {
        print $"    No deps hash: ($hash1)"
        print $"    With deps hash: ($hash2)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Hash changes with platform
  let test6 = (run-test "Test 6: Hash changes with platform" {
    with-test-cleanup {
      let test_env = (setup-test-environment "test-service" "v1.0.0")
      
      let source_shas = {}
      let source_types = {}
      let dep_hashes = {}
      
      let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "debian" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
      
      # Hashes should be different for different platforms
      if $hash1 == $hash2 {
        error make { msg: $"Hashes should differ for different platforms: '($hash1)'" }
      }
      
      if $verbose_flag {
        print $"    No platform hash: ($hash1)"
        print $"    debian platform hash: ($hash2)"
      }
      
      true
    }
  } $verbose_flag)
  $results = ($results | append $test6)
  
  print-test-summary $results
  
  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
