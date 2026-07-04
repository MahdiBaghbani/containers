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

# GHCR purge suite fixtures and temp-repo helpers

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]

export const ISOLATION_SVC = "test-svc"
export const ISOLATION_TRACKED_V1 = "v1"
export const ISOLATION_TRACKED_V2 = "v2"
export const ISOLATION_LOCAL_ONLY = "dev-local-only"

export def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    ^git -C $tmp init -q
    $tmp
}

export def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

export def run-in-temp-repo [repo: string, block: closure] {
    do -i { cd $repo; do $block }
}

export def seed-tracked-versions [repo: string, versions_manifest: record, name: string] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
    $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

export def save-local-fragment [repo: string, name: string, fragment: record] {
    let mirror = (local-services-path $repo | path join $name)
    mkdir $mirror
    $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

export def seed-tracked-plane-isolation-fixture [repo: string] {
    seed-tracked-versions $repo {
        default: $ISOLATION_TRACKED_V1
        versions: [
            { name: $ISOLATION_TRACKED_V1, overrides: {} }
            { name: $ISOLATION_TRACKED_V2, overrides: {} }
        ]
    } $ISOLATION_SVC
    mkdir (local-root-path $repo)
    save-local-fragment $repo $ISOLATION_SVC {
        versions: [
            { name: $ISOLATION_LOCAL_ONLY, overrides: {} }
            {
                name: $ISOLATION_TRACKED_V2
                overrides: {
                    sources: {
                        my_src: { path: "../local-src" }
                    }
                }
            }
        ]
    }
}
