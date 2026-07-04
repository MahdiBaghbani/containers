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

# purge-service-core behavior tests

use ../../lib/ci/ghcr/purge.nu [purge-service-core]
use ../lib.nu [run-test]
use ./_mocks.nu [mock-version mock-list-ok delete-fn-ok delete-fn-fail-id]

export def test-core-live-delete-success [verbose: bool] {
    run-test "core: live delete success -> ok, all deleted, charged=attempted" {
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
    } $verbose
}

export def test-core-live-delete-fail-strict [verbose: bool] {
    run-test "core: live delete failure (strict) -> ok=false, failure recorded" {
        let versions = [(mock-version 1 []) (mock-version 2 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false false (delete-fn-fail-id 2))
        if $r.ok { error make {msg: "expected ok=false when a live delete fails under strict policy"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        if $r.deleted != 1 { error make {msg: $"expected deleted=1, got ($r.deleted)"} }
        if ($r.error | str length) == 0 { error make {msg: "expected non-empty error message"} }
        true
    } $verbose
}

export def test-core-live-delete-fail-partial [verbose: bool] {
    run-test "core: live delete failure (partial-success) -> ok=true, failure still counted" {
        let versions = [(mock-version 1 []) (mock-version 2 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false true (delete-fn-fail-id 2))
        if not $r.ok { error make {msg: "expected ok=true under partial-success policy"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        if $r.deleted != 1 { error make {msg: $"expected deleted=1, got ($r.deleted)"} }
        true
    } $verbose
}

export def test-core-dry-run [verbose: bool] {
    run-test "core: dry-run charges zero against budget while reporting planned" {
        let versions = [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] true 0 false false false (delete-fn-fail-id 1))
        if not $r.ok { error make {msg: "expected ok=true in dry-run"} }
        if $r.planned != 3 { error make {msg: $"expected planned=3, got ($r.planned)"} }
        if $r.charged != 0 { error make {msg: $"expected charged=0 in dry-run, got ($r.charged)"} }
        if $r.attempted != 0 { error make {msg: $"expected attempted=0 in dry-run, got ($r.attempted)"} }
        if $r.deleted != 0 { error make {msg: $"expected deleted=0 in dry-run, got ($r.deleted)"} }
        if $r.skipped != 3 { error make {msg: $"expected skipped=3 in dry-run, got ($r.skipped)"} }
        true
    } $verbose
}

export def test-core-strict-stop-first-failure [verbose: bool] {
    run-test "core: strict policy stops deleting after the first failed delete" {
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
    } $verbose
}

export def test-core-partial-continues-after-failure [verbose: bool] {
    run-test "core: partial-success keeps deleting after a mid-list failure" {
        let versions = [(mock-version 1 []) (mock-version 2 []) (mock-version 3 [])]
        let list_result = (mock-list-ok $versions)
        let r = (purge-service-core "svc" $list_result ["keep"] false 0 false false true (delete-fn-fail-id 1))
        if not $r.ok { error make {msg: "expected ok=true under partial-success policy"} }
        if $r.attempted != 3 { error make {msg: $"expected attempted=3 (no early stop), got ($r.attempted)"} }
        if $r.deleted != 2 { error make {msg: $"expected deleted=2, got ($r.deleted)"} }
        if $r.failed != 1 { error make {msg: $"expected failed=1, got ($r.failed)"} }
        true
    } $verbose
}

export def test-core-permission-denied [verbose: bool] {
    run-test "core: permission-denied list -> soft skip (ok=true, permission_denied=true)" {
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
    } $verbose
}

export def test-core-list-fail [verbose: bool] {
    run-test "core: non-permission list failure -> ok=false with error" {
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
    } $verbose
}
