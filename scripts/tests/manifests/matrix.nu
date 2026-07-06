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

# Matrix-generation coverage.

use ../../lib/build/matrix.nu [generate-service-matrix]
use ../lib.nu [run-test]

export def test-matrix-includes-platform-field [verbose: bool] {
  run-test "Matrix includes platform field (multi-platform)" {
    # Use revad-base which is a multi-platform service with production/development platforms
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
      # Multi-platform should have non-empty platform string
      if ($entry.platform | str length) == 0 {
        error make {msg: "Multi-platform should have non-empty platform string"}
      }
    }
    true
  } $verbose
}
