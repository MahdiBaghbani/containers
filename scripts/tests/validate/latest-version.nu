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

# latest-version rule tests.

use ../../lib/validate/core.nu [validate-version-manifest]
use ../lib.nu [run-test]

export def latest-version-tests [verbose: bool] {
  [
    (run-test "validate-version-manifest: single latest is accepted" {
      let manifest = {
        default: "v1.0.0",
        versions: [
          {name: "v1.0.0", latest: true},
          {name: "v2.0.0"}
        ]
      }
      let result = (validate-version-manifest $manifest null)
      if not $result.valid {
        error make {msg: $"Expected single-latest manifest to be valid, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-manifest: multiple latest emits explicit message" {
      let manifest = {
        default: "v1.0.0",
        versions: [
          {name: "v1.0.0", latest: true},
          {name: "v2.0.0", latest: true}
        ]
      }
      let result = (validate-version-manifest $manifest null)
      if $result.valid {
        error make {msg: "Expected multiple latest versions to be rejected"}
      }
      let has_msg = ($result.errors | any {|e| $e | str contains "Only one version can have 'latest: true'"})
      if not $has_msg {
        error make {msg: $"Expected explicit multiple-latest message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
