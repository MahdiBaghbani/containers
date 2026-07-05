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

# Platform manifest integrity and TLS filtering consistency tests.

use ../../lib/platforms/core.nu [
  check-platforms-manifest-exists load-platforms-manifest
  get-platform-names get-default-platform
]
use ../../lib/services/core.nu [list-services list-service-names get-service]
use ../lib.nu [run-test]

export def integrity-tests [verbose: bool] {
  [
    (run-test "Platform manifest integrity (all multi-platform services)" {
      let all_services = (list-service-names)
      for svc in $all_services {
        if not (check-platforms-manifest-exists $svc) { continue }
        let platforms = (load-platforms-manifest $svc)
        let names = (get-platform-names $platforms)

        if ($names | is-empty) {
          error make {msg: $"($svc): platform list is empty"}
        }

        let unique_names = ($names | uniq)
        if ($unique_names | length) != ($names | length) {
          error make {msg: $"($svc): platform names are not unique: ($names | str join ', ')"}
        }

        let default_platform = (get-default-platform $platforms)
        if not ($default_platform in $names) {
          error make {
            msg: $"($svc): default platform '($default_platform)' not in platform names: ($names | str join ', ')"
          }
        }
      }
      if $verbose {
        let multi = ($all_services | where {|svc|
          check-platforms-manifest-exists $svc
        })
        print $"    Checked ($multi | length) multi-platform services"
      }
      true
    } $verbose)
    ,
    (run-test "TLS-only filtering consistency" {
      let all_services = (list-service-names)
      let expected_tls = ($all_services | where {|svc|
        let config = (get-service $svc)
        (try { $config.tls.enabled } catch { false }) == true
      } | sort)
      let actual_tls = ((list-services --tls-only) | get name | sort)
      if $expected_tls != $actual_tls {
        error make {
          msg: $"TLS filtering mismatch. expected=($expected_tls | str join ',') actual=($actual_tls | str join ',')"
        }
      }
      if $verbose { print $"    TLS-enabled services: ($actual_tls | str join ', ')" }
      true
    } $verbose)
  ]
}
