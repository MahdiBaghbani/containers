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

# Multi-platform default vs non-default platform behavior.

use ../../lib/build/tags.nu [generate-tags]
use ../lib.nu [run-test]
use ./_fixtures.nu [assert-tags-equal registry_info]

export def multi-platform-tests [verbose: bool] {
    let reg = (registry_info)
    [
        (run-test "Multi-platform default platform (unprefixed tags)" {
            let version_spec = {name: "v2.0.0", latest: true, tags: ["v2.0", "v2"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            assert-tags-equal $tags [
                "my-service:v2.0.0-debian",
                "my-service:v2.0.0",
                "my-service:latest-debian",
                "my-service:latest",
                "my-service:v2.0-debian",
                "my-service:v2.0",
                "my-service:v2-debian",
                "my-service:v2",
            ]
            true
        } $verbose),
        (run-test "Multi-platform non-default platform (platform-suffixed only)" {
            let version_spec = {name: "v2.0.0", latest: true, tags: ["v2.0", "v2"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "alpine" "debian")
            assert-tags-equal $tags [
                "my-service:v2.0.0-alpine",
                "my-service:latest-alpine",
                "my-service:v2.0-alpine",
                "my-service:v2-alpine",
            ]
            true
        } $verbose),
    ]
}

export def platforms-nuon-tests [verbose: bool] {
    let reg = (registry_info)
    [
        (run-test "Single platform in platforms.nuon (still gets unprefixed tags)" {
            let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            assert-tags-equal $tags [
                "my-service:v1.0.0-debian",
                "my-service:v1.0.0",
                "my-service:latest-debian",
                "my-service:latest",
                "my-service:v1.0-debian",
                "my-service:v1.0",
            ]
            true
        } $verbose),
    ]
}
