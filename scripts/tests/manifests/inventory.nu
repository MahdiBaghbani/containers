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

# Service and manifest inventory checks.

use ../../lib/manifest/core.nu [check-versions-manifest-exists]
use ../../lib/validate/core.nu [validate-service-file validate-manifest-file]
use ../../lib/services/core.nu [list-service-names]
use ../lib.nu [run-test]

export def test-all-services-have-manifests [verbose: bool] {
  run-test "All services have manifests" {
    let all_services = (list-service-names)
    mut missing = []
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) {
        $missing = ($missing | append $svc)
      }
    }
    if not ($missing | is-empty) {
      error make {msg: $"Services missing manifests: ($missing | str join ', ')"}
    }
    true
  } $verbose
}

export def test-validate-service-configs [verbose: bool] {
  run-test "Validate service configs" {
    let all_services = (list-service-names)
    mut invalid = []
    for svc in $all_services {
      let validation = (validate-service-file $svc)
      if not $validation.valid {
        $invalid = ($invalid | append $svc)
      }
    }
    if not ($invalid | is-empty) {
      error make {msg: $"Invalid service configs: ($invalid | str join ', ')"}
    }
    true
  } $verbose
}

export def test-validate-manifests [verbose: bool] {
  run-test "Validate manifests" {
    let all_services = (list-service-names)
    mut invalid = []
    for svc in $all_services {
      let validation = (validate-manifest-file $svc)
      if not $validation.valid {
        $invalid = ($invalid | append $svc)
        if $verbose {
          print $"    ($svc) validation errors:"
          for err in $validation.errors {
            print $"      - ($err)"
          }
        }
      }
    }
    if not ($invalid | is-empty) {
      error make {msg: $"Invalid manifests: ($invalid | str join ', ')"}
    }
    true
  } $verbose
}
