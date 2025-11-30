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

use ../lib/services.nu [list-services list-service-names service-exists get-service]
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
    if $verbose_flag { print $"    Found ($services | length) service(s)" }
  } $verbose_flag)
  $results = ($results | append $test1)
  
  # Test 2: TLS filtering
  let test2 = (run-test "TLS filtering (--tls-only)" {
    let tls_services = (list-services --tls-only)
    if $verbose_flag { print $"    Found ($tls_services | length) TLS-enabled service(s)" }
  } $verbose_flag)
  $results = ($results | append $test2)
  
  # Test 3: Service existence check
  let test3 = (run-test "Service existence check" {
    if not (service-exists "revad-base") {
      error make {msg: "revad-base service should exist"}
    }
    if (service-exists "nonexistent-service") {
      error make {msg: "nonexistent-service should not exist"}
    }
  } $verbose_flag)
  $results = ($results | append $test3)
  
  # Test 4: Get service config
  let test4 = (run-test "Get service config" {
    let config = (get-service "revad-base")
    if not ("name" in ($config | columns)) {
      error make {msg: "Service config missing 'name' field"}
    }
    if $verbose_flag { print $"    Config name: ($config.name)" }
  } $verbose_flag)
  $results = ($results | append $test4)
  
  # Test 5: Service config completeness
  let test5 = (run-test "Service config completeness" {
    use ../lib/platforms.nu [check-platforms-manifest-exists]
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
  } $verbose_flag)
  $results = ($results | append $test5)
  
  print-test-summary $results
  
  if ($results | any {|r| not $r}) {
    exit 1
  }
}
