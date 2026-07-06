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

# Direct integration checks for the manifests suite.

use ../../lib/validate/core.nu [validate-service-complete]
use ../../lib/services/core.nu [list-service-names]
use ../lib.nu [run-test]

export def test-matrix-json-generation [verbose: bool] {
  run-test "Matrix JSON generation" {
    let matrix = (nu scripts/dockypody.nu build --service revad-base --matrix-json)
    if $verbose { print $"    Matrix: ($matrix)" }
    true
  } $verbose
}

export def test-all-services-pass-complete-validation [verbose: bool] {
  run-test "All services pass complete validation" {
    let all_services = (list-service-names)
    for svc in $all_services {
      let result = (validate-service-complete $svc)
      if not $result.valid {
        let joined = ($result.errors | str join " | ")
        error make {msg: $"($svc): ($joined)"}
      }
    }
    if $verbose {
      print $"    All ($all_services | length) services passed complete validation"
    }
    true
  } $verbose
}
