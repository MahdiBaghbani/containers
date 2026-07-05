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

# Service definition hash basics (Tests 1-6).

use ../../lib/build/hash.nu [compute-service-def-hash]
use ../helpers.nu [setup-test-environment with-test-cleanup]
use ../lib.nu [run-test]

export def hash-basics-tests [verbose: bool] {
    [
        (run-test "Test 1: Hash stability - same inputs produce same hash" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes = {}

              let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
              let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)

              if $hash1 != $hash2 {
                error make { msg: $"Hash mismatch: '($hash1)' != '($hash2)'" }
              }

              if $verbose {
                print $"    Hash: ($hash1)"
              }

              true
            }
          } $verbose)
        ,
        (run-test "Test 2: Hash format - 64 character SHA256 hex string" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes = {}

              let hash = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)

              if ($hash | str length) != 64 {
                error make { msg: $"Hash length is ($hash | str length), expected 64" }
              }

              if not ($hash =~ '^[0-9a-f]{64}$') {
                error make { msg: $"Hash '($hash)' is not valid lowercase hex" }
              }

              if $verbose {
                print $"    Hash: ($hash) \(length: ($hash | str length)\)"
              }

              true
            }
          } $verbose)
        ,
        (run-test "Test 3: Hash changes with different version" {
            with-test-cleanup {
              let test_env1 = (setup-test-environment "test-service" "v1.0.0")
              let test_env2 = (setup-test-environment "test-service" "v2.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes = {}

              let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env1.merged_cfg $source_shas $source_types $dep_hashes)
              let hash2 = (compute-service-def-hash "test-service" "v2.0.0" "" $test_env2.merged_cfg $source_shas $source_types $dep_hashes)

              if $hash1 == $hash2 {
                error make { msg: $"Hashes should differ for different versions: '($hash1)'" }
              }

              if $verbose {
                print $"    v1.0.0 hash: ($hash1)"
                print $"    v2.0.0 hash: ($hash2)"
              }

              true
            }
          } $verbose)
        ,
        (run-test "Test 4: Hash changes with different service name" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes = {}

              let hash1 = (compute-service-def-hash "service-a" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
              let hash2 = (compute-service-def-hash "service-b" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)

              if $hash1 == $hash2 {
                error make { msg: $"Hashes should differ for different services: '($hash1)'" }
              }

              if $verbose {
                print $"    service-a hash: ($hash1)"
                print $"    service-b hash: ($hash2)"
              }

              true
            }
          } $verbose)
        ,
        (run-test "Test 5: Hash includes dependency hashes" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes_empty = {}
              let dep_hashes_with_dep = { "dep-service:v1.0.0": "abc123def456" }

              let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes_empty)
              let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes_with_dep)

              if $hash1 == $hash2 {
                error make { msg: $"Hashes should differ when dependency hashes change: '($hash1)'" }
              }

              if $verbose {
                print $"    No deps hash: ($hash1)"
                print $"    With deps hash: ($hash2)"
              }

              true
            }
          } $verbose)
        ,
        (run-test "Test 6: Hash changes with platform" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")

              let source_shas = {}
              let source_types = {}
              let dep_hashes = {}

              let hash1 = (compute-service-def-hash "test-service" "v1.0.0" "" $test_env.merged_cfg $source_shas $source_types $dep_hashes)
              let hash2 = (compute-service-def-hash "test-service" "v1.0.0" "debian" $test_env.merged_cfg $source_shas $source_types $dep_hashes)

              if $hash1 == $hash2 {
                error make { msg: $"Hashes should differ for different platforms: '($hash1)'" }
              }

              if $verbose {
                print $"    No platform hash: ($hash1)"
                print $"    debian platform hash: ($hash2)"
              }

              true
            }
          } $verbose)
    ]
}
