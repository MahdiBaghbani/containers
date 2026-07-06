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

# aggregate-purge-results tests

use ../../lib/ci/ghcr/purge.nu [purge-service-core]
use ../../lib/ci/ghcr/cli.nu [aggregate-purge-results]
use ../lib.nu [run-test]
use ./_mocks.nu [mock-version mock-list-ok delete-fn-ok delete-fn-fail-id]

export def test-aggregate-dry-run-run-wide-budget [verbose: bool] {
    run-test "aggregate: dry-run planning budget is run-wide, not per-service" {
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
    } $verbose
}

export def test-aggregate-failed-services [verbose: bool] {
    run-test "aggregate: failed and permission-denied services are collected from real results" {
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
            purge-service-core $svc ($lists | get $svc) ["keep"] false $budget_remaining false false false $delete_fn
        }
        let agg = (aggregate-purge-results ["svc-ok" "svc-fail" "svc-perm"] 0 $runner)
        if $agg.failed_services != ["svc-fail"] {
            error make {msg: $"expected failed_services=[svc-fail], got ($agg.failed_services)"}
        }
        if $agg.permission_denied_services != ["svc-perm"] {
            error make {msg: $"expected permission_denied_services=[svc-perm], got ($agg.permission_denied_services)"}
        }
        if $agg.deleted != 3 { error make {msg: $"expected deleted=3, got ($agg.deleted)"} }
        if $agg.failed != 1 { error make {msg: $"expected failed=1, got ($agg.failed)"} }
        true
    } $verbose
}

export def test-aggregate-budget-stops-iteration [verbose: bool] {
    run-test "aggregate: run-wide budget exhaustion stops later services" {
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
    } $verbose
}

export def test-aggregate-strict-stop-halts [verbose: bool] {
    run-test "aggregate: strict-stop halts service iteration after a failed service" {
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
    } $verbose
}

export def test-aggregate-no-strict-stop-continues [verbose: bool] {
    run-test "aggregate: without strict-stop, iteration continues past a failed service" {
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
    } $verbose
}
