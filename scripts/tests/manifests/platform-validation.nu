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

# Platform validation and expansion cases.

use ../../lib/validate/core.nu [
  validate-version-manifest validate-service-config validate-platform-config
]
use ../../lib/platforms/core.nu [expand-version-to-platforms get-default-platform]
use ../lib.nu [run-test]

export def test-detect-platform-suffix-in-version-name [verbose: bool] {
  run-test "Detect platform suffix in version name" {
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
    true
  } $verbose
}

export def test-platform-expansion-composite-uniqueness [verbose: bool] {
  run-test "Platform expansion composite uniqueness" {
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
    true
  } $verbose
}

export def test-multi-platform-service-without-base-dockerfile [verbose: bool] {
  run-test "Multi-platform service without base dockerfile" {
    let test_config = {
      name: "test-multi-platform",
      context: "services/test-multi-platform"
      # Note: no dockerfile field
    }
    let result = (validate-service-config $test_config true)  # has_platforms = true
    if not $result.valid {
      error make {msg: $"Multi-platform service without dockerfile should be valid, errors: ($result.errors | str join ', ')"}
    }
    true
  } $verbose
}

export def test-single-platform-service-without-dockerfile [verbose: bool] {
  run-test "Single-platform service without dockerfile" {
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
    true
  } $verbose
}

export def test-platform-config-missing-build-arg [verbose: bool] {
  run-test "Platform config with missing build_arg in external_images" {
    let bad_platform_config = {
      name: "alpine",
      dockerfile: "Dockerfile.alpine",
      external_images: {
        runtime: {
          name: "alpine:3.21"
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
    if $verbose {
      print $"    Caught expected error: ($result.errors.0)"
    }
    true
  } $verbose
}

export def test-platform-config-complete-external-images [verbose: bool] {
  run-test "Platform config with complete external_images" {
    let good_platform_config = {
      name: "alpine",
      dockerfile: "Dockerfile.alpine",
      external_images: {
        runtime: {
          name: "alpine:3.21",
          build_arg: "BASE_RUNTIME_IMAGE"
        }
      }
    }
    let result = (validate-platform-config $good_platform_config "alpine")
    if not $result.valid {
      error make {msg: $"Platform config with complete external_images should be valid. Errors: ($result.errors | str join ', ')"}
    }
    if $verbose {
      print $"    Validation passed for complete platform config"
    }
    true
  } $verbose
}
