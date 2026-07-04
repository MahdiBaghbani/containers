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

# Independent manifest scan for dependency resolution cross-checks

# Build dep_id -> service_name mapping from infra manifests (independent of library).
# Uses platforms.nuon (defaults + per-platform deps) when present,
# otherwise falls back to the base service .nuon dependencies record.
export def local-build-dep-mapping [svc: string] {
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
export def compute-expected-deps [svc: string] {
  use ../../lib/manifest/core.nu [check-versions-manifest-exists load-versions-manifest]

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
