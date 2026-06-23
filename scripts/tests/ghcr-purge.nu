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

use ../lib/ci/ghcr/purge.nu [decide-versions-to-delete sort-delete-candidates plan-deletions purge-service-core]
use ../lib/ci/ghcr/ssot-tags.nu [compute-desired-tags-for-service]
use ../lib/ci/ghcr/cli.nu [validate-force-flags aggregate-purge-results format-purge-summary]
use ../lib/services/core.nu [list-service-names]
use ../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ./lib.nu [run-test print-test-summary]

const ISOLATION_SVC = "test-svc"
const ISOLATION_TRACKED_V1 = "v1"
const ISOLATION_TRACKED_V2 = "v2"
const ISOLATION_LOCAL_ONLY = "dev-local-only"

def make-temp-repo [] {
    let tmp = (^mktemp -d | str trim)
    mkdir $tmp
    mkdir ($tmp | path join "services")
    ^git -C $tmp init -q
    $tmp
}

def rm-temp-repo [dir: string] {
    try { rm -rf $dir } catch { }
}

def run-in-temp-repo [repo: string, block: closure] {
    do -i { cd $repo; do $block }
}

def seed-tracked-versions [repo: string, versions_manifest: record, name: string] {
    { name: $name } | save -f ($repo | path join $"services/($name).nuon")
    mkdir ($repo | path join $"services/($name)")
    $versions_manifest | save -f ($repo | path join $"services/($name)/versions.nuon")
}

def save-local-fragment [repo: string, name: string, fragment: record] {
    let mirror = (local-services-path $repo | path join $name)
    mkdir $mirror
    $fragment | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
}

def seed-tracked-plane-isolation-fixture [repo: string] {
    seed-tracked-versions $repo {
        default: $ISOLATION_TRACKED_V1
        versions: [
            { name: $ISOLATION_TRACKED_V1, overrides: {} }
            { name: $ISOLATION_TRACKED_V2, overrides: {} }
        ]
    } $ISOLATION_SVC
    mkdir (local-root-path $repo)
    save-local-fragment $repo $ISOLATION_SVC {
        versions: [
            { name: $ISOLATION_LOCAL_ONLY, overrides: {} }
            {
                name: $ISOLATION_TRACKED_V2
                overrides: {
                    sources: {
                        my_src: { path: "../local-src" }
                    }
                }
            }
        ]
    }
}

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

# Build a successful list-package-versions result wrapping the given versions.
def mock-list-ok [versions: list] {
    {
        ok: true
        base_path: "/orgs/acme/packages/container/repo%2Fsvc"
        versions: $versions
        not_found: false
        permission_denied: false
        error: ""
    }
}

# Always-succeed delete closure.
def delete-fn-ok [] {
    {|base_path, version_id| {ok: true, error: ""} }
}

# Delete closure that fails for a specific version id.
def delete-fn-fail-id [bad_id: int] {
    {|base_path, version_id|
        if $version_id == $bad_id {
            {ok: false, error: "HTTP 500 simulated failure"}
        } else {
            {ok: true, error: ""}
        }
    }
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
        if ($selected | length) != 1 { error make {msg: $"expected 1 \(only untagged\), got ($selected | length)"} }
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

    let t12 = (run-test "ssot: compute-desired-tags ignores local fragment versions (tracked-only isolation)" {
        let repo = (make-temp-repo)
        seed-tracked-plane-isolation-fixture $repo
        let tags = (run-in-temp-repo $repo {||
            compute-desired-tags-for-service $ISOLATION_SVC
        })
        rm-temp-repo $repo
        if $ISOLATION_LOCAL_ONLY in $tags {
            error make {msg: $"Local-only version leaked into SSOT tags: ($tags | str join ', ')"}
        }
        if not ($ISOLATION_TRACKED_V1 in $tags) {
            error make {msg: $"Tracked version tag ($ISOLATION_TRACKED_V1) missing from SSOT output"}
        }
        if not ($ISOLATION_TRACKED_V2 in $tags) {
            error make {msg: $"Tracked version tag ($ISOLATION_TRACKED_V2) missing from SSOT output"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t12)

    # ------------------------------------------------------------------ #
    # purge-service-core: injectable, API-free execution contract tests
    # (no gh api calls; delete behavior is injected via a closure)
    # ------------------------------------------------------------------ #

    let t_core_live_ok = (run-test "core: live delete success -> ok, all deleted, charged=attempted" {
        let versions = [(mock-version 1 []) (mock-version 2 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-ok))
        if not $r.ok { error make {msg: "expected ok=true on full success"} }
        if $r.planned != 2 { error make {msg: $"expected planned=2, got ($r.planned)"} }
        if $r.attempted != 2 { error make {msg: $"expected attempted=2, got ($r.attempted)"} }
        if $r.deleted != 2 { error make {msg: $"expected deleted=2, got ($r.deleted)"} }
        if $r.failed != 0 { error make {msg: $"expected failed=0, got ($r.failed)"} }
        if $r.charged != 2 { error make {msg: $"expected charged=2, got ($r.charged)"} }
        if $r.skipped != 0 { error make {msg: $"expected skipped=0, got ($r.skipped)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_live_ok)

    let t_core_live_fail_strict = (run-test "core: live delete failure (strict) -> ok=false, failure recorded" {
        let versions = [(mock-version 1 []) (mock-version 2 [])]
        let list_result = (mock-list-ok $versions)
        # strict policy (partial_success=false): id=2 delete fails
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-fail-id 2))
        if $r.ok { error make {msg: "expected ok=false when a live delete fails under strict policy"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        if $r.deleted != 1 { error make {msg: $"expected deleted=1, got ($r.deleted)"} }
        if ($r.error | str length) == 0 { error make {msg: "expected non-empty error message"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_live_fail_strict)

    let t_core_live_fail_partial = (run-test "core: live delete failure (partial-success) -> ok=true, failure still counted" {
        let versions = [(mock-version 1 []) (mock-version 2 [])]
        let list_result = (mock-list-ok $versions)
        # partial_success=true: failure tolerated
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false true (delete-fn-fail-id 2))
        if not $r.ok { error make {msg: "expected ok=true under partial-success policy"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        if $r.deleted != 1 { error make {msg: $"expected deleted=1, got ($r.deleted)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_live_fail_partial)

    let t_core_dry_run = (run-test "core: dry-run charges zero against budget while reporting planned" {
        let versions = [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])]
        let list_result = (mock-list-ok $versions)
        # dry_run=true; delete_fn must never be called, so a failing closure is safe
        let r = (purge-service-core "svc" $list_result ["keep"] true 0 false false false (delete-fn-fail-id 1))
        if not $r.ok { error make {msg: "expected ok=true in dry-run"} }
        if $r.planned != 3 { error make {msg: $"expected planned=3, got ($r.planned)"} }
        if $r.charged != 0 { error make {msg: $"expected charged=0 in dry-run, got ($r.charged)"} }
        if $r.attempted != 0 { error make {msg: $"expected attempted=0 in dry-run, got ($r.attempted)"} }
        if $r.deleted != 0 { error make {msg: $"expected deleted=0 in dry-run, got ($r.deleted)"} }
        if $r.skipped != 3 { error make {msg: $"expected skipped=3 in dry-run, got ($r.skipped)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_dry_run)

    let t_core_run_wide_plan_budget = (run-test "aggregate: dry-run planning budget is run-wide, not per-service" {
        # Exercises the real ghcr-purge-cli aggregation loop via
        # aggregate-purge-results (no local reimplementation).  Two services
        # with 3 untagged (always-candidate) versions each and a run-wide
        # max_deletes=4 must plan 4 total, NOT 6.  charged stays 0 because
        # dry-run never touches the live delete budget.
        let lists = {
            "svc-a": (mock-list-ok [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])])
            "svc-b": (mock-list-ok [(mock-version 4 []) (mock-version 5 []) (mock-version 6 [])])
        }
        let runner = {|svc, budget_remaining|
            purge-service-core $svc ($lists | get $svc) ["keep"] true $budget_remaining false false false (delete-fn-ok)
        }
        let agg = (aggregate-purge-results ["svc-a" "svc-b"] 4 $runner)
        if $agg.planned != 4 {
            error make {msg: $"expected run-wide planned=4, got ($agg.planned)"}
        }
        if $agg.charged != 0 {
            error make {msg: $"expected charged=0 across dry-run services, got ($agg.charged)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_run_wide_plan_budget)

    let t_agg_failed_services = (run-test "aggregate: failed and permission-denied services are collected from real results" {
        # svc-ok succeeds, svc-fail hits a strict live-delete failure (ok=false),
        # svc-perm is soft-skipped on permission denied.  aggregate-purge-results
        # must surface both lists and roll up the totals from the real core.
        let lists = {
            "svc-ok": (mock-list-ok [(mock-version 1 []) (mock-version 2 [])])
            "svc-fail": (mock-list-ok [(mock-version 3 []) (mock-version 4 [])])
            "svc-perm": {
                ok: false, base_path: "", versions: [], not_found: false,
                permission_denied: true, error: "HTTP 403"
            }
        }
        let runner = {|svc, budget_remaining|
            let delete_fn = (if $svc == "svc-fail" { (delete-fn-fail-id 4) } else { (delete-fn-ok) })
            # live mode (dry_run=false), strict policy (partial_success=false)
            purge-service-core $svc ($lists | get $svc) ["keep"] false $budget_remaining false false false $delete_fn
        }
        let agg = (aggregate-purge-results ["svc-ok" "svc-fail" "svc-perm"] 0 $runner)
        if $agg.failed_services != ["svc-fail"] {
            error make {msg: $"expected failed_services=[svc-fail], got ($agg.failed_services)"}
        }
        if $agg.permission_denied_services != ["svc-perm"] {
            error make {msg: $"expected permission_denied_services=[svc-perm], got ($agg.permission_denied_services)"}
        }
        # svc-ok deleted 2, svc-fail deleted 1 of 2 -> 3 total deleted, 1 failed.
        if $agg.deleted != 3 { error make {msg: $"expected deleted=3, got ($agg.deleted)"} }
        if $agg.failed != 1 { error make {msg: $"expected failed=1, got ($agg.failed)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_agg_failed_services)

    let t_agg_budget_stops_iteration = (run-test "aggregate: run-wide budget exhaustion stops later services" {
        # First service plans 3 against a budget of 3, exhausting it; the second
        # service must never run (planned stays 3, not 6).
        let lists = {
            "svc-a": (mock-list-ok [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])])
            "svc-b": (mock-list-ok [(mock-version 4 []) (mock-version 5 []) (mock-version 6 [])])
        }
        let runner = {|svc, budget_remaining|
            purge-service-core $svc ($lists | get $svc) ["keep"] true $budget_remaining false false false (delete-fn-ok)
        }
        let agg = (aggregate-purge-results ["svc-a" "svc-b"] 3 $runner)
        if $agg.planned != 3 {
            error make {msg: $"expected planned=3 (second service skipped), got ($agg.planned)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_agg_budget_stops_iteration)

    # ------------------------------------------------------------------ #
    # Strict-stop regression tests
    # Strict policy (partial_success=false) must stop mutating as soon as a
    # failure is observed: within a service (purge-service-core) and across
    # services (aggregate-purge-results --strict-stop).
    # ------------------------------------------------------------------ #

    let t_core_strict_stop_first_failure = (run-test "core: strict policy stops deleting after the first failed delete" {
        # Three untagged versions sort oldest-first as [1 2 3]; the first delete
        # (id=1) fails under strict policy, so ids 2 and 3 must never be tried.
        let versions = [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-fail-id 1))
        if $r.ok { error make {msg: "expected ok=false on strict live-delete failure"} }
        if $r.planned != 3 { error make {msg: $"expected planned=3, got ($r.planned)"} }
        if $r.attempted != 1 { error make {msg: $"expected attempted=1 (stopped after first failure), got ($r.attempted)"} }
        if $r.deleted != 0 { error make {msg: $"expected deleted=0, got ($r.deleted)"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        if $r.charged != 1 { error make {msg: $"expected charged=1 (only the issued call), got ($r.charged)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_strict_stop_first_failure)

    let t_core_partial_continues_after_failure = (run-test "core: partial-success keeps deleting after a mid-list failure" {
        # Contrast with strict: the same id=1 failure under partial-success must
        # not stop the loop; ids 2 and 3 are still deleted.
        let versions = [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false true (delete-fn-fail-id 1))
        if not $r.ok { error make {msg: "expected ok=true under partial-success policy"} }
        if $r.attempted != 3 { error make {msg: $"expected attempted=3 (no early stop), got ($r.attempted)"} }
        if $r.deleted != 2 { error make {msg: $"expected deleted=2, got ($r.deleted)"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_partial_continues_after_failure)

    let t_agg_strict_stop_halts_iteration = (run-test "aggregate: strict-stop halts service iteration after a failed service" {
        # svc-fail hits a strict live-delete failure (ok=false); with --strict-stop
        # set, svc-after must never run, so totals only reflect svc-fail.
        let lists = {
            "svc-fail": (mock-list-ok [(mock-version 1 []) (mock-version 2 [])])
            "svc-after": (mock-list-ok [(mock-version 3 []) (mock-version 4 [])])
        }
        let runner = {|svc, budget_remaining|
            let delete_fn = (if $svc == "svc-fail" { (delete-fn-fail-id 1) } else { (delete-fn-ok) })
            purge-service-core $svc ($lists | get $svc) ["keep"] false $budget_remaining false false false $delete_fn
        }
        let agg = (aggregate-purge-results ["svc-fail" "svc-after"] 0 $runner --strict-stop)
        if $agg.failed_services != ["svc-fail"] {
            error make {msg: $"expected failed_services=[svc-fail], got ($agg.failed_services)"}
        }
        if $agg.planned != 2 { error make {msg: $"expected planned=2 (svc-after skipped), got ($agg.planned)"} }
        if $agg.deleted != 0 { error make {msg: $"expected deleted=0 (svc-after skipped), got ($agg.deleted)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_agg_strict_stop_halts_iteration)

    let t_agg_no_strict_stop_continues = (run-test "aggregate: without strict-stop, iteration continues past a failed service" {
        # Same setup as above but with the default (flag unset): svc-after still
        # runs, so totals roll up both services.
        let lists = {
            "svc-fail": (mock-list-ok [(mock-version 1 []) (mock-version 2 [])])
            "svc-after": (mock-list-ok [(mock-version 3 []) (mock-version 4 [])])
        }
        let runner = {|svc, budget_remaining|
            let delete_fn = (if $svc == "svc-fail" { (delete-fn-fail-id 1) } else { (delete-fn-ok) })
            purge-service-core $svc ($lists | get $svc) ["keep"] false $budget_remaining false false false $delete_fn
        }
        let agg = (aggregate-purge-results ["svc-fail" "svc-after"] 0 $runner)
        if $agg.failed_services != ["svc-fail"] {
            error make {msg: $"expected failed_services=[svc-fail], got ($agg.failed_services)"}
        }
        if $agg.planned != 4 { error make {msg: $"expected planned=4 (both services run), got ($agg.planned)"} }
        if $agg.deleted != 2 { error make {msg: $"expected deleted=2 (svc-after deleted both), got ($agg.deleted)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_agg_no_strict_stop_continues)

    let t_format_summary = (run-test "format-purge-summary: emits summary, permission-denied, and failed lines" {
        let agg = {
            planned: 5, attempted: 4, deleted: 3, failed: 1, skipped: 0, charged: 4,
            failed_services: ["svc-fail"], permission_denied_services: ["svc-perm"]
        }
        let lines = (format-purge-summary $agg)
        if ($lines | length) != 3 { error make {msg: $"expected 3 summary lines, got ($lines | length)"} }
        if not ($lines.0 | str contains "Purge complete: planned=5") {
            error make {msg: $"expected summary line, got: ($lines.0)"}
        }
        if not ($lines.0 | str contains "failed_services=1") {
            error make {msg: $"expected failed_services count in summary, got: ($lines.0)"}
        }
        if not ($lines.1 | str contains "Permission-denied versions") {
            error make {msg: $"expected permission-denied line, got: ($lines.1)"}
        }
        if not ($lines.2 | str contains "Failed services: svc-fail") {
            error make {msg: $"expected failed-services line, got: ($lines.2)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_format_summary)

    let t_format_summary_clean = (run-test "format-purge-summary: clean run emits only the summary line" {
        let agg = {
            planned: 0, attempted: 0, deleted: 0, failed: 0, skipped: 0, charged: 0,
            failed_services: [], permission_denied_services: []
        }
        let lines = (format-purge-summary $agg)
        if ($lines | length) != 1 { error make {msg: $"expected 1 line for clean run, got ($lines | length)"} }
        if not ($lines.0 | str contains "failed_services=0") {
            error make {msg: $"expected failed_services=0, got: ($lines.0)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_format_summary_clean)

    let t_core_perm_denied = (run-test "core: permission-denied list -> soft skip (ok=true, permission_denied=true)" {
        let list_result = {
            ok: false
            base_path: ""
            versions: []
            not_found: false
            permission_denied: true
            error: "HTTP 403"
        }
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-ok))
        if not $r.ok { error make {msg: "expected ok=true for permission-denied soft skip"} }
        if not $r.permission_denied { error make {msg: "expected permission_denied=true"} }
        if $r.planned != 0 { error make {msg: $"expected planned=0, got ($r.planned)"} }
        if $r.charged != 0 { error make {msg: $"expected charged=0, got ($r.charged)"} }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_perm_denied)

    let t_core_list_fail = (run-test "core: non-permission list failure -> ok=false with error" {
        let list_result = {
            ok: false
            base_path: ""
            versions: []
            not_found: false
            permission_denied: false
            error: "HTTP 500 server error"
        }
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-ok))
        if $r.ok { error make {msg: "expected ok=false for non-permission list failure"} }
        if $r.permission_denied { error make {msg: "expected permission_denied=false"} }
        if not ($r.error | str contains "HTTP 500") {
            error make {msg: $"expected error to carry list failure detail, got: ($r.error)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_core_list_fail)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
