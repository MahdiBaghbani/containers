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

# SSOT desired-tag computation for GHCR purge.
# Derives the full set of tag names that SHOULD exist for each service,
# based on versions.nuon + platforms.nuon.  Tags outside this set are stale.

use ../../services/core.nu [list-service-names]
use ../../manifest/core.nu [check-versions-manifest-exists load-versions-manifest]
use ../../platforms/core.nu [
    check-platforms-manifest-exists
    load-platforms-manifest
    get-default-platform
    get-platform-names
]
use ../../build/tags.nu [generate-tags]

# Compute desired tag names for one service from SSOT.
# Returns list<string> of bare tag names (no registry or service prefix).
export def compute-desired-tags-for-service [service: string] {
    if not (check-versions-manifest-exists $service) {
        return []
    }

    let manifest = (load-versions-manifest $service)
    let versions = (try { $manifest.versions } catch { [] })

    let has_platforms = (check-platforms-manifest-exists $service)
    let pm = (if $has_platforms { load-platforms-manifest $service } else { null })
    let platform_names = (if $has_platforms { get-platform-names $pm } else { [] })
    let default_platform = (if $has_platforms { get-default-platform $pm } else { "" })

    # is_local=true produces "service:tag" strings; registry_info is ignored.
    let fake_registry = {}

    mut tag_names = []

    for version_spec in $versions {
        if ($platform_names | is-empty) {
            let full_tags = (generate-tags $service $version_spec true $fake_registry "" "")
            let names = ($full_tags | each {|t| $t | split row ":" | last })
            $tag_names = ($tag_names | append $names)
        } else {
            for plat in $platform_names {
                let full_tags = (generate-tags $service $version_spec true $fake_registry $plat $default_platform)
                let names = ($full_tags | each {|t| $t | split row ":" | last })
                $tag_names = ($tag_names | append $names)
            }
        }
    }

    $tag_names | uniq | sort
}

# Compute desired tags for all services (or one when service_filter is set).
# Returns record: { service_name: list<string> }
export def compute-all-desired-tags [service_filter: string = ""] {
    let services = (if ($service_filter | str length) > 0 {
        [$service_filter]
    } else {
        list-service-names
    })

    $services | reduce --fold {} {|svc, acc|
        let tags = (compute-desired-tags-for-service $svc)
        $acc | insert $svc $tags
    }
}
