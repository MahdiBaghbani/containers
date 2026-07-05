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

# Local-plane single-primary suppression, CI-like qualified tags, tracked-plane fan-out.

use ../../lib/build/tags.nu [generate-tags]
use ../lib.nu [run-test]
use ./_fixtures.nu [assert-tags-equal registry_info]

export def local-plane-tests [verbose: bool] {
    let reg = (registry_info)
    [
        (run-test "Local plane single-primary tag (suppresses latest and extras)" {
            let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0", "v1"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian" true)
            assert-tags-equal $tags ["my-service:v1.0.0-debian"] "Local plane tag"
            true
        } $verbose),
        (run-test "Local plane single-primary tag (single platform)" {
            let version_spec = {name: "v2.0.0", latest: true, tags: ["stable"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "" "" true)
            assert-tags-equal $tags ["my-service:v2.0.0"] "Local plane tag"
            true
        } $verbose),
        (run-test "Local plane CI-like mode uses registry-qualified primary tag" {
            let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0", "v1"]}
            let tags = (generate-tags "my-service" $version_spec false $reg "" "" true)
            assert-tags-equal $tags ["ghcr.io/ocm/my-service:v1.0.0"] "Local plane CI-like tag"
            true
        } $verbose),
        (run-test "Tracked-plane local build retains latest and custom tags" {
            let version_spec = {name: "v1.0.0", latest: true, tags: ["v1.0"]}
            let tags = (generate-tags "my-service" $version_spec true $reg "debian" "debian" false)
            assert-tags-equal $tags [
                "my-service:v1.0.0-debian",
                "my-service:v1.0.0",
                "my-service:latest-debian",
                "my-service:latest",
                "my-service:v1.0-debian",
                "my-service:v1.0",
            ] "Tracked-plane tag"
            true
        } $verbose),
    ]
}
