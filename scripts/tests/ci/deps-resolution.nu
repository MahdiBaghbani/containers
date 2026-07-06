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

# CI dependency resolution tests

use ../../lib/ci/deps.nu [get-direct-dependency-services get-all-dependency-services]
use ../../lib/services/core.nu [list-service-names]
use ../lib.nu [run-test]
use ./_dep-scan.nu [compute-expected-deps]

export def test-list-service-names [verbose: bool] {
  run-test "list-service-names returns services" {
    let services = (list-service-names)
    ($services | length) > 0
  } $verbose
}

export def test-direct-dep-resolution [verbose: bool] {
  run-test "Direct dep resolution matches independent manifest scan" {
    use ../../lib/manifest/core.nu [check-versions-manifest-exists]
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let actual = ((get-direct-dependency-services $svc) | sort)
      let expected = ((compute-expected-deps $svc) | sort)
      if $actual != $expected {
        error make {
          msg: $"($svc): dep mismatch. actual=($actual | str join ',') expected=($expected | str join ',')"
        }
      }
    }
    true
  } $verbose
}

export def test-all-direct-deps-known [verbose: bool] {
  run-test "All direct deps are known services" {
    use ../../lib/manifest/core.nu [check-versions-manifest-exists]
    let known = (list-service-names)
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let deps = (get-direct-dependency-services $svc)
      for dep in $deps {
        if not ($dep in $known) {
          error make {msg: $"($svc): dependency '($dep)' is not a known service"}
        }
      }
    }
    true
  } $verbose
}

export def test-transitive-deps [verbose: bool] {
  run-test "Transitive deps are superset of direct deps, exclude self" {
    use ../../lib/manifest/core.nu [check-versions-manifest-exists]
    let all_services = (list-service-names)
    for svc in $all_services {
      if not (check-versions-manifest-exists $svc) { continue }
      let direct = (get-direct-dependency-services $svc)
      if ($direct | is-empty) { continue }
      let all_deps = (get-all-dependency-services $svc)
      for dep in $direct {
        if not ($dep in $all_deps) {
          error make {msg: $"($svc): direct dep '($dep)' missing from transitive deps"}
        }
      }
      if $svc in $all_deps {
        error make {msg: $"($svc): service appears in its own transitive deps \(cycle\)"}
      }
    }
    true
  } $verbose
}

export def test-kasm-base-deps [verbose: bool] {
  run-test "kasm-base direct deps include common-tools" {
    let deps = (get-direct-dependency-services "kasm-base")
    if ($deps | is-empty) {
      error make {msg: "kasm-base has no direct deps (expected common-tools)"}
    }
    if not ("common-tools" in $deps) {
      error make {msg: $"kasm-base deps missing common-tools: ($deps | str join ',')"}
    }
    true
  } $verbose
}

export def test-cypress-deps [verbose: bool] {
  run-test "cypress direct deps include common-tools and kasm-base" {
    let deps = (get-direct-dependency-services "cypress")
    if not ("common-tools" in $deps) {
      error make {msg: $"cypress deps missing common-tools: ($deps | str join ',')"}
    }
    if not ("kasm-base" in $deps) {
      error make {msg: $"cypress deps missing kasm-base: ($deps | str join ',')"}
    }
    true
  } $verbose
}
