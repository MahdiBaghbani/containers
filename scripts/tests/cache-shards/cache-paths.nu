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

# get-owner-cache-dir, get-manifest-path, and get-image-tarball-path helpers.

use ../../lib/build/cache.nu [
    get-owner-cache-dir get-manifest-path get-image-tarball-path
]
use ../lib.nu [run-test]

export def cache-paths-tests [verbose: bool] {
    [
        (run-test "get-owner-cache-dir returns /tmp/docker-images/<service>" {
            let dir = (get-owner-cache-dir "my-svc")
            $dir == "/tmp/docker-images/my-svc"
        } $verbose)
        (run-test "get-manifest-path returns .../manifest.nuon" {
            let p = (get-manifest-path "my-svc")
            $p == "/tmp/docker-images/my-svc/manifest.nuon"
        } $verbose)
        (run-test "get-image-tarball-path strips sha256: prefix" {
            let p = (get-image-tarball-path "my-svc" "sha256:deadbeef")
            $p == "/tmp/docker-images/my-svc/deadbeef.tar.zst"
        } $verbose)
        (run-test "get-image-tarball-path works without sha256: prefix" {
            let p = (get-image-tarball-path "my-svc" "deadbeef")
            $p == "/tmp/docker-images/my-svc/deadbeef.tar.zst"
        } $verbose)
    ]
}
