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

# service-complete, service-file, and manifest-file smoke/pass-path checks.

use ../../lib/validate/core.nu [
  validate-service-complete
  validate-service-file
  validate-manifest-file
]
use ../lib.nu [run-test]

export def service-complete-smoke-tests [verbose: bool] {
  [
    (run-test "validate-service-complete returns valid/errors shape" {
      let result = (validate-service-complete "common-tools")
      ("valid" in ($result | columns)) and ("errors" in ($result | columns))
    } $verbose)
    (run-test "validate-service-complete passes for common-tools" {
      let result = (validate-service-complete "common-tools")
      if not $result.valid {
        error make {msg: $"Expected common-tools complete validation to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-file runs for common-tools" {
      let result = (validate-service-file "common-tools")
      ("valid" in ($result | columns)) and ("errors" in ($result | columns))
    } $verbose)
    (run-test "validate-manifest-file runs for common-tools" {
      let result = (validate-manifest-file "common-tools")
      ("valid" in ($result | columns)) and ("errors" in ($result | columns))
    } $verbose)
  ]
}
