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

# Expanded-tag collision coverage.

use ../../lib/validate/core.nu [validate-version-manifest validate-manifest-file]
use ../lib.nu [run-test]

export def test-validate-manifest-file-expanded-tag-validation [verbose: bool] {
  run-test "validate-manifest-file expanded-tag validation with platforms" {
    # Create a scenario that would pass base validation but fail expanded-tag validation
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

    # Validate with platforms (expanded-tag validation should catch tag collision)
    let result = (validate-version-manifest $bad_manifest $platforms)

    if $result.valid {
      error make {msg: "Should have detected tag collision after platform expansion"}
    }

    # Check error mentions tag collision
    let has_collision_error = ($result.errors | any {|e| ($e | str contains "collision") or ($e | str contains "stable")})
    if not $has_collision_error {
      error make {msg: $"Error should mention tag collision. Got: ($result.errors | str join ', ')"}
    }

    if $verbose {
      print $"    Expanded-tag validation correctly detected tag collision: ($result.errors.0)"
    }
    true
  } $verbose
}

export def test-validate-manifest-file-auto-loads-platforms [verbose: bool] {
  run-test "validate-manifest-file auto-loads platforms for expanded-tag validation" {
    # For this test, we'll verify that validate-manifest-file works correctly
    # by calling it on revad-base (which exists and should have valid manifest)
    let result = (validate-manifest-file "revad-base")

    # Should pass (revad-base has valid manifest)
    if not $result.valid {
      error make {msg: $"revad-base manifest should be valid. Errors: ($result.errors | str join ', ')"}
    }

    if $verbose {
      print $"    validate-manifest-file successfully validated revad-base"
    }
    true
  } $verbose
}
