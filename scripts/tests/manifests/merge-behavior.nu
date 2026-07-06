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

# Merge-behavior checks.

use ../../lib/platforms/core.nu [merge-platform-config]
use ../lib.nu [run-test]

export def test-deep-merge-external-images [verbose: bool] {
  run-test "Deep-merge behavior for external_images" {
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

    if $verbose {
      print $"    Deep-merge verified: build image preserved, runtime image overridden"
    }
    true
  } $verbose
}
