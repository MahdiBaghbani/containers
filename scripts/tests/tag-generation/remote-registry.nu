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

# GitHub CI -> GHCR and Forgejo CI -> Forgejo remote registry tags.

use ../../lib/build/tags.nu [generate-tags]
use ../lib.nu [run-test]
use ./_fixtures.nu [forgejo_registry_info registry_info]

export def remote-registry-tests [verbose: bool] {
    let reg = (registry_info)
    let forgejo_reg = (forgejo_registry_info)
    [
        (run-test "Remote registry tag format (GitHub CI - GHCR only)" {
            let version_spec = {name: "v1.0.0", latest: true}
            let tags = (generate-tags "my-service" $version_spec false $reg "debian" "debian")
            let ghcr_tags = ($tags | where {|t| $t | str starts-with "ghcr.io"})
            let forgejo_tags = ($tags | where {|t| $t | str starts-with "registry.example.com"})
            if ($ghcr_tags | length) == 0 {
                error make {msg: "No GHCR registry tags found"}
            }
            if ($forgejo_tags | length) > 0 {
                error make {msg: "Forgejo tags should not be generated in GitHub CI"}
            }
            let expected_base_tags = ["v1.0.0-debian", "v1.0.0", "latest-debian", "latest"]
            for base_tag in $expected_base_tags {
                let ghcr_tag = $"ghcr.io/ocm/my-service:($base_tag)"
                if not ($ghcr_tag in $ghcr_tags) {
                    error make {msg: $"Missing GHCR tag: ($ghcr_tag)"}
                }
            }
            true
        } $verbose),
        (run-test "Remote registry tag format (Forgejo CI - Forgejo only)" {
            let version_spec = {name: "v1.0.0", latest: true}
            let tags = (generate-tags "my-service" $version_spec false $forgejo_reg "debian" "debian")
            let forgejo_tags = ($tags | where {|t| $t | str starts-with "registry.example.com"})
            let ghcr_tags = ($tags | where {|t| $t | str starts-with "ghcr.io"})
            if ($forgejo_tags | length) == 0 {
                error make {msg: "No Forgejo registry tags found"}
            }
            if ($ghcr_tags | length) > 0 {
                error make {msg: "GHCR tags should not be generated in Forgejo CI"}
            }
            let expected_base_tags = ["v1.0.0-debian", "v1.0.0", "latest-debian", "latest"]
            for base_tag in $expected_base_tags {
                let forgejo_tag = $"registry.example.com/ocm/my-service:($base_tag)"
                if not ($forgejo_tag in $forgejo_tags) {
                    error make {msg: $"Missing Forgejo tag: ($forgejo_tag)"}
                }
            }
            true
        } $verbose),
    ]
}
