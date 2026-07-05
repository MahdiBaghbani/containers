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

# latest: true/false, empty tags, and missing tags field.

use ../../lib/build/tags.nu [generate-tags]
use ../lib.nu [run-test]
use ./_fixtures.nu [assert-tags-equal registry_info]

export def version-latest-tags-tests [verbose: bool] {
    let reg = (registry_info)
    [
        (run-test "Version without custom tags (latest: false)" {
            let version_spec = {name: "v1.0.0"}
            let tags_default = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            let tags_other = (generate-tags "my-service" $version_spec true $reg "alpine" "debian")
            assert-tags-equal $tags_default ["my-service:v1.0.0-debian", "my-service:v1.0.0"] "Default platform tag"
            assert-tags-equal $tags_other ["my-service:v1.0.0-alpine"] "Other platform tag"
            true
        } $verbose),
        (run-test "Version without custom tags (latest: true)" {
            let version_spec = {name: "v1.0.0", latest: true}
            let tags_default = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            let tags_other = (generate-tags "my-service" $version_spec true $reg "alpine" "debian")
            assert-tags-equal $tags_default [
                "my-service:v1.0.0-debian",
                "my-service:v1.0.0",
                "my-service:latest-debian",
                "my-service:latest",
            ] "Default platform tag"
            assert-tags-equal $tags_other [
                "my-service:v1.0.0-alpine",
                "my-service:latest-alpine",
            ] "Other platform tag"
            true
        } $verbose),
    ]
}

export def empty-missing-tags-tests [verbose: bool] {
    let reg = (registry_info)
    [
        (run-test "Empty tags array" {
            let version_spec = {name: "v1.0.0", latest: true, tags: []}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            assert-tags-equal $tags [
                "my-service:v1.0.0-debian",
                "my-service:v1.0.0",
                "my-service:latest-debian",
                "my-service:latest",
            ]
            true
        } $verbose),
        (run-test "Missing tags field" {
            let version_spec = {name: "v1.0.0", latest: true}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian")
            assert-tags-equal $tags [
                "my-service:v1.0.0-debian",
                "my-service:v1.0.0",
                "my-service:latest-debian",
                "my-service:latest",
            ]
            true
        } $verbose),
    ]
}
