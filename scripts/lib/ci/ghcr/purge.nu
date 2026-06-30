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

# Core purge logic: decide which GHCR package versions to delete and execute.
# Delete unit is the package version ID (not the tag).
# A version is KEPT if ANY of its tags intersects the SSOT desired tag set.
# Untagged versions (tags=[]) are always candidates for deletion (Layer 1).
#
# Empty-SSOT policy (default):
#   When desired_tags is empty and force=false, only untagged versions are
#   deleted.  Tagged versions are always kept.  This prevents accidental
#   mass-deletion when the SSOT manifest is missing or incomplete.
#
# Force wipe (empty SSOT + force=true):
#   All candidates (untagged + stale-tagged) are eligible.  The caller
#   (ghcr-purge-cli) enforces that force is only used with a single service
#   and dry_run=false.

use ./ssot-tags.nu [compute-desired-tags-for-service]
use ./api.nu [list-package-versions delete-package-version]

# Decide which versions are candidates for deletion.
# all_versions: raw list from GHCR API (each item has .id, .metadata.container.tags,
#   and optionally .updated_at / .created_at)
# desired_tags: list<string> of tag names that should exist
# Returns list of {id: int, tags: list<string>, ts: string, reason: string}
# ts is populated from updated_at (fallback created_at, "" if absent).
# List is in API order; call sort-delete-candidates to get oldest-first ordering.
export def decide-versions-to-delete [
    all_versions: list
    desired_tags: list<string>
] {
    $all_versions | each {|v|
        let vid = (try { $v.id } catch { null })
        let vtags = (try { $v.metadata.container.tags } catch { [] })
        let ts_updated = ($v.updated_at? | default "")
        let ts_created = ($v.created_at? | default "")
        let ts = (if ($ts_updated | str length) > 0 { $ts_updated } else { $ts_created })

        if $vid == null { return null }

        if ($vtags | is-empty) {
            # Layer 1: untagged versions are always stale
            {id: $vid, tags: [], ts: $ts, reason: "untagged"}
        } else {
            let keep = ($vtags | any {|t| $t in $desired_tags})
            if not $keep {
                {id: $vid, tags: $vtags, ts: $ts, reason: "no desired tags"}
            } else {
                null
            }
        }
    } | compact
}

# Sort delete candidates: oldest first (ts asc), id asc as tiebreaker.
# Versions with empty ts sort before dated ones (unknown age treated as oldest).
export def sort-delete-candidates []: list -> list {
    $in | sort-by ts id
}

# Pure decision helper: apply deletion policy and return a sorted, budget-capped
# candidate list.  This is the testable, API-free core of purge-service.
#
# Policy matrix:
#   desired_tags non-empty, any force -> keep versions that intersect desired
#     set; delete untagged + stale-tagged (standard behavior).
#   desired_tags empty, force=false -> delete ONLY untagged versions;
#     all tagged versions are kept regardless.
#   desired_tags empty, force=true -> delete all candidates (untagged +
#     stale-tagged); caller must have already verified force preconditions.
#
# budget_remaining: 0 = unlimited; >0 = cap (oldest versions are preferred).
export def plan-deletions [
    all_versions: list
    desired_tags: list<string>
    budget_remaining: int
    force: bool
] {
    let raw = (decide-versions-to-delete $all_versions $desired_tags)
    let candidates = if ($desired_tags | is-empty) and not $force {
        # empty SSOT + no force -> keep tagged, only remove untagged
        $raw | where reason == "untagged"
    } else {
        $raw
    }
    let sorted = ($candidates | sort-delete-candidates)
    if $budget_remaining > 0 and ($sorted | length) > $budget_remaining {
        $sorted | first $budget_remaining
    } else {
        $sorted
    }
}

# Purge result contract.
# Every purge-service / purge-service-core call returns a record with these
# fields so the CLI can aggregate run-wide totals and decide exit status:
#   ok                 service result; false means the run must fail (exit 1)
#   planned            candidates selected for deletion (after policy + budget)
#   attempted          delete calls actually issued (0 in dry-run)
#   deleted            successful deletions
#   failed             failed delete calls
#   skipped            candidates reported but not deleted (dry-run planned set)
#   charged            versions charged against the global live-delete budget
#                      (0 in dry-run; equals attempted in live mode)
#   permission_denied  true when the version list was soft-skipped on 401/403
#   error              human-readable reason when ok=false (else "")
export def empty-purge-result [] {
    {
        ok: true
        planned: 0
        attempted: 0
        deleted: 0
        failed: 0
        skipped: 0
        charged: 0
        permission_denied: false
        error: ""
    }
}

# Injectable, API-free purge core.  This holds all of the per-service decision
# and execution logic so it can be unit-tested without touching the GH API.
#
# list_result: the record returned by list-package-versions (or a mock with the
#   same shape: {ok, base_path, versions, not_found, permission_denied, error}).
# delete_fn: closure {|base_path, version_id| -> {ok: bool, error: string}} used
#   to perform a single live deletion.  Tests inject a pure closure here.
#
# Failure policy:
#   - non-permission list failures fail the service result (ok=false).
#   - permission-denied list failures are a soft skip (ok=true,
#     permission_denied=true); the CLI summary must report them clearly.
#   - live delete failures fail the service result (ok=false) UNLESS
#     partial_success=true, in which case failures are tolerated (ok=true) and
#     still counted in `failed`.
#   - under the strict policy (partial_success=false) deletion stops at the
#     first failed delete so a doomed service does not keep mutating GHCR;
#     `attempted` then reflects the calls actually issued (< planned).
#   - dry-run charges zero against the live-delete budget while reporting the
#     planned candidate count.
export def purge-service-core [
    service: string
    list_result: record
    desired_tags: list<string>
    dry_run: bool
    budget_remaining: int
    debug: bool
    force: bool
    partial_success: bool
    delete_fn: closure
] {
    if not $list_result.ok {
        if $list_result.permission_denied {
            print --stderr $"WARNING: ($service): permission denied listing versions - skipping"
            return (empty-purge-result | merge {permission_denied: true})
        }
        print --stderr $"ERROR: ($service): failed to list versions: ($list_result.error)"
        return (empty-purge-result | merge {ok: false, error: $list_result.error})
    }

    if $list_result.not_found {
        print --stderr $"INFO: ($service): package not found in GHCR - skipping"
        return (empty-purge-result)
    }

    let all_versions = $list_result.versions
    let base_path = $list_result.base_path

    if $debug {
        print --stderr $"DEBUG: ($service): found ($all_versions | length) total versions"
    }

    # Plan deletions using policy-aware helper (sorts oldest-first, applies
    # budget cap, enforces empty-SSOT policy or force).
    let to_delete = (plan-deletions $all_versions $desired_tags $budget_remaining $force)
    let planned = ($to_delete | length)

    if ($to_delete | is-empty) {
        print --stderr $"INFO: ($service): no versions selected for deletion"
        return (empty-purge-result)
    }

    let n_untagged = ($to_delete | where reason == "untagged" | length)
    let n_stale = ($to_delete | where reason == "no desired tags" | length)
    print --stderr $"($service): ($planned) versions to delete - untagged=($n_untagged) stale=($n_stale)"

    if $dry_run {
        for v in $to_delete {
            let tag_str = (if ($v.tags | is-empty) { "<untagged>" } else { $v.tags | str join ", " })
            print --stderr $"DRY-RUN: ($service): would delete id=($v.id) ts=($v.ts) tags=[($tag_str)] reason=($v.reason)"
        }
        # Dry-run reports planned candidates but charges zero against the budget.
        return (empty-purge-result | merge {planned: $planned, skipped: $planned, charged: 0})
    }

    # Live execution.  Under the strict policy (partial_success=false) we stop
    # at the first failed delete so a service that is already going to fail the
    # run does not keep issuing further deletions.  `attempted` counts the
    # calls actually issued, which may be fewer than `planned` after a stop.
    mut deleted = 0
    mut failed = 0
    mut attempted = 0

    for v in $to_delete {
        let tag_str = (if ($v.tags | is-empty) { "<untagged>" } else { $v.tags | str join ", " })
        let del_result = (do $delete_fn $base_path $v.id)
        $attempted = $attempted + 1

        if $del_result.ok {
            $deleted = $deleted + 1
            if $debug {
                print --stderr $"DEBUG: ($service): deleted id=($v.id) tags=[($tag_str)]"
            }
        } else {
            $failed = $failed + 1
            print --stderr $"WARNING: ($service): failed to delete id=($v.id) tags=[($tag_str)]: ($del_result.error)"
            if not $partial_success {
                print --stderr $"ERROR: ($service): strict policy - stopping after first delete failure"
                break
            }
        }
    }

    let charged = $attempted
    let has_failures = ($failed > 0)
    let ok = (not ($has_failures and (not $partial_success)))
    let error = (if $has_failures and (not $partial_success) {
        $"($failed) of ($attempted) deletion\(s\) failed"
    } else {
        ""
    })

    if $has_failures and $partial_success {
        print --stderr $"WARNING: ($service): ($failed) of ($attempted) deletion\(s\) failed - partial-success policy active, continuing"
    }

    print --stderr $"($service): deleted=($deleted) failed=($failed)"

    (empty-purge-result | merge {
        ok: $ok
        planned: $planned
        attempted: $attempted
        deleted: $deleted
        failed: $failed
        skipped: 0
        charged: $charged
        error: $error
    })
}

# Purge one service's GHCR package versions.
# budget_remaining: remaining global delete budget (0 = unlimited).
# force: when true and desired_tags is empty, delete all candidates (not just
#   untagged).  The caller must have already enforced force preconditions
#   (single service, dry_run=false).
# --partial-success: tolerate live delete failures (ok stays true).  Default is
#   strict: any live delete failure fails the service result.
# Returns the purge result contract (see empty-purge-result).
export def purge-service [
    service: string
    owner: string
    repo: string
    dry_run: bool
    budget_remaining: int
    debug: bool
    force: bool
    --partial-success
] {
    # Step 1: Compute desired tags from SSOT
    let desired_tags = (compute-desired-tags-for-service $service)

    if ($desired_tags | is-empty) {
        if $force {
            print --stderr $"WARNING: ($service): desired_tags is empty \(SSOT missing or incomplete\) - force active; all candidates eligible"
        } else {
            print --stderr $"INFO: ($service): desired_tags is empty \(SSOT missing or incomplete\) - only untagged versions will be removed"
        }
    }

    if $debug {
        print --stderr $"DEBUG: ($service): desired tags = ($desired_tags | str join ', ') force=($force)"
    }

    # Step 2: List versions from GHCR API
    let list_result = (list-package-versions $owner $repo $service $debug)

    # Step 3-4: Delegate planning + execution to the injectable core, passing a
    # real delete closure bound to the live API.
    let delete_fn = {|base_path, version_id| delete-package-version $base_path $version_id $debug }
    (purge-service-core
        $service
        $list_result
        $desired_tags
        $dry_run
        $budget_remaining
        $debug
        $force
        $partial_success
        $delete_fn)
}
