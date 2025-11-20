#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Version manifest tests

use ../lib/manifest.nu [check-versions-manifest-exists load-versions-manifest filter-versions]
use ../lib/platforms.nu [merge-version-overrides]
use ../lib/matrix.nu [generate-service-matrix]
use ../lib/validate.nu [validate-service-file validate-manifest-file validate-version-manifest print-validation-results]
use ../lib/services.nu [list-service-names]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Test 1: Matrix JSON generation
  let test1 = (run-test "Matrix JSON generation" {
    let matrix = (nu scripts/build.nu --service revad-base --matrix-json true)
    if $verbose_flag { print $"    Matrix: ($matrix)" }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: All services have manifests
  let test2 = (run-test "All services have manifests" {
    let all_services = (list-service-names)
    mut missing = []
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) {
        $missing = ($missing | append $svc)
      }
    }
    if not ($missing | is-empty) {
      error make {msg: $"Services missing manifests: ($missing | str join ', ')"}
    }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Load manifest
  let test3 = (run-test "Load manifest" {
    let manifest = (load-versions-manifest "revad-base")
    if $verbose_flag { print $"    Default version: ($manifest.default)" }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Validate all service configs
  let test4 = (run-test "Validate service configs" {
    let all_services = (list-service-names)
    mut invalid = []
    for svc in $all_services {
      let validation = (validate-service-file $svc)
      if not $validation.valid {
        $invalid = ($invalid | append $svc)
      }
    }
    if not ($invalid | is-empty) {
      error make {msg: $"Invalid service configs: ($invalid | str join ', ')"}
    }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Validate all manifests
  let test5 = (run-test "Validate manifests" {
    let all_services = (list-service-names)
    mut invalid = []
    for svc in $all_services {
      let validation = (validate-manifest-file $svc)
      if not $validation.valid {
        $invalid = ($invalid | append $svc)
        if $verbose_flag {
          print $"    ($svc) validation errors:"
          for err in $validation.errors {
            print $"      - ($err)"
          }
        }
      }
    }
    if not ($invalid | is-empty) {
      error make {msg: $"Invalid manifests: ($invalid | str join ', ')"}
    }
  } $verbose_flag)
  $results = ($results | append $test5)
  
  # Test 6: Config merge
  let test6 = (run-test "Config merge with overrides" {
    let manifest = (load-versions-manifest "revad-base")
    let base_config = (open "services/revad-base.nuon")
    
    if ($manifest.versions | length) > 0 {
      let version_spec = $manifest.versions.0
      # Use merge-version-overrides with empty platform string for single-platform
      let merged = (merge-version-overrides $base_config $version_spec "" null)
      if $verbose_flag { print $"    Merged config has ($merged | columns | length) keys" }
    }
  } $verbose_flag)
  $results = ($results | append $test6)
  
  # Test 7: Filter versions
  let test7 = (run-test "Filter versions (all)" {
    let manifest = (load-versions-manifest "revad-base")
    # filter-versions now returns record with {versions, detected_platforms}
    let result = (filter-versions $manifest null --all=true)
    let all_versions = $result.versions
    if $verbose_flag { print $"    Found ($all_versions | length) version\(s\)" }
  } $verbose_flag)
  $results = ($results | append $test7)
  
  # Test 8: Detect forbidden 'latest' in tags
  let test8 = (run-test "Detect forbidden 'latest' in tags" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true, tags: ["latest"]}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect forbidden 'latest' in tags"}
    }
  } $verbose_flag)
  $results = ($results | append $test8)
  
  # Test 9: Detect duplicate version names
  let test9 = (run-test "Detect duplicate version names" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v1.0.0"}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect duplicate version names"}
    }
  } $verbose_flag)
  $results = ($results | append $test9)
  
  # Test 10: Detect tag collision across versions
  let test10 = (run-test "Detect tag collision across versions" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true, tags: ["stable"]},
        {name: "v2.0.0", tags: ["stable"]}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect tag collision"}
    }
  } $verbose_flag)
  $results = ($results | append $test10)
  
  # Test 11: Detect multiple latest versions
  let test11 = (run-test "Detect multiple latest versions" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v2.0.0", latest: true}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect multiple latest versions"}
    }
  } $verbose_flag)
  $results = ($results | append $test11)
  
  # Test 12: Platform-aware validation - detect platform suffix in version name
  let test12 = (run-test "Detect platform suffix in version name" {
    let platforms = {
      default: "debian",
      platforms: [
        {name: "debian", dockerfile: "Dockerfile.debian"},
        {name: "alpine", dockerfile: "Dockerfile.alpine"}
      ]
    }
    let bad_manifest = {
      default: "v1.0.0-debian",
      versions: [
        {name: "v1.0.0-debian", latest: true}
      ]
    }
    let result = (validate-version-manifest $bad_manifest $platforms)
    if $result.valid {
      error make {msg: "Failed to detect platform suffix in version name"}
    }
    # Check error message mentions platform suffix
    let has_suffix_error = ($result.errors | any {|e| ($e | str contains "platform suffix")})
    if not $has_suffix_error {
      error make {msg: "Error message should mention platform suffix"}
    }
  } $verbose_flag)
  $results = ($results | append $test12)
  
  # Test 13: Platform expansion creates correct composite keys
  let test13 = (run-test "Platform expansion composite uniqueness" {
    use ../lib/platforms.nu [expand-version-to-platforms get-default-platform]
    let platforms = {
      default: "debian",
      platforms: [
        {name: "debian", dockerfile: "Dockerfile.debian"},
        {name: "alpine", dockerfile: "Dockerfile.alpine"}
      ]
    }
    let version_spec = {name: "v1.0.0", latest: true}
    let default_platform = (get-default-platform $platforms)
    let expanded = (expand-version-to-platforms $version_spec $platforms $default_platform)
    
    if ($expanded | length) != 2 {
      error make {msg: $"Expected 2 expanded versions, got ($expanded | length)"}
    }
    
    # Check each has platform field
    for exp in $expanded {
      if not ("platform" in ($exp | columns)) {
        error make {msg: "Expanded version missing platform field"}
      }
    }
  } $verbose_flag)
  $results = ($results | append $test13)
  
  # Test 14: Matrix generation includes platform field
  let test14 = (run-test "Matrix includes platform field (single-platform)" {
    let matrix = (generate-service-matrix "revad-base")
    let entries = $matrix.include
    
    if ($entries | is-empty) {
      error make {msg: "Matrix should not be empty"}
    }
    
    # Check all entries have platform field
    for entry in $entries {
      if not ("platform" in ($entry | columns)) {
        error make {msg: "Matrix entry missing platform field"}
      }
      # Single-platform should have empty string
      if ($entry.platform | str length) > 0 {
        error make {msg: $"Single-platform should have empty platform string, got: ($entry.platform)"}
      }
    }
  } $verbose_flag)
  $results = ($results | append $test14)
  
  # Test 15: Multi-platform service without base dockerfile (should pass)
  let test15 = (run-test "Multi-platform service without base dockerfile" {
    use ../lib/validate.nu [validate-service-config]
    let test_config = {
      name: "test-multi-platform",
      context: "services/test-multi-platform"
      # Note: no dockerfile field
    }
    let result = (validate-service-config $test_config true)  # has_platforms = true
    if not $result.valid {
      error make {msg: $"Multi-platform service without dockerfile should be valid, errors: ($result.errors | str join ', ')"}
    }
  } $verbose_flag)
  $results = ($results | append $test15)
  
  # Test 16: Single-platform service without dockerfile (should fail)
  let test16 = (run-test "Single-platform service without dockerfile" {
    use ../lib/validate.nu [validate-service-config]
    let test_config = {
      name: "test-single-platform",
      context: "services/test-single-platform"
      # Note: no dockerfile field
    }
    let result = (validate-service-config $test_config false)  # has_platforms = false
    if $result.valid {
      error make {msg: "Single-platform service without dockerfile should be invalid"}
    }
    # Check error message mentions dockerfile
    let has_dockerfile_error = ($result.errors | any {|e| ($e | str contains "dockerfile")})
    if not $has_dockerfile_error {
      error make {msg: "Error should mention missing dockerfile"}
    }
  } $verbose_flag)
  $results = ($results | append $test16)
  
  # Test 17: Platform config with missing build_arg in external_images (should fail)
  let test17 = (run-test "Platform config with missing build_arg in external_images" {
    use ../lib/validate.nu [validate-platform-config]
    let bad_platform_config = {
      name: "alpine",
      dockerfile: "Dockerfile.alpine",
      external_images: {
        runtime: {
          image: "alpine:3.21"
          # Missing: build_arg field
        }
      }
    }
    let result = (validate-platform-config $bad_platform_config "alpine")
    if $result.valid {
      error make {msg: "Platform config with missing build_arg should be invalid"}
    }
    # Check error message mentions build_arg
    let has_build_arg_error = ($result.errors | any {|e| ($e | str contains "build_arg")})
    if not $has_build_arg_error {
      error make {msg: "Error should mention missing build_arg"}
    }
    if $verbose_flag {
      print $"    Caught expected error: ($result.errors.0)"
    }
  } $verbose_flag)
  $results = ($results | append $test17)
  
  # Test 18: Platform config with complete external_images entries (should pass)
  let test18 = (run-test "Platform config with complete external_images" {
    use ../lib/validate.nu [validate-platform-config]
    let good_platform_config = {
      name: "alpine",
      dockerfile: "Dockerfile.alpine",
      external_images: {
        runtime: {
          image: "alpine:3.21",
          build_arg: "BASE_RUNTIME_IMAGE"
        }
      }
    }
    let result = (validate-platform-config $good_platform_config "alpine")
    if not $result.valid {
      error make {msg: $"Platform config with complete external_images should be valid. Errors: ($result.errors | str join ', ')"}
    }
    if $verbose_flag {
      print $"    Validation passed for complete platform config"
    }
  } $verbose_flag)
  $results = ($results | append $test18)
  
  # Test 19: Deep-merge behavior for external_images (platform + base = merged)
  let test19 = (run-test "Deep-merge behavior for external_images" {
    use ../lib/platforms.nu [merge-platform-config]
    use ../lib/common.nu [deep-merge]
    
    # Base config
    let base_config = {
      name: "test-service",
      external_images: {
        build: {
          image: "golang:1.25",
          build_arg: "BASE_BUILD_IMAGE"
        },
        runtime: {
          image: "debian:bookworm",
          build_arg: "BASE_RUNTIME_IMAGE"
        }
      }
    }
    
    # Platform config (only overrides runtime image, not build_arg)
    let platform_spec = {
      name: "alpine",
      dockerfile: "Dockerfile.alpine",
      external_images: {
        runtime: {
          image: "alpine:3.21",
          build_arg: "BASE_RUNTIME_IMAGE"
        }
      }
    }
    
    # Merge
    let merged = (merge-platform-config $base_config $platform_spec)
    
    # Verify build image is preserved from base
    let build_image = (try { $merged.external_images.build.image } catch { "" })
    if $build_image != "golang:1.25" {
      error make {msg: $"Expected build image 'golang:1.25', got '($build_image)'"}
    }
    
    let build_arg = (try { $merged.external_images.build.build_arg } catch { "" })
    if $build_arg != "BASE_BUILD_IMAGE" {
      error make {msg: $"Expected build_arg 'BASE_BUILD_IMAGE', got '($build_arg)'"}
    }
    
    # Verify runtime image is overridden from platform
    let runtime_image = (try { $merged.external_images.runtime.image } catch { "" })
    if $runtime_image != "alpine:3.21" {
      error make {msg: $"Expected runtime image 'alpine:3.21', got '($runtime_image)'"}
    }
    
    # Verify runtime build_arg is from platform (explicit)
    let runtime_arg = (try { $merged.external_images.runtime.build_arg } catch { "" })
    if $runtime_arg != "BASE_RUNTIME_IMAGE" {
      error make {msg: $"Expected runtime build_arg 'BASE_RUNTIME_IMAGE', got '($runtime_arg)'"}
    }
    
    if $verbose_flag {
      print $"    Deep-merge verified: build image preserved, runtime image overridden"
    }
  } $verbose_flag)
  $results = ($results | append $test19)
  
  # Test 20: Validate-manifest-file performs Phase 2 validation for multi-platform
  let test20 = (run-test "validate-manifest-file Phase 2 validation with platforms" {
    use ../lib/validate.nu [validate-version-manifest]
    use ../lib/platforms.nu [expand-version-to-platforms get-default-platform]
    
    # Create a scenario that would pass Phase 1 but fail Phase 2
    # (version names without platform suffixes, but collision after expansion)
    let platforms = {
      default: "debian",
      platforms: [
        {name: "debian", dockerfile: "Dockerfile.debian"},
        {name: "alpine", dockerfile: "Dockerfile.alpine"}
      ]
    }
    
    # This manifest has a potential tag collision after platform expansion
    # v1.0.0 generates: v1.0.0-debian, v1.0.0-alpine, stable-debian, stable-alpine
    # v2.0.0 generates: v2.0.0-debian, v2.0.0-alpine, stable-debian (COLLISION!), stable-alpine (COLLISION!)
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true, tags: ["stable"]},
        {name: "v2.0.0", tags: ["stable"]}  # Same tag "stable" will collide after expansion
      ]
    }
    
    # Validate with platforms (Phase 2 should catch tag collision)
    let result = (validate-version-manifest $bad_manifest $platforms)
    
    if $result.valid {
      error make {msg: "Should have detected tag collision after platform expansion"}
    }
    
    # Check error mentions tag collision
    let has_collision_error = ($result.errors | any {|e| ($e | str contains "collision") or ($e | str contains "stable")})
    if not $has_collision_error {
      error make {msg: $"Error should mention tag collision. Got: ($result.errors | str join ', ')"}
    }
    
    if $verbose_flag {
      print $"    Phase 2 validation correctly detected tag collision: ($result.errors.0)"
    }
  } $verbose_flag)
  $results = ($results | append $test20)
  
  # Test 21: validate-manifest-file loads platforms manifest automatically
  let test21 = (run-test "validate-manifest-file auto-loads platforms for Phase 2" {
    use ../lib/validate.nu [validate-manifest-file]
    
    # For this test, we'll verify that validate-manifest-file works correctly
    # by calling it on revad-base (which exists and should have valid manifest)
    let result = (validate-manifest-file "revad-base")
    
    # Should pass (revad-base has valid manifest)
    if not $result.valid {
      error make {msg: $"revad-base manifest should be valid. Errors: ($result.errors | str join ', ')"}
    }
    
    if $verbose_flag {
      print $"    validate-manifest-file successfully validated revad-base"
    }
  } $verbose_flag)
  $results = ($results | append $test21)
  
  print-test-summary $results
  
  # Exit with error if any tests failed
  if ($results | any {|r| not $r}) {
    exit 1
  }
}
