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

# Cache busting tests (Tests 1-6).

use ../../lib/build/args.nu [generate-build-args]
use ../helpers.nu [setup-test-environment with-test-cleanup assert-cache-bust-format assert-cache-bust-value]
use ../lib.nu [run-test]

export def cache-busting-tests [verbose: bool] {
    [
        (run-test "Test 1: Cache Busting - Per-service computation" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
              
              # Generate build args without override
              let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
              let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
              
              # Verify CACHEBUST is present and has correct format (16 chars for source refs hash)
              let _ = (assert-cache-bust-format $cache_bust1 16 "hash")
              
              # Verify hash is consistent (same sources = same hash)
              let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
              let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
              
              let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
              
              if $verbose {
                print $"    CACHEBUST: ($cache_bust1)"
              }
              
              true
            }
          } $verbose)
        ,
        (run-test "Test 2: Cache Busting - Global override" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
              let override_value = "custom-cache-bust-123"
            
              # Generate build args with override
              let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta $override_value false)
              let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
            
              assert-cache-bust-value $cache_bust $override_value
            
              if $verbose {
                print $"    Override value: ($override_value)"
                print $"    CACHEBUST: ($cache_bust)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 3: Cache Busting - --no-cache flag" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Generate build args with --no-cache
              let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" true)
              let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
            
              # Verify it's a UUID format (36 chars with dashes)
              assert-cache-bust-format $cache_bust 36 "uuid"
            
              if $verbose {
                print $"    Generated UUID: ($cache_bust)"
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 4: Cache Busting - Git SHA fallback" {
            with-test-cleanup {
              # Create test environment with no sources (override config)
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Override config to remove sources (test Git SHA fallback)
              mut merged_cfg = $test_env.merged_cfg
              $merged_cfg = ($merged_cfg | upsert sources {})
            
              # Generate build args without override
              let build_args = (generate-build-args "test" $merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
              let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
            
              # Should be Git SHA (variable length) or "local"
              if ($cache_bust | str length) == 0 {
                error make {msg: "CACHEBUST not generated"}
              }
            
              if $cache_bust == "local" {
                if $verbose {
                  print $"    Using 'local' fallback \(no Git\)"
                }
              } else {
                if $verbose {
                  print $"    Using Git SHA: ($cache_bust)"
                }
              }
            
              true
            }
          } $verbose)
        ,
        (run-test "Test 5: Cache Busting - Environment variable override" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
              let env_value = "env-cache-bust-456"
            
              # Set environment variable
              let old_env = (try { $env.CACHEBUST } catch { "" })
              $env.CACHEBUST = $env_value
            
              try {
                # Generate build args without override or --no-cache
                let build_args = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
                let cache_bust = (try { $build_args.CACHEBUST } catch { "" })
              
                assert-cache-bust-value $cache_bust $env_value
              
                if $verbose {
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
          } $verbose)
        ,
        (run-test "Test 6: Cache Busting - Hash consistency" {
            with-test-cleanup {
              let test_env = (setup-test-environment "test-service" "v1.0.0")
            
              # Generate build args multiple times
              let build_args1 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
              let build_args2 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
              let build_args3 = (generate-build-args "test" $test_env.merged_cfg $test_env.meta $test_env.deps_resolved $test_env.tls_meta $test_env.ssh_meta "" false)
            
              let cache_bust1 = (try { $build_args1.CACHEBUST } catch { "" })
              let cache_bust2 = (try { $build_args2.CACHEBUST } catch { "" })
              let cache_bust3 = (try { $build_args3.CACHEBUST } catch { "" })
            
              # All should be identical
              let _ = (assert-cache-bust-value $cache_bust1 $cache_bust2)
              let _ = (assert-cache-bust-value $cache_bust2 $cache_bust3)
            
              if $verbose {
                print $"    Consistent CACHEBUST: ($cache_bust1)"
              }
            
              true
            }
          } $verbose)

    ]
}
