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

# decide-versions-to-delete tests

use ../../lib/ci/ghcr/purge.nu [decide-versions-to-delete]
use ../lib.nu [run-test]
use ./_mocks.nu [mock-version]

export def test-decide-untagged-is-candidate [verbose: bool] {
    run-test "decide: untagged version is always a candidate" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if ($candidates | length) != 1 { error make {msg: "expected 1 candidate"} }
        if $candidates.0.id != 1 { error make {msg: "expected id=1"} }
        if $candidates.0.reason != "untagged" { error make {msg: "expected reason=untagged"} }
        true
    } $verbose
}

export def test-decide-desired-tag-kept [verbose: bool] {
    run-test "decide: version with desired tag is kept" {
        let versions = [
            (mock-version 10 ["latest" "v2.0"])
        ]
        let candidates = (decide-versions-to-delete $versions ["latest" "v2.0"])
        if not ($candidates | is-empty) { error make {msg: "expected no candidates"} }
        true
    } $verbose
}

export def test-decide-no-desired-tags [verbose: bool] {
    run-test "decide: version with no desired tags is a candidate" {
        let versions = [
            (mock-version 20 ["old-v1" "stale"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v2.0" "latest"])
        if ($candidates | length) != 1 { error make {msg: "expected 1 candidate"} }
        if $candidates.0.reason != "no desired tags" { error make {msg: "expected reason=no desired tags"} }
        true
    } $verbose
}

export def test-decide-partial-intersection [verbose: bool] {
    run-test "decide: partial tag intersection keeps version" {
        let versions = [
            (mock-version 30 ["v1" "old-alias"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1" "latest"])
        if not ($candidates | is-empty) { error make {msg: "expected no candidates (v1 intersects)"} }
        true
    } $verbose
}

export def test-decide-empty-versions [verbose: bool] {
    run-test "decide: empty version list returns empty candidates" {
        let candidates = (decide-versions-to-delete [] ["latest"])
        if not ($candidates | is-empty) { error make {msg: "expected empty"} }
        true
    } $verbose
}

export def test-decide-all-stale [verbose: bool] {
    run-test "decide: all versions stale -> all are candidates" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["old"])
            (mock-version 3 ["also-old"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if ($candidates | length) != 3 { error make {msg: $"expected 3 candidates, got ($candidates | length)"} }
        true
    } $verbose
}

export def test-decide-empty-desired-set [verbose: bool] {
    run-test "decide: empty desired set -> all versions are candidates (policy is in plan-deletions)" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
        ]
        let candidates = (decide-versions-to-delete $versions [])
        if ($candidates | length) != 2 { error make {msg: $"expected 2 candidates, got ($candidates | length)"} }
        true
    } $verbose
}

export def test-decide-ts-from-updated-at [verbose: bool] {
    run-test "decide: ts populated from updated_at when present" {
        let versions = [
            (mock-version 1 [] --updated-at "2024-06-01T00:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-06-01T00:00:00Z" {
            error make {msg: $"expected ts from updated_at, got: ($candidates.0.ts)"}
        }
        true
    } $verbose
}

export def test-decide-ts-from-created-at [verbose: bool] {
    run-test "decide: ts falls back to created_at when updated_at absent" {
        let versions = [
            (mock-version 1 [] --created-at "2024-03-15T12:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-03-15T12:00:00Z" {
            error make {msg: $"expected ts from created_at, got: ($candidates.0.ts)"}
        }
        true
    } $verbose
}

export def test-decide-ts-empty [verbose: bool] {
    run-test "decide: ts is empty string when no timestamp fields present" {
        let versions = [
            (mock-version 1 [])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "" {
            error make {msg: $"expected empty ts, got: ($candidates.0.ts)"}
        }
        true
    } $verbose
}

export def test-decide-ts-updated-at-wins [verbose: bool] {
    run-test "decide: updated_at takes precedence over created_at" {
        let versions = [
            (mock-version 1 [] --updated-at "2024-09-01T00:00:00Z" --created-at "2024-01-01T00:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-09-01T00:00:00Z" {
            error make {msg: $"expected updated_at to win, got: ($candidates.0.ts)"}
        }
        true
    } $verbose
}
