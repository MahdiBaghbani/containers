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

# Service discovery and configuration lookup tests.

use ../../lib/services/core.nu [list-services list-service-names service-exists get-service]
use ../lib.nu [run-test]

export def discovery-tests [verbose: bool] {
  [
    (run-test "Service discovery" {
      let services = (list-service-names)
      if ($services | is-empty) {
        error make {msg: "No services found"}
      }
      if $verbose { print $"    Found ($services | length) services" }
      true
    } $verbose)
    ,
    (run-test "TLS filtering (--tls-only)" {
      let tls_services = (list-services --tls-only)
      if $verbose { print $"    Found ($tls_services | length) TLS-enabled services" }
      true
    } $verbose)
    ,
    (run-test "Service existence check" {
      let all_services = (list-service-names)
      if ($all_services | is-empty) {
        error make {msg: "No services found to check existence"}
      }
      let first_svc = ($all_services | first)
      if not (service-exists $first_svc) {
        error make {msg: $"($first_svc) should exist in the service list"}
      }
      if (service-exists "nonexistent-service") {
        error make {msg: "nonexistent-service should not exist"}
      }
      true
    } $verbose)
    ,
    (run-test "Get service config" {
      let all_services = (list-service-names)
      if ($all_services | is-empty) {
        error make {msg: "No services found to get config"}
      }
      let first_svc = ($all_services | first)
      let config = (get-service $first_svc)
      if not ("name" in ($config | columns)) {
        error make {msg: $"Service config for ($first_svc) missing 'name' field"}
      }
      if $verbose { print $"    Config name: ($config.name)" }
      true
    } $verbose)
  ]
}
