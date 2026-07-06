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

# Advisory/warning behavior surfaced through validation.

use ../../lib/validate/core.nu [validate-version-manifest]
use ../lib.nu [run-test]

export def manifest-warnings-tests [verbose: bool] {
  [
    (run-test "validate-version-manifest: surfaces SSH override warning through results" {
      let manifest = {
        default: "v1",
        versions: [
          {name: "v1", overrides: {ssh: {enabled: true, mode: "server", port: 22}}}
        ]
      }
      let result = (validate-version-manifest $manifest null)
      if not $result.valid {
        error make {msg: $"Expected manifest with valid SSH override to be valid, got: ($result.errors | str join ', ')"}
      }
      if not ("warnings" in ($result | columns)) {
        error make {msg: "Expected validate-version-manifest result to include a warnings field"}
      }
      let has_warn = ($result.warnings | any {|w| $w | str contains "Version-level SSH overrides"})
      if not $has_warn {
        error make {msg: $"Expected SSH override warning to be surfaced, got: ($result.warnings | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
