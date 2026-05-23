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

# CI domain test suite

use ../lib/ci/deps.nu [get-direct-dependency-services get-all-dependency-services]
use ../lib/services/core.nu [list-service-names]
use ./lib.nu [run-test print-test-summary]

# Build dep_id -> service_name mapping from infra manifests (independent of library).
# Uses platforms.nuon (defaults + per-platform deps) when present,
# otherwise falls back to the base service .nuon dependencies record.
def local-build-dep-mapping [svc: string] {
    let platforms_path = $"services/($svc)/platforms.nuon"
    mut mapping = {}
    if ($platforms_path | path exists) {
        let pm = (open $platforms_path)
        let defaults_deps = (try { $pm.defaults.dependencies } catch { {} })
        if not ($defaults_deps | is-empty) {
            for dep_id in ($defaults_deps | columns) {
                let dep = ($defaults_deps | get $dep_id)
                $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
            }
        }
        let platforms = (try { $pm.platforms } catch { [] })
        for platform in $platforms {
            let pdeps = (try { $platform.dependencies } catch { {} })
            if not ($pdeps | is-empty) {
                for dep_id in ($pdeps | columns) {
                    let dep = ($pdeps | get $dep_id)
                    $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
                }
            }
        }
    } else {
        let service_path = $"services/($svc).nuon"
        if ($service_path | path exists) {
            let sc = (open $service_path)
            let deps = (try { $sc.dependencies } catch { {} })
            if not ($deps | is-empty) {
                for dep_id in ($deps | columns) {
                    let dep = ($deps | get $dep_id)
                    $mapping = ($mapping | upsert $dep_id (try { $dep.service } catch { $dep_id }))
                }
            }
        }
    }
    $mapping
}

# Compute expected direct dependency service names by walking a service's
# versions.nuon at exactly four locations:
#   defaults.dependencies
#   defaults.platforms.<platform>.dependencies
#   each version overrides.dependencies
#   each version overrides.platforms.<platform>.dependencies
# Resolves dep_ids to service names using infra manifests (independent reimplementation).
def compute-expected-deps [svc: string] {
  use ../lib/manifest/core.nu [check-versions-manifest-exists load-versions-manifest]

  if not (check-versions-manifest-exists $svc) { return [] }

  let manifest = (load-versions-manifest $svc)
  let mapping = (local-build-dep-mapping $svc)

  # Resolve dep_ids to service names; unknown dep_ids fall back to the key itself.
  let resolve_ids = {|deps: record|
    if ($deps | is-empty) { return [] }
    $deps | columns | each {|dep_id|
      ($mapping | get --optional $dep_id) | default $dep_id
    }
  }

  let default_names = (do $resolve_ids (try { $manifest.defaults.dependencies } catch { {} }))

  let dp = (try { $manifest.defaults.platforms } catch { {} })
  let default_plat_names = (if ($dp | is-empty) {
    []
  } else {
    $dp | columns | each {|pname|
      do $resolve_ids (try { ($dp | get $pname).dependencies } catch { {} })
    } | flatten
  })

  let version_names = ((try { $manifest.versions } catch { [] }) | each {|version|
    let ver_names = (do $resolve_ids (try { $version.overrides.dependencies } catch { {} }))
    let platforms = (try { $version.overrides.platforms } catch { {} })
    let plat_names = (if ($platforms | is-empty) {
      []
    } else {
      $platforms | columns | each {|pname|
        do $resolve_ids (try { ($platforms | get $pname).dependencies } catch { {} })
      } | flatten
    })
    $ver_names | append $plat_names
  } | flatten)

  ($default_names | append $default_plat_names | append $version_names) | uniq
}

def main [--verbose] {
  mut results = []

  # Test 1: list-service-names returns a non-empty list
  let test1 = (run-test "list-service-names returns services" {
    let services = (list-service-names)
    ($services | length) > 0
  } $verbose)
  $results = ($results | append $test1)

  # Test 2: For each service with a versions manifest, sorted(actual library deps)
  # must equal sorted(expected deps from independent manifest scan).
  let test2 = (run-test "Direct dep resolution matches independent manifest scan" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
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
  } $verbose)
  $results = ($results | append $test2)

  # Test 3: All direct dependencies of every service are known service names.
  let test3 = (run-test "All direct deps are known services" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
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
  } $verbose)
  $results = ($results | append $test3)

  # Test 4: get-all-dependency-services returns a superset of direct deps
  # and never includes the service itself.
  let test4 = (run-test "Transitive deps are superset of direct deps, exclude self" {
    use ../lib/manifest/core.nu [check-versions-manifest-exists]
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
  } $verbose)
  $results = ($results | append $test4)

  # Test 5: kasm-base must declare common-tools as a direct dependency.
  # Regression for defaults.platforms.*.dependencies being missed.
  let test5 = (run-test "kasm-base direct deps include common-tools" {
    let deps = (get-direct-dependency-services "kasm-base")
    if ($deps | is-empty) {
      error make {msg: "kasm-base has no direct deps (expected common-tools)"}
    }
    if not ("common-tools" in $deps) {
      error make {msg: $"kasm-base deps missing common-tools: ($deps | str join ',')"}
    }
    true
  } $verbose)
  $results = ($results | append $test5)

  # Test 6: cypress must declare common-tools and kasm-base as direct dependencies.
  # Regression for defaults.platforms.*.dependencies being missed.
  let test6 = (run-test "cypress direct deps include common-tools and kasm-base" {
    let deps = (get-direct-dependency-services "cypress")
    if not ("common-tools" in $deps) {
      error make {msg: $"cypress deps missing common-tools: ($deps | str join ',')"}
    }
    if not ("kasm-base" in $deps) {
      error make {msg: $"cypress deps missing kasm-base: ($deps | str join ',')"}
    }
    true
  } $verbose)
  $results = ($results | append $test6)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
