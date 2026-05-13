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

use ../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]

# Merge dep entries from a dependencies record into a dep_id -> service_name mapping.
# Errors if the same dep_id maps to two different service names across callers.
def collect-deps-into-mapping [mapping: record, deps: record, service: string] {
    if ($deps | is-empty) {
        return $mapping
    }
    mut m = $mapping
    for dep_id in ($deps | columns) {
        let dep = ($deps | get $dep_id)
        let resolved = (try { $dep.service } catch { $dep_id })
        let existing = ($m | get --optional $dep_id)
        if $existing != null and $existing != $resolved {
            error make {
                msg: $"($service): dep_id '($dep_id)' maps to '($existing)' and '($resolved)' in different manifests"
            }
        }
        $m = ($m | upsert $dep_id $resolved)
    }
    $m
}

# Build a dep_id -> service_name mapping from infrastructure manifests.
# Uses platforms.nuon (defaults + each platform entry) when it exists,
# otherwise falls back to the base service .nuon dependencies record.
def build-dep-id-mapping [service: string] {
    let platforms_path = $"services/($service)/platforms.nuon"
    mut mapping = {}
    if ($platforms_path | path exists) {
        let pm = (open $platforms_path)
        let defaults_deps = (try { $pm.defaults.dependencies } catch { {} })
        $mapping = (collect-deps-into-mapping $mapping $defaults_deps $service)
        let platforms = (try { $pm.platforms } catch { [] })
        for platform in $platforms {
            let pdeps = (try { $platform.dependencies } catch { {} })
            $mapping = (collect-deps-into-mapping $mapping $pdeps $service)
        }
    } else {
        let service_path = $"services/($service).nuon"
        if ($service_path | path exists) {
            let svc = (open $service_path)
            let deps = (try { $svc.dependencies } catch { {} })
            $mapping = (collect-deps-into-mapping $mapping $deps $service)
        }
    }
    $mapping
}

# Map dep_id keys from a dependencies record to resolved service names.
# Errors if a dep_id has no entry in the mapping (undefined in infra manifests).
def map-dep-ids-to-services [deps: record, mapping: record, service: string] {
    if ($deps | is-empty) {
        return []
    }
    $deps | columns | each {|dep_id|
        let resolved = ($mapping | get --optional $dep_id)
        if $resolved == null {
            error make {
                msg: $"($service): dep_id '($dep_id)' in versions.nuon is not defined in infra manifests"
            }
        }
        $resolved
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

# Get direct dependency service names for a service (non-recursive).
# Resolves dep_ids from versions.nuon to actual service names via infra manifests:
# - single-platform: services/<service>.nuon dependencies
# - multi-platform:  services/<service>/platforms.nuon defaults + per-platform deps
# Scans versions.nuon at defaults.dependencies, defaults.platforms.{platform}.dependencies,
# each version overrides.dependencies, and each version overrides.platforms.{platform}.dependencies.
# Returns deduplicated list preserving discovery order.
export def get-direct-dependency-services [service: string] {
    if not (check-versions-manifest-exists $service) {
        return []
    }

    let manifest = (load-versions-manifest $service)
    let mapping = (build-dep-id-mapping $service)
    mut all_deps = []

    # 1. Extract from defaults.dependencies
    let default_deps = (try { $manifest.defaults.dependencies } catch { {} })
    let default_services = (map-dep-ids-to-services $default_deps $mapping $service)
    $all_deps = (merge-services $all_deps $default_services)

    # 1b. Extract from defaults.platforms.{platform}.dependencies
    let default_platforms = (try { $manifest.defaults.platforms } catch { {} })
    if not ($default_platforms | is-empty) {
        for platform_name in ($default_platforms | columns) {
            let platform_cfg = ($default_platforms | get $platform_name)
            let platform_deps = (try { $platform_cfg.dependencies } catch { {} })
            let platform_services = (map-dep-ids-to-services $platform_deps $mapping $service)
            $all_deps = (merge-services $all_deps $platform_services)
        }
    }

    # 2. Extract from each version's overrides
    let versions = (try { $manifest.versions } catch { [] })
    for version in $versions {
        # Version-level overrides.dependencies
        let version_deps = (try { $version.overrides.dependencies } catch { {} })
        let version_services = (map-dep-ids-to-services $version_deps $mapping $service)
        $all_deps = (merge-services $all_deps $version_services)

        # Platform-specific overrides.platforms.{platform}.dependencies
        let platforms = (try { $version.overrides.platforms } catch { {} })
        if not ($platforms | is-empty) {
            for platform_name in ($platforms | columns) {
                let platform_cfg = ($platforms | get $platform_name)
                let platform_deps = (try { $platform_cfg.dependencies } catch { {} })
                let platform_services = (map-dep-ids-to-services $platform_deps $mapping $service)
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
