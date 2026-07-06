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

# sort-delete-candidates and ordering tests

use ../../lib/ci/ghcr/purge.nu [decide-versions-to-delete sort-delete-candidates]
use ../lib.nu [run-test]
use ./_mocks.nu [mock-version]

export def test-sort-oldest-first [verbose: bool] {
    run-test "sort: oldest-first ordering by updated_at timestamp" {
        let candidates = [
            {id: 3, tags: [], ts: "2024-03-01T00:00:00Z", reason: "untagged"}
            {id: 1, tags: [], ts: "2024-01-01T00:00:00Z", reason: "untagged"}
            {id: 2, tags: [], ts: "2024-02-01T00:00:00Z", reason: "untagged"}
        ]
        let sorted = ($candidates | sort-delete-candidates)
        if $sorted.0.id != 1 { error make {msg: $"expected id=1 first, got ($sorted.0.id)"} }
        if $sorted.1.id != 2 { error make {msg: $"expected id=2 second, got ($sorted.1.id)"} }
        if $sorted.2.id != 3 { error make {msg: $"expected id=3 third, got ($sorted.2.id)"} }
        true
    } $verbose
}

export def test-sort-empty-ts-first [verbose: bool] {
    run-test "sort: empty ts sorts before dated entries (unknown age = oldest)" {
        let candidates = [
            {id: 2, tags: [], ts: "2024-01-01T00:00:00Z", reason: "untagged"}
            {id: 1, tags: [], ts: "", reason: "untagged"}
        ]
        let sorted = ($candidates | sort-delete-candidates)
        if $sorted.0.id != 1 { error make {msg: $"expected empty-ts id=1 first, got ($sorted.0.id)"} }
        if $sorted.1.id != 2 { error make {msg: $"expected dated id=2 second, got ($sorted.1.id)"} }
        true
    } $verbose
}

export def test-sort-id-tiebreaker [verbose: bool] {
    run-test "sort: id is tiebreaker when timestamps are equal" {
        let ts = "2024-01-01T00:00:00Z"
        let candidates = [
            {id: 3, tags: [], ts: $ts, reason: "untagged"}
            {id: 1, tags: [], ts: $ts, reason: "untagged"}
            {id: 2, tags: [], ts: $ts, reason: "untagged"}
        ]
        let sorted = ($candidates | sort-delete-candidates)
        if $sorted.0.id != 1 { error make {msg: $"expected id=1 first, got ($sorted.0.id)"} }
        if $sorted.1.id != 2 { error make {msg: $"expected id=2 second, got ($sorted.1.id)"} }
        if $sorted.2.id != 3 { error make {msg: $"expected id=3 third, got ($sorted.2.id)"} }
        true
    } $verbose
}

export def test-sort-decide-pipeline [verbose: bool] {
    run-test "sort: decide + sort pipeline produces oldest-first order" {
        let versions = [
            (mock-version 3 [] --updated-at "2024-03-01T00:00:00Z")
            (mock-version 1 [] --updated-at "2024-01-01T00:00:00Z")
            (mock-version 2 [] --updated-at "2024-02-01T00:00:00Z")
        ]
        let sorted = (
            decide-versions-to-delete $versions ["keep-tag"]
            | sort-delete-candidates
        )
        if $sorted.0.id != 1 { error make {msg: $"expected id=1 first, got ($sorted.0.id)"} }
        if $sorted.1.id != 2 { error make {msg: $"expected id=2 second, got ($sorted.2.id)"} }
        if $sorted.2.id != 3 { error make {msg: $"expected id=3 third, got ($sorted.2.id)"} }
        true
    } $verbose
}

export def test-budget-oldest-selected [verbose: bool] {
    run-test "budget: oldest versions are selected when budget < total candidates" {
        let versions = [
            (mock-version 3 [] --updated-at "2024-03-01T00:00:00Z")
            (mock-version 1 [] --updated-at "2024-01-01T00:00:00Z")
            (mock-version 2 [] --updated-at "2024-02-01T00:00:00Z")
        ]
        let selected = (
            decide-versions-to-delete $versions ["keep-tag"]
            | sort-delete-candidates
            | first 2
        )
        if ($selected | length) != 2 { error make {msg: "expected 2 selected"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1 first, got ($selected.0.id)"} }
        if $selected.1.id != 2 { error make {msg: $"expected id=2 second, got ($selected.1.id)"} }
        true
    } $verbose
}
