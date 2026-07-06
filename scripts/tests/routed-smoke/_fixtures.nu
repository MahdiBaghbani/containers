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

# Routed-smoke suite-local fixtures and dockypody-in-repo helpers.

export def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

export def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    mkdir ($tmp | path join "scripts")
    ^git -C $tmp init -q
    $tmp
}

export def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

export def dockypody-entry [] {
    "scripts/dockypody.nu" | path expand
}

export def run-dockypody-in-repo [repo: string, args: list<string>] {
    let entry = (dockypody-entry)
    do -i { cd $repo; ^nu $entry ...$args } | complete
}

export def seed-tracked-service [repo: string, name: string = "test-svc"] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
}

export def seed-service-with-git-source [
    repo: string,
    name: string = "test-svc",
    fanout_capable: bool = false
] {
    seed-tracked-service $repo $name
    mkdir ($repo | path join $"services/($name)")
    mut version_entry = { name: "v1", overrides: {} }
    if $fanout_capable {
        $version_entry = ($version_entry | merge { latest: true, tags: ["extra"] })
    }
    {
        default: "v1"
        versions: [$version_entry]
        defaults: {
            sources: {
                my_src: {
                    url: "https://example.com/repo.git"
                    ref: "main"
                }
            }
        }
    } | save -f ($repo | path join $"services/($name)/versions.nuon")
}
