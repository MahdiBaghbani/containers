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

# CI dependency helpers for direct dependency resolution
# Used by CI scripts to determine which dependency caches to restore

use ./manifest.nu [check-versions-manifest-exists load-versions-manifest]

# Extract service names from a dependencies record
# Returns list of service names (uses dep.service if present, otherwise the key)
def extract-dep-services [deps: record] {
    if ($deps | is-empty) {
        return []
    }
    $deps | columns | each {|dep_key|
        let dep = ($deps | get $dep_key)
        try { $dep.service } catch { $dep_key }
    }
}

# Add services to accumulator, deduplicating while preserving order
def merge-services [acc: list, services: list] {
    $services | reduce --fold $acc {|svc, merged|
        if $svc in $merged {
            $merged
        } else {
            $merged | append $svc
        }
    }
}

# Get direct dependency service names for a service (non-recursive)
# Directly parses versions.nuon to extract dependency service names from:
# - defaults.dependencies
# - version overrides.dependencies
# - version overrides.platforms.{platform}.dependencies
# Returns deduplicated list preserving discovery order.
export def get-direct-dependency-services [service: string] {
    if not (check-versions-manifest-exists $service) {
        return []
    }

    let manifest = (load-versions-manifest $service)
    mut all_deps = []

    # 1. Extract from defaults.dependencies
    let default_deps = (try { $manifest.defaults.dependencies } catch { {} })
    let default_services = (extract-dep-services $default_deps)
    $all_deps = (merge-services $all_deps $default_services)

    # 2. Extract from each version's overrides
    let versions = (try { $manifest.versions } catch { [] })
    for version in $versions {
        # Version-level overrides.dependencies
        let version_deps = (try { $version.overrides.dependencies } catch { {} })
        let version_services = (extract-dep-services $version_deps)
        $all_deps = (merge-services $all_deps $version_services)

        # Platform-specific overrides.platforms.{platform}.dependencies
        let platforms = (try { $version.overrides.platforms } catch { {} })
        if not ($platforms | is-empty) {
            for platform_name in ($platforms | columns) {
                let platform_cfg = ($platforms | get $platform_name)
                let platform_deps = (try { $platform_cfg.dependencies } catch { {} })
                let platform_services = (extract-dep-services $platform_deps)
                $all_deps = (merge-services $all_deps $platform_services)
            }
        }
    }

    $all_deps
}

# Get all transitive dependency service names for a service (recursive)
# Walks the full dependency tree to find all services needed to build this service.
# Returns deduplicated list in topological order (deepest deps first).
export def get-all-dependency-services [service: string] {
    mut result = []
    mut queue = (get-direct-dependency-services $service)
    mut visited = []

    # BFS through dependency tree
    while not ($queue | is-empty) {
        let current = ($queue | first)
        $queue = ($queue | skip 1)

        if $current in $visited {
            continue
        }

        $visited = ($visited | append $current)

        # Get deps of current service and add to queue
        let current_deps = (get-direct-dependency-services $current)
        for dep in $current_deps {
            if not ($dep in $visited) {
                $queue = ($queue | append $dep)
            }
        }

        # Prepend to result (deepest deps first for topological order)
        $result = ([$current] | append $result)
    }

    # Deduplicate while preserving order
    mut final = []
    for svc in $result {
        if not ($svc in $final) {
            $final = ($final | append $svc)
        }
    }
    $final
}
