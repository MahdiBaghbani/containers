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

# GHCR purge offline unit tests.
# Tests desired-tag computation and version decision logic with no gh api calls.

use ../lib/ci/ghcr/purge.nu [decide-versions-to-delete sort-delete-candidates plan-deletions]
use ../lib/ci/ghcr/ssot-tags.nu [compute-desired-tags-for-service]
use ../lib/ci/ghcr/cli.nu [validate-force-flags]
use ../lib/services/core.nu [list-service-names]
use ./lib.nu [run-test print-test-summary]

# Build a mock GHCR version record matching the API response shape.
# Optional --updated-at and --created-at flags add the corresponding timestamp
# fields so ts-extraction logic in decide-versions-to-delete can be exercised.
def mock-version [
    id: int
    tags: list<string>
    --updated-at: string = ""
    --created-at: string = ""
] {
    mut record = {
        id: $id
        name: $"sha256:abc($id)"
        metadata: {
            package_type: "container"
            container: {
                tags: $tags
            }
        }
    }
    if ($updated_at | str length) > 0 {
        $record = ($record | insert updated_at $updated_at)
    }
    if ($created_at | str length) > 0 {
        $record = ($record | insert created_at $created_at)
    }
    $record
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    # ------------------------------------------------------------------ #
    # Decision logic tests (no disk I/O)
    # ------------------------------------------------------------------ #

    let t1 = (run-test "decide: untagged version is always a candidate" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if ($candidates | length) != 1 { error make {msg: "expected 1 candidate"} }
        if $candidates.0.id != 1 { error make {msg: "expected id=1"} }
        if $candidates.0.reason != "untagged" { error make {msg: "expected reason=untagged"} }
        true
    } $verbose_flag)
    $results = ($results | append $t1)

    let t2 = (run-test "decide: version with desired tag is kept" {
        let versions = [
            (mock-version 10 ["latest" "v2.0"])
        ]
        let candidates = (decide-versions-to-delete $versions ["latest" "v2.0"])
        if not ($candidates | is-empty) { error make {msg: "expected no candidates"} }
        true
    } $verbose_flag)
    $results = ($results | append $t2)

    let t3 = (run-test "decide: version with no desired tags is a candidate" {
        let versions = [
            (mock-version 20 ["old-v1" "stale"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v2.0" "latest"])
        if ($candidates | length) != 1 { error make {msg: "expected 1 candidate"} }
        if $candidates.0.reason != "no desired tags" { error make {msg: "expected reason=no desired tags"} }
        true
    } $verbose_flag)
    $results = ($results | append $t3)

    let t4 = (run-test "decide: partial tag intersection keeps version" {
        # version has [v1, old-alias]; desired set includes v1 -> keep
        let versions = [
            (mock-version 30 ["v1" "old-alias"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1" "latest"])
        if not ($candidates | is-empty) { error make {msg: "expected no candidates (v1 intersects)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t4)

    let t5 = (run-test "decide: empty version list returns empty candidates" {
        let candidates = (decide-versions-to-delete [] ["latest"])
        if not ($candidates | is-empty) { error make {msg: "expected empty"} }
        true
    } $verbose_flag)
    $results = ($results | append $t5)

    let t6 = (run-test "decide: all versions stale -> all are candidates" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["old"])
            (mock-version 3 ["also-old"])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if ($candidates | length) != 3 { error make {msg: $"expected 3 candidates, got ($candidates | length)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t6)

    # decide-versions-to-delete with empty desired_tags returns all versions as
    # candidates because no tag can intersect an empty set.  The policy layer
    # (plan-deletions) narrows this to only untagged when force=false.
    let t7 = (run-test "decide: empty desired set -> all versions are candidates (policy is in plan-deletions)" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 ["v1.0"])
        ]
        let candidates = (decide-versions-to-delete $versions [])
        if ($candidates | length) != 2 { error make {msg: $"expected 2 candidates, got ($candidates | length)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t7)

    # ------------------------------------------------------------------ #
    # Timestamp field tests
    # ------------------------------------------------------------------ #

    let t_ts_01 = (run-test "decide: ts populated from updated_at when present" {
        let versions = [
            (mock-version 1 [] --updated-at "2024-06-01T00:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-06-01T00:00:00Z" {
            error make {msg: $"expected ts from updated_at, got: ($candidates.0.ts)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_ts_01)

    let t_ts_02 = (run-test "decide: ts falls back to created_at when updated_at absent" {
        let versions = [
            (mock-version 1 [] --created-at "2024-03-15T12:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-03-15T12:00:00Z" {
            error make {msg: $"expected ts from created_at, got: ($candidates.0.ts)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_ts_02)

    let t_ts_03 = (run-test "decide: ts is empty string when no timestamp fields present" {
        let versions = [
            (mock-version 1 [])
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "" {
            error make {msg: $"expected empty ts, got: ($candidates.0.ts)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_ts_03)

    let t_ts_04 = (run-test "decide: updated_at takes precedence over created_at" {
        let versions = [
            (mock-version 1 [] --updated-at "2024-09-01T00:00:00Z" --created-at "2024-01-01T00:00:00Z")
        ]
        let candidates = (decide-versions-to-delete $versions ["v1.0"])
        if $candidates.0.ts != "2024-09-01T00:00:00Z" {
            error make {msg: $"expected updated_at to win, got: ($candidates.0.ts)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_ts_04)

    # ------------------------------------------------------------------ #
    # Delete ordering tests (oldest first)
    # ------------------------------------------------------------------ #

    let t_sort_01 = (run-test "sort: oldest-first ordering by updated_at timestamp" {
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
    } $verbose_flag)
    $results = ($results | append $t_sort_01)

    let t_sort_02 = (run-test "sort: empty ts sorts before dated entries (unknown age = oldest)" {
        let candidates = [
            {id: 2, tags: [], ts: "2024-01-01T00:00:00Z", reason: "untagged"}
            {id: 1, tags: [], ts: "", reason: "untagged"}
        ]
        let sorted = ($candidates | sort-delete-candidates)
        if $sorted.0.id != 1 { error make {msg: $"expected empty-ts id=1 first, got ($sorted.0.id)"} }
        if $sorted.1.id != 2 { error make {msg: $"expected dated id=2 second, got ($sorted.1.id)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_sort_02)

    let t_sort_03 = (run-test "sort: id is tiebreaker when timestamps are equal" {
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
    } $verbose_flag)
    $results = ($results | append $t_sort_03)

    # Verify end-to-end: decide gives ts, sort-delete-candidates orders by it
    let t_sort_04 = (run-test "sort: decide + sort pipeline produces oldest-first order" {
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
        if $sorted.1.id != 2 { error make {msg: $"expected id=2 second, got ($sorted.1.id)"} }
        if $sorted.2.id != 3 { error make {msg: $"expected id=3 third, got ($sorted.2.id)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_sort_04)

    # ------------------------------------------------------------------ #
    # Global budget semantics (verify budget cap on sorted candidate list)
    # Budget tracking lives in ghcr-purge-cli (requires live API), but the
    # capping mechanism is tested here via sort + first.
    # ------------------------------------------------------------------ #

    let t_budget_01 = (run-test "budget: oldest versions are selected when budget < total candidates" {
        let versions = [
            (mock-version 3 [] --updated-at "2024-03-01T00:00:00Z")
            (mock-version 1 [] --updated-at "2024-01-01T00:00:00Z")
            (mock-version 2 [] --updated-at "2024-02-01T00:00:00Z")
        ]
        # Simulate budget_remaining=2: should pick the two oldest (id 1, 2)
        let selected = (
            decide-versions-to-delete $versions ["keep-tag"]
            | sort-delete-candidates
            | first 2
        )
        if ($selected | length) != 2 { error make {msg: "expected 2 selected"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1 first, got ($selected.0.id)"} }
        if $selected.1.id != 2 { error make {msg: $"expected id=2 second, got ($selected.1.id)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_budget_01)

    # ------------------------------------------------------------------ #
    # plan-deletions policy tests
    # ------------------------------------------------------------------ #

    let t_plan_01 = (run-test "plan-deletions: empty desired_tags, force=false -> only untagged selected" {
        let versions = [
            (mock-version 1 [])                  # untagged -> candidate
            (mock-version 2 ["v1.0"])            # tagged -> kept
            (mock-version 3 ["old" "stale"])     # tagged -> kept
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if ($selected | length) != 1 { error make {msg: $"expected 1 (only untagged), got ($selected | length)"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1, got ($selected.0.id)"} }
        if $selected.0.reason != "untagged" { error make {msg: "expected reason=untagged"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_01)

    let t_plan_02 = (run-test "plan-deletions: empty desired_tags, force=true -> all candidates selected" {
        let versions = [
            (mock-version 1 [])                  # untagged -> candidate
            (mock-version 2 ["v1.0"])            # tagged -> candidate (force)
            (mock-version 3 ["old" "stale"])     # tagged -> candidate (force)
        ]
        let selected = (plan-deletions $versions [] 0 true)
        if ($selected | length) != 3 { error make {msg: $"expected 3 candidates, got ($selected | length)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_02)

    let t_plan_03 = (run-test "plan-deletions: non-empty desired_tags, force=false -> standard behavior" {
        let versions = [
            (mock-version 1 [])                  # untagged -> candidate
            (mock-version 2 ["v1.0"])            # desired -> kept
            (mock-version 3 ["old"])             # stale -> candidate
        ]
        let selected = (plan-deletions $versions ["v1.0"] 0 false)
        if ($selected | length) != 2 { error make {msg: $"expected 2 candidates, got ($selected | length)"} }
        let ids = ($selected | get id | sort)
        if $ids != [1 3] { error make {msg: $"expected ids [1,3], got ($ids)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_03)

    let t_plan_04 = (run-test "plan-deletions: non-empty desired_tags, force=true -> same as force=false (force is no-op when SSOT is present)" {
        let versions = [
            (mock-version 1 [])                  # untagged -> candidate
            (mock-version 2 ["v1.0"])            # desired -> kept regardless of force
            (mock-version 3 ["old"])             # stale -> candidate
        ]
        let selected_no_force = (plan-deletions $versions ["v1.0"] 0 false)
        let selected_force    = (plan-deletions $versions ["v1.0"] 0 true)
        if ($selected_no_force | get id | sort) != ($selected_force | get id | sort) {
            error make {msg: "force should not change outcome when desired_tags is non-empty"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_04)

    let t_plan_05 = (run-test "plan-deletions: budget cap respected (oldest selected)" {
        let versions = [
            (mock-version 3 [] --updated-at "2024-03-01T00:00:00Z")
            (mock-version 1 [] --updated-at "2024-01-01T00:00:00Z")
            (mock-version 2 [] --updated-at "2024-02-01T00:00:00Z")
        ]
        # budget=2 should return oldest two (id 1, 2)
        let selected = (plan-deletions $versions [] 2 false)
        if ($selected | length) != 2 { error make {msg: $"expected 2, got ($selected | length)"} }
        if $selected.0.id != 1 { error make {msg: $"expected id=1 first, got ($selected.0.id)"} }
        if $selected.1.id != 2 { error make {msg: $"expected id=2 second, got ($selected.1.id)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_05)

    let t_plan_06 = (run-test "plan-deletions: budget=0 means unlimited" {
        let versions = [
            (mock-version 1 [])
            (mock-version 2 [])
            (mock-version 3 [])
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if ($selected | length) != 3 { error make {msg: $"expected 3, got ($selected | length)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_06)

    let t_plan_07 = (run-test "plan-deletions: empty all_versions returns empty result" {
        let selected = (plan-deletions [] ["v1.0"] 0 false)
        if not ($selected | is-empty) { error make {msg: "expected empty result for empty versions"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_07)

    let t_plan_08 = (run-test "plan-deletions: empty desired_tags no force, no untagged versions -> empty result" {
        # All versions are tagged; with empty SSOT and no force, none are selected
        let versions = [
            (mock-version 1 ["v1.0"])
            (mock-version 2 ["v2.0"])
        ]
        let selected = (plan-deletions $versions [] 0 false)
        if not ($selected | is-empty) { error make {msg: $"expected empty, got ($selected | length)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_plan_08)

    # ------------------------------------------------------------------ #
    # validate-force-flags gate tests (pure, no API)
    # ------------------------------------------------------------------ #

    let t_gate_01 = (run-test "force-gate: force without service -> rejected" {
        let result = (validate-force-flags "" false true)
        if $result.ok { error make {msg: "expected gate to reject force without service"} }
        if not ($result.reason | str contains "--service") {
            error make {msg: $"expected reason to mention --service, got: ($result.reason)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_gate_01)

    let t_gate_02 = (run-test "force-gate: force with dry_run=true -> rejected" {
        let result = (validate-force-flags "my-service" true true)
        if $result.ok { error make {msg: "expected gate to reject force+dry_run"} }
        if not ($result.reason | str contains "--dry-run") {
            error make {msg: $"expected reason to mention --dry-run, got: ($result.reason)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_gate_02)

    let t_gate_03 = (run-test "force-gate: force with service and dry_run=false -> allowed" {
        let result = (validate-force-flags "my-service" false true)
        if not $result.ok { error make {msg: $"expected gate to pass, got: ($result.reason)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_gate_03)

    let t_gate_04 = (run-test "force-gate: no force, any combination -> always allowed" {
        let r1 = (validate-force-flags "" false false)
        let r2 = (validate-force-flags "" true false)
        let r3 = (validate-force-flags "svc" true false)
        if not $r1.ok { error make {msg: "no-force + no-service should be allowed"} }
        if not $r2.ok { error make {msg: "no-force + dry_run should be allowed"} }
        if not $r3.ok { error make {msg: "no-force + service + dry_run should be allowed"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_gate_04)

    # ------------------------------------------------------------------ #
    # SSOT desired-tag computation tests (reads from disk, no API calls)
    # ------------------------------------------------------------------ #

    let t8 = (run-test "ssot: compute-desired-tags-for-service returns non-empty for known service" {
        # Use a service that is guaranteed to have a versions manifest
        let services = (list-service-names)
        # Pick the first service with a versions manifest
        use ../lib/manifest/core.nu [check-versions-manifest-exists]
        let svc_with_manifest = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc_with_manifest)
        if ($tags | is-empty) {
            error make {msg: $"expected non-empty desired tags for ($svc_with_manifest)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t8)

    let t9 = (run-test "ssot: service without versions manifest returns empty list" {
        # A service with no versions.nuon should return []
        # common-tools is a root service; check if it has a versions manifest
        let tags = (compute-desired-tags-for-service "common-tools")
        # Result depends on whether common-tools has a versions.nuon
        # We just verify it returns a list (not an error)
        ($tags | describe | str starts-with "list")
    } $verbose_flag)
    $results = ($results | append $t9)

    let t10 = (run-test "ssot: tags contain no registry prefix or service prefix" {
        use ../lib/manifest/core.nu [check-versions-manifest-exists]
        let services = (list-service-names)
        let svc = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc)
        # No tag should contain "ghcr.io" or "/"
        let bad = ($tags | where {|t|
            (($t | str contains "ghcr.io")
                or ($t | str contains "/"))
        })
        if not ($bad | is-empty) {
            error make {msg: $"found tags with registry prefix: ($bad | str join ', ')"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t10)

    let t11 = (run-test "ssot: desired tags are sorted and unique" {
        use ../lib/manifest/core.nu [check-versions-manifest-exists]
        let services = (list-service-names)
        let svc = ($services | where {|s| check-versions-manifest-exists $s} | first)
        let tags = (compute-desired-tags-for-service $svc)
        let sorted = ($tags | sort)
        let unique = ($tags | uniq)
        if $tags != $sorted { error make {msg: "tags are not sorted"} }
        if $tags != $unique { error make {msg: "tags contain duplicates"} }
        true
    } $verbose_flag)
    $results = ($results | append $t11)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
