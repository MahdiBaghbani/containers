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

# apply-platform-defaults coverage.

use ../../lib/platforms/core.nu [apply-platform-defaults]
use ../lib.nu [run-test]

export def test-apply-platform-defaults-no-defaults [verbose: bool] {
  run-test "apply-platform-defaults: no defaults" {
    let platforms = {
      default: "production",
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production",
          external_images: {
            build: {
              name: "golang",
              build_arg: "BASE_BUILD_IMAGE"
            }
          }
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "golang" {
      error make {msg: "Platform spec should be unchanged when no defaults"}
    }
    true
  } $verbose
}

export def test-apply-platform-defaults-with-defaults [verbose: bool] {
  run-test "apply-platform-defaults: with defaults" {
    let platforms = {
      default: "production",
      defaults: {
        external_images: {
          build: {
            name: "golang",
            build_arg: "BASE_BUILD_IMAGE"
          }
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production"
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "golang" {
      error make {msg: $"Expected 'golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose
}

export def test-apply-platform-defaults-override-takes-precedence [verbose: bool] {
  run-test "apply-platform-defaults: override takes precedence" {
    let platforms = {
      default: "production",
      defaults: {
        external_images: {
          build: {
            name: "golang",
            build_arg: "BASE_BUILD_IMAGE"
          }
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production",
          external_images: {
            build: {
              name: "custom-golang",
              build_arg: "BASE_BUILD_IMAGE"
            }
          }
        }
      ]
    }
    let platform_spec = $platforms.platforms.0
    let result = (apply-platform-defaults $platforms $platform_spec)
    if ($result.external_images.build.name) != "custom-golang" {
      error make {msg: $"Platform override should win: expected 'custom-golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose
}
