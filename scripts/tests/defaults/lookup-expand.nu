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

# get-version-spec, get-platform-spec, and expand-version-to-platforms coverage.

use ../../lib/manifest/core.nu [get-version-spec]
use ../../lib/platforms/core.nu [
  get-platform-spec expand-version-to-platforms get-default-platform
]
use ../lib.nu [run-test]

export def test-get-version-spec-applies-defaults-automatically [verbose: bool] {
  run-test "get-version-spec: applies defaults automatically" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let result = (get-version-spec $manifest "v1.0.0")
    if ($result.overrides.external_images.build.tag) != "1.25-trixie" {
      error make {msg: $"get-version-spec should apply defaults: expected '1.25-trixie', got '($result.overrides.external_images.build.tag)'"}
    }
    true
  } $verbose
}

export def test-get-platform-spec-applies-defaults-automatically [verbose: bool] {
  run-test "get-platform-spec: applies defaults automatically" {
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
    let result = (get-platform-spec $platforms "production")
    if ($result.external_images.build.name) != "golang" {
      error make {msg: $"get-platform-spec should apply defaults: expected 'golang', got '($result.external_images.build.name)'"}
    }
    true
  } $verbose
}

export def test-expand-version-to-platforms-works-with-defaults [verbose: bool] {
  run-test "expand-version-to-platforms: works with defaults" {
    let platforms = {
      default: "production",
      platforms: [
        { name: "production" },
        { name: "development" }
      ]
    }
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: { tag: "1.25-trixie" }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let version_spec = (get-version-spec $manifest "v1.0.0")
    let default_platform = (get-default-platform $platforms)
    let expanded = (expand-version-to-platforms $version_spec $platforms $default_platform)
    if ($expanded | length) != 2 {
      error make {msg: $"Expected 2 platforms, got ($expanded | length)"}
    }
    for exp in $expanded {
      let tag = (try { $exp.overrides.external_images.build.tag } catch { "missing" })
      if $tag != "1.25-trixie" {
        error make {msg: $"Default should be applied in expanded version: got '($tag)'"}
      }
    }
    true
  } $verbose
}
