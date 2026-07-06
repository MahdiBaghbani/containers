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

# plan-deletions policy tests

use ../../lib/ci/ghcr/purge.nu [plan-deletions]
use ../lib.nu [run-test]
use ./_mocks.nu [mock-version]

export def test-plan-empty-desired-no-force [verbose: bool] {
    run-test "plan-deletions: empty desired_tags, force=false -> only untagged selected" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
            (mock-version 3 ["old" "stale"])
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if ($selected | length) != 1 { error make {msg: $"expected 1 \(only untagged\), got ($selected | length)"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1, got ($selected.0.id)"} }
        if $selected.0.reason != "untagged" { error make {msg: "expected reason=untagged"} }
        true
    } $verbose
}

export def test-plan-empty-desired-force [verbose: bool] {
    run-test "plan-deletions: empty desired_tags, force=true -> all candidates selected" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
            (mock-version 3 ["old" "stale"])
        ]
        let selected = (plan-deletions $versions [] 0 true)
        if ($selected | length) != 3 { error make {msg: $"expected 3 candidates, got ($selected | length)"} }
        true
    } $verbose
}

export def test-plan-nonempty-desired-no-force [verbose: bool] {
    run-test "plan-deletions: non-empty desired_tags, force=false -> standard behavior" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
            (mock-version 3 ["old"])
        ]
        let selected = (plan-deletions $versions ["v1.0"] 0 false)
        if ($selected | length) != 2 { error make {msg: $"expected 2 candidates, got ($selected | length)"} }
        let ids = ($selected | get id | sort)
        if $ids != [1 3] { error make {msg: $"expected ids [1,3], got ($ids)"} }
        true
    } $verbose
}

export def test-plan-force-noop-with-ssot [verbose: bool] {
    run-test "plan-deletions: non-empty desired_tags, force=true -> same as force=false (force is no-op when SSOT is present)" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
            (mock-version 3 ["old"])
        ]
        let selected_no_force = (plan-deletions $versions ["v1.0"] 0 false)
        let selected_force    = (plan-deletions $versions ["v1.0"] 0 true)
        if ($selected_no_force | get id | sort) != ($selected_force | get id | sort) {
            error make {msg: "force should not change outcome when desired_tags is non-empty"}
        }
        true
    } $verbose
}

export def test-plan-budget-cap [verbose: bool] {
    run-test "plan-deletions: budget cap respected (oldest selected)" {
        let versions = [
            (mock-version 3 [] --updated-at "2024-03-01T00:00:00Z")
            (mock-version 1 [] --updated-at "2024-01-01T00:00:00Z")
            (mock-version 2 [] --updated-at "2024-02-01T00:00:00Z")
        ]
        let selected = (plan-deletions $versions [] 2 false)
        if ($selected | length) != 2 { error make {msg: $"expected 2, got ($selected | length)"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1 first, got ($selected.0.id)"} }
        if $selected.1.id != 2 { error make {msg: $"expected id=2 second, got ($selected.1.id)"} }
        true
    } $verbose
}

export def test-plan-budget-zero-unlimited [verbose: bool] {
    run-test "plan-deletions: budget=0 means unlimited" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 [])
            (mock-version 3 [])
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if ($selected | length) != 3 { error make {msg: $"expected 3, got ($selected | length)"} }
        true
    } $verbose
}

export def test-plan-empty-versions [verbose: bool] {
    run-test "plan-deletions: empty all_versions returns empty result" {
        let selected = (plan-deletions [] ["v1.0"] 0 false)
        if not ($selected | is-empty) { error make {msg: "expected empty result for empty versions"} }
        true
    } $verbose
}

export def test-plan-no-untagged-empty-result [verbose: bool] {
    run-test "plan-deletions: empty desired_tags no force, no untagged versions -> empty result" {
        let versions = [
            (mock-version 1 ["v1.0"])
            (mock-version 2 ["v2.0"])
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if not ($selected | is-empty) { error make {msg: $"expected empty, got ($selected | length)"} }
        true
    } $verbose
}
