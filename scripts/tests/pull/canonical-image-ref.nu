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

# compute-canonical-image-ref tests.

use ../../lib/build/pull.nu [compute-canonical-image-ref]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    local_registry_info
    github_registry_info
    forgejo_registry_info
]

export def canonical-image-ref-tests [verbose: bool] {
    [
        (run-test "compute-canonical-image-ref: single-platform local" {
            let ref = (compute-canonical-image-ref "service-a:v1.0.0" (local_registry_info) true)
            if $ref != "service-a:v1.0.0" {
                error make {msg: $"Expected 'service-a:v1.0.0', got: ($ref)"}
            }
            true
        } $verbose),
        (run-test "compute-canonical-image-ref: multi-platform local" {
            let ref = (compute-canonical-image-ref "service-a:v1.0.0:debian" (local_registry_info) true)
            if $ref != "service-a:v1.0.0-debian" {
                error make {msg: $"Expected 'service-a:v1.0.0-debian', got: ($ref)"}
            }
            true
        } $verbose),
        (run-test "compute-canonical-image-ref: single-platform GitHub CI" {
            let ref = (compute-canonical-image-ref "service-a:v1.0.0" (github_registry_info) false)
            if $ref != "ghcr.io/owner/repo/service-a:v1.0.0" {
                error make {msg: $"Expected 'ghcr.io/owner/repo/service-a:v1.0.0', got: ($ref)"}
            }
            true
        } $verbose),
        (run-test "compute-canonical-image-ref: multi-platform GitHub CI" {
            let ref = (compute-canonical-image-ref "service-b:v2.0.0:production" (github_registry_info) false)
            if $ref != "ghcr.io/owner/repo/service-b:v2.0.0-production" {
                error make {msg: $"Expected 'ghcr.io/owner/repo/service-b:v2.0.0-production', got: ($ref)"}
            }
            true
        } $verbose),
        (run-test "compute-canonical-image-ref: Forgejo CI" {
            let ref = (compute-canonical-image-ref "service:v1.0.0" (forgejo_registry_info) false)
            if $ref != "git.example.io/org/containers/service:v1.0.0" {
                error make {msg: $"Expected 'git.example.io/org/containers/service:v1.0.0', got: ($ref)"}
            }
            true
        } $verbose),
    ]
}
