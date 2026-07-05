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

# Manifest/platform validation and backward-compat checks.

use ../../lib/manifest/core.nu [get-version-spec]
use ../../lib/validate/core.nu [validate-version-manifest validate-platforms-manifest]
use ../lib.nu [run-test]

export def test-validation-valid-defaults-structure [verbose: bool] {
  run-test "Validation: valid defaults structure" {
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
    let validation = (validate-version-manifest $manifest null)
    if not $validation.valid {
      error make {msg: $"Valid defaults should pass validation: ($validation.errors | str join ', ')"}
    }
    true
  } $verbose
}

export def test-validation-invalid-defaults-forbidden-field [verbose: bool] {
  run-test "Validation: invalid defaults (forbidden field)" {
    let manifest = {
      default: "v1.0.0",
      defaults: {
        external_images: {
          build: {
            name: "golang"  # Forbidden in version defaults
          }
        }
      },
      versions: [
        {
          name: "v1.0.0",
          overrides: {}
        }
      ]
    }
    let validation = (validate-version-manifest $manifest null)
    if $validation.valid {
      error make {msg: "Invalid defaults should fail validation"}
    }
    true
  } $verbose
}

export def test-validation-platform-defaults-forbid-sources [verbose: bool] {
  run-test "Validation: platform defaults forbid sources" {
    let platforms = {
      default: "production",
      defaults: {
        sources: {
          revad: { ref: "v3.3.3" }  # Forbidden in platform defaults
        }
      },
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production"
        }
      ]
    }
    let validation = (validate-platforms-manifest $platforms)
    if $validation.valid {
      error make {msg: "Platform defaults with sources should fail validation"}
    }
    true
  } $verbose
}

export def test-backward-compatibility-manifest-without-defaults [verbose: bool] {
  run-test "Backward compatibility: manifest without defaults validates and resolves version spec" {
    let manifest = {
      default: "v1.0.0",
      versions: [
        {
          name: "v1.0.0",
          overrides: {
            sources: {
              app: { ref: "v1.0.0" }
            }
          }
        }
      ]
    }
    let platforms = {
      default: "production",
      platforms: [
        {
          name: "production",
          dockerfile: "Dockerfile.production",
          external_images: {
            build: { name: "golang", build_arg: "BASE_BUILD_IMAGE" }
          }
        }
      ]
    }
    let v_validation = (validate-version-manifest $manifest $platforms)
    let p_validation = (validate-platforms-manifest $platforms)
    if not ($v_validation.valid and $p_validation.valid) {
      error make {msg: "Manifest without defaults should validate"}
    }
    let version_spec = (get-version-spec $manifest "v1.0.0")
    if not ("overrides" in ($version_spec | columns)) {
      error make {msg: "Version spec should have overrides field"}
    }
    if ($version_spec.overrides.sources.app.ref) != "v1.0.0" {
      error make {msg: "Version spec overrides should remain unchanged without defaults"}
    }
    true
  } $verbose
}
