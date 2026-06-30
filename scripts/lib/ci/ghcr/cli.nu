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

# CLI entrypoint for the ci ghcr-purge subcommand.
# All output (progress, warnings) goes to stderr; exit code signals success/failure.

use ./purge.nu [purge-service]
use ./api.nu [check-gh-prereqs]
use ../../services/core.nu [list-service-names]
use ../../registries/info.nu [get-registry-info]

# Pure validator for --force preconditions.
# Tests can call this directly without touching the GH API.
# Returns {ok: bool, reason: string}
export def validate-force-flags [service: string, dry_run: bool, force: bool] {
    if $force and ($service | str length) == 0 {
        return {ok: false, reason: "--force requires --service (single service only)"}
    }
    if $force and $dry_run {
        return {ok: false, reason: "--force is not allowed with --dry-run"}
    }
    {ok: true, reason: ""}
}

# Aggregate per-service purge results into run-wide totals.
# run_service: closure {|svc, budget_remaining| -> purge result contract} that
#   purges one service.  Production binds it to purge-service; tests inject an
#   API-free closure (for example one backed by purge-service-core) so the real
#   aggregation logic is exercised without duplicating it.
# max_deletes is the GLOBAL planning budget (0 = unlimited).  It is threaded
#   across services and shrunk by `planned` so --max-deletes stays a single
#   run-wide cap; iteration stops once the budget is exhausted.
# --strict-stop: when set, stop iterating services after the first failed
#   service result (ok=false) so a run that is already doomed to exit 1 does
#   not keep mutating later services.  Permission-denied soft skips (ok=true)
#   do not trigger the stop.  Default (unset) preserves best-effort iteration.
# Returns a record with the run-wide totals plus failed_services and
#   permission_denied_services.  Emits only progress info to stderr, never the
#   final summary (see format-purge-summary).
export def aggregate-purge-results [
    services: list<string>
    max_deletes: int
    run_service: closure
    --strict-stop
] {
    mut total_planned = 0
    mut total_attempted = 0
    mut total_deleted = 0
    mut total_failed = 0
    mut total_skipped = 0
    mut total_charged = 0
    mut failed_services = []
    mut permission_denied_services = []
    mut plan_budget_remaining = $max_deletes

    for svc in $services {
        let result = (do $run_service $svc $plan_budget_remaining)

        $total_planned = $total_planned + $result.planned
        $total_attempted = $total_attempted + $result.attempted
        $total_deleted = $total_deleted + $result.deleted
        $total_failed = $total_failed + $result.failed
        $total_skipped = $total_skipped + $result.skipped
        $total_charged = $total_charged + $result.charged

        if $result.permission_denied {
            $permission_denied_services = ($permission_denied_services | append $svc)
        }
        if not $result.ok {
            $failed_services = ($failed_services | append $svc)
        }

        # Under the strict policy, stop after the first failed service result so
        # we do not keep mutating later services in a run that will exit 1.
        # Permission-denied soft skips keep ok=true and do not stop iteration.
        if $strict_stop and (not $result.ok) {
            print --stderr $"ERROR: strict policy - stopping service iteration after failed service ($svc)"
            break
        }

        # Shrink the run-wide planning budget by `planned` so --max-deletes stays
        # a single run-wide cap in dry-run too (where charged is 0). We charge the
        # budget by `planned` intentionally, even in live mode: it bounds the
        # work we commit to per service before deletes run. Strict live mode can
        # stop a service early on a failed delete, leaving `charged < planned`
        # for that service, but we still decrement by `planned` so the run-wide
        # cap reflects what was planned, not just what succeeded.
        if $max_deletes > 0 {
            $plan_budget_remaining = $plan_budget_remaining - $result.planned
            if $plan_budget_remaining <= 0 {
                print --stderr "INFO: max_deletes budget exhausted; stopping service iteration"
                break
            }
        }
    }

    {
        planned: $total_planned
        attempted: $total_attempted
        deleted: $total_deleted
        failed: $total_failed
        skipped: $total_skipped
        charged: $total_charged
        failed_services: $failed_services
        permission_denied_services: $permission_denied_services
    }
}

# Format the run-wide purge summary as a list of stderr lines from an aggregate
# record (see aggregate-purge-results).  Returns strings and prints nothing, so
# the line shape can be unit-tested without capturing stderr.
export def format-purge-summary [agg: record] {
    mut lines = [
        $"Purge complete: planned=($agg.planned) attempted=($agg.attempted) deleted=($agg.deleted) failed=($agg.failed) skipped=($agg.skipped) charged=($agg.charged) failed_services=($agg.failed_services | length)"
    ]

    if ($agg.permission_denied_services | length) > 0 {
        $lines = ($lines | append $"Permission-denied versions \(soft-skipped\): ($agg.permission_denied_services | str join ', ')")
    }

    if ($agg.failed_services | length) > 0 {
        $lines = ($lines | append $"Failed services: ($agg.failed_services | str join ', ')")
    }

    $lines
}

# Run GHCR purge for all services (or one service when service is non-empty).
# max_deletes is a GLOBAL budget for the entire run across all services (0 = unlimited).
# force: when true and desired_tags is empty, delete all candidates instead of
#   only untagged ones.  Requires --service (single service only) and
#   dry_run=false.
# --partial-success: tolerate live delete failures instead of failing the run.
#   Default is strict: any live delete failure makes the run exit 1.
# Soft-failure for missing token / missing gh / package not found, and for
#   permission-denied version lists (reported clearly in the final summary).
# Hard-failure (exit 1) when a service's version list fails for non-404,
#   non-permission reasons, or when a live delete fails under the strict policy.
export def ghcr-purge-cli [
    service: string
    dry_run: bool
    max_deletes: int
    debug: bool
    force: bool
    --partial-success
] {
    # Enforce force preconditions before touching the API
    let gate = (validate-force-flags $service $dry_run $force)
    if not $gate.ok {
        print --stderr $"ERROR: ($gate.reason)"
        exit 1
    }

    # Resolve owner/repo from GITHUB_REPOSITORY; fall back to git origin for
    # local dev when GITHUB_REPOSITORY is not set.
    let gh_repo = (try { $env.GITHUB_REPOSITORY } catch { "" })

    mut owner = ""
    mut repo = ""

    if ($gh_repo | str length) > 0 {
        let parts = ($gh_repo | split row "/")
        if ($parts | length) != 2 {
            print --stderr $"WARNING: GITHUB_REPOSITORY has unexpected format: ($gh_repo) - skipping"
            return
        }
        $owner = ($parts | get 0)
        $repo = ($parts | get 1)
    } else {
        let info = (get-registry-info)
        if ($info.owner == "local" or $info.repo == "local") {
            print --stderr "WARNING: GITHUB_REPOSITORY not set and git origin unavailable - skipping GHCR purge"
            return
        }
        print --stderr $"INFO: GITHUB_REPOSITORY not set; using git origin owner/repo=($info.owner)/($info.repo)"
        $owner = $info.owner
        $repo = $info.repo
    }

    # Check prereqs (GITHUB_TOKEN + gh CLI)
    let prereq = (check-gh-prereqs)
    if not $prereq.ok {
        print --stderr $"WARNING: ($prereq.reason) - skipping GHCR purge"
        return
    }

    let services = (if ($service | str length) > 0 {
        [$service]
    } else {
        list-service-names
    })

    if $dry_run {
        print --stderr "DRY-RUN mode: no versions will be deleted"
    }

    if $debug {
        print --stderr $"DEBUG: owner=($owner) repo=($repo) services=($services | length) dry_run=($dry_run) max_deletes=($max_deletes) force=($force) partial_success=($partial_success)"
    }

    # Closures cannot capture mutable bindings, so snapshot owner/repo first.
    let owner_final = $owner
    let repo_final = $repo
    let run_service = {|svc, budget_remaining|
        purge-service $svc $owner_final $repo_final $dry_run $budget_remaining $debug $force --partial-success=$partial_success
    }

    let agg = (aggregate-purge-results $services $max_deletes $run_service --strict-stop=(not $partial_success))

    for line in (format-purge-summary $agg) {
        print --stderr $line
    }

    if ($agg.failed_services | length) > 0 {
        exit 1
    }
}
