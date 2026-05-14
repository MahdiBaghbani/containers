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

# Purge one service's GHCR package versions.
# budget_remaining: remaining global delete budget (0 = unlimited).
# force: when true and desired_tags is empty, delete all candidates (not just
#   untagged).  The caller must have already enforced force preconditions
#   (single service, dry_run=false).
# Returns {ok: bool, deleted: int, skipped: int, counted: int, error: string}
# counted: versions charged against the global budget
#   (capped selection size in dry-run; attempted deletions in live mode)
export def purge-service [
    service: string
    owner: string
    repo: string
    dry_run: bool
    budget_remaining: int
    debug: bool
    force: bool
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

    if not $list_result.ok {
        if $list_result.permission_denied {
            print --stderr $"WARNING: ($service): permission denied listing versions - skipping"
            return {ok: true, deleted: 0, skipped: 0, counted: 0, error: ""}
        }
        print --stderr $"ERROR: ($service): failed to list versions: ($list_result.error)"
        return {ok: false, deleted: 0, skipped: 0, counted: 0, error: $list_result.error}
    }

    if $list_result.not_found {
        print --stderr $"INFO: ($service): package not found in GHCR - skipping"
        return {ok: true, deleted: 0, skipped: 0, counted: 0, error: ""}
    }

    let all_versions = $list_result.versions
    let base_path = $list_result.base_path

    if $debug {
        print --stderr $"DEBUG: ($service): found ($all_versions | length) total versions"
    }

    # Step 3: Plan deletions using policy-aware helper (sorts oldest-first,
    #         applies budget cap, enforces empty-SSOT policy or force)
    let to_delete = (plan-deletions $all_versions $desired_tags $budget_remaining $force)

    if ($to_delete | is-empty) {
        print --stderr $"INFO: ($service): no versions selected for deletion"
        return {ok: true, deleted: 0, skipped: 0, counted: 0, error: ""}
    }

    let counted = ($to_delete | length)
    let n_untagged = ($to_delete | where reason == "untagged" | length)
    let n_stale = ($to_delete | where reason == "no desired tags" | length)
    print --stderr $"($service): ($counted) versions to delete - untagged=($n_untagged) stale=($n_stale)"

    if $dry_run {
        for v in $to_delete {
            let tag_str = (if ($v.tags | is-empty) { "<untagged>" } else { $v.tags | str join ", " })
            print --stderr $"DRY-RUN: ($service): would delete id=($v.id) ts=($v.ts) tags=[($tag_str)] reason=($v.reason)"
        }
        return {ok: true, deleted: 0, skipped: $counted, counted: $counted, error: ""}
    }

    # Step 4: Execute deletions
    mut deleted = 0
    mut failed = 0

    for v in $to_delete {
        let tag_str = (if ($v.tags | is-empty) { "<untagged>" } else { $v.tags | str join ", " })
        let del_result = (delete-package-version $base_path $v.id $debug)

        if $del_result.ok {
            $deleted = $deleted + 1
            if $debug {
                print --stderr $"DEBUG: ($service): deleted id=($v.id) tags=[($tag_str)]"
            }
        } else {
            $failed = $failed + 1
            print --stderr $"WARNING: ($service): failed to delete id=($v.id) tags=[($tag_str)]: ($del_result.error)"
        }
    }

    print --stderr $"($service): deleted=($deleted) failed=($failed)"

    {ok: true, deleted: $deleted, skipped: 0, counted: $counted, error: ""}
}
