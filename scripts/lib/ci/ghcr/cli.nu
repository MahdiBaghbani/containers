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

# Run GHCR purge for all services (or one service when service is non-empty).
# max_deletes is a GLOBAL budget for the entire run across all services (0 = unlimited).
# force: when true and desired_tags is empty, delete all candidates instead of
#   only untagged ones.  Requires --service (single service only) and
#   dry_run=false.
# Soft-failure for missing token / missing gh / package not found.
# Hard-failure (exit 1) only when a service's version list fails for non-404 reasons.
export def ghcr-purge-cli [
    service: string
    dry_run: bool
    max_deletes: int
    debug: bool
    force: bool
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
        print --stderr $"DEBUG: owner=($owner) repo=($repo) services=($services | length) dry_run=($dry_run) max_deletes=($max_deletes) force=($force)"
    }

    mut total_deleted = 0
    mut total_counted = 0
    mut failed_services = []
    mut budget_remaining = $max_deletes

    for svc in $services {
        let result = (purge-service $svc $owner $repo $dry_run $budget_remaining $debug $force)
        if $result.ok {
            $total_deleted = $total_deleted + $result.deleted
            $total_counted = $total_counted + $result.counted
            if $max_deletes > 0 {
                $budget_remaining = $budget_remaining - $result.counted
                if $budget_remaining <= 0 {
                    print --stderr "INFO: max_deletes budget exhausted; stopping service iteration"
                    break
                }
            }
        } else {
            $failed_services = ($failed_services | append $svc)
        }
    }

    print --stderr $"Purge complete: total_deleted=($total_deleted) total_counted=($total_counted) failed_services=($failed_services | length)"

    if ($failed_services | length) > 0 {
        print --stderr $"Failed services: ($failed_services | str join ', ')"
        exit 1
    }
}
