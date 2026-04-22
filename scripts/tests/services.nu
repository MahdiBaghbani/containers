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

# Service discovery and configuration tests

use ../lib/services/core.nu [list-services list-service-names service-exists get-service]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  let verbose_flag = (try { $verbose } catch { false })
  mut results = []
  
  # Test 1: Service discovery
  let test1 = (run-test "Service discovery" {
    let services = (list-service-names)
    if ($services | is-empty) {
      error make {msg: "No services found"}
    }
    if $verbose_flag { print $"    Found ($services | length) services" }
    true
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: TLS filtering
  let test2 = (run-test "TLS filtering (--tls-only)" {
    let tls_services = (list-services --tls-only)
    if $verbose_flag { print $"    Found ($tls_services | length) TLS-enabled services" }
    true
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Service existence check
  let test3 = (run-test "Service existence check" {
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
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Get service config
  let test4 = (run-test "Get service config" {
    let all_services = (list-service-names)
    if ($all_services | is-empty) {
      error make {msg: "No services found to get config"}
    }
    let first_svc = ($all_services | first)
    let config = (get-service $first_svc)
    if not ("name" in ($config | columns)) {
      error make {msg: $"Service config for ($first_svc) missing 'name' field"}
    }
    if $verbose_flag { print $"    Config name: ($config.name)" }
    true
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Service config completeness
  let test5 = (run-test "Service config completeness" {
    use ../lib/platforms/core.nu [check-platforms-manifest-exists]
    let all_services = (list-service-names)
    for svc in $all_services {
      let config = (get-service $svc)
      let has_platforms = (check-platforms-manifest-exists $svc)
      
      # Always required fields
      let required_fields = ["name", "context"]
      
      # Dockerfile is required only for single-platform services
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
    if $verbose_flag { print $"    All services have required fields" }
    true
  } $verbose_flag)
  $results = ($results | append $test5)

  # Test 6: Platform manifest integrity for all multi-platform services
  let test6 = (run-test "Platform manifest integrity (all multi-platform services)" {
    use ../lib/platforms/core.nu [
      check-platforms-manifest-exists load-platforms-manifest
      get-platform-names get-default-platform
    ]
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
    if $verbose_flag {
      let multi = ($all_services | where {|svc|
        check-platforms-manifest-exists $svc
      })
      print $"    Checked ($multi | length) multi-platform services"
    }
    true
  } $verbose_flag)
  $results = ($results | append $test6)

  # Test 7: TLS-only filtering is consistent with per-service config
  let test7 = (run-test "TLS-only filtering consistency" {
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
    if $verbose_flag { print $"    TLS-enabled services: ($actual_tls | str join ', ')" }
    true
  } $verbose_flag)
  $results = ($results | append $test7)

  print-test-summary $results

  if ($results | any {|r| not $r}) {
    exit 1
  }
}
