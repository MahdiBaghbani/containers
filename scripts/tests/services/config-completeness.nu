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

# Service config required-field completeness tests.

use ../../lib/platforms/core.nu [check-platforms-manifest-exists]
use ../../lib/services/core.nu [list-service-names get-service]
use ../lib.nu [run-test]

export def config-completeness-tests [verbose: bool] {
  [
    (run-test "Service config completeness" {
      let all_services = (list-service-names)
      for svc in $all_services {
        let config = (get-service $svc)
        let has_platforms = (check-platforms-manifest-exists $svc)

        let required_fields = ["name", "context"]

        let required_with_conditional = (
          if $has_platforms {
            $required_fields
          } else {
            $required_fields | append "dockerfile"
          }
        )

        for field in $required_with_conditional {
          if not ($field in ($config | columns)) {
            error make {msg: $"Service ($svc) missing required field: ($field)"}
          }
        }
      }
      if $verbose { print $"    All services have required fields" }
      true
    } $verbose)
  ]
}
