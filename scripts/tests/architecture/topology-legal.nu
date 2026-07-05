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

# Valid tracked mirror and empty subtree pass-path checks.

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-temp-repo rm-temp-repo seed-tracked-service expect-guard-pass
  assert-audit-result-shape assert-guard-result-shape
]

export def test-legal-tracked-mirror [verbose: bool] {
  run-test "legal tracked mirror with versions.nuon passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-audit-reports-legal-mirrors [verbose: bool] {
  run-test "audit-local-root-topology reports legal mirrors" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-audit-result-shape $repo ["test-svc"]
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-guard-merged-audit-shape [verbose: bool] {
  run-test "guard-local-plane-presence returns merged audit shape" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "test-svc")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-guard-result-shape $repo ["test-svc"]
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-absent-local-mirrors [verbose: bool] {
  run-test "tracked service with absent local mirrors passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    assert-guard-result-shape $repo []
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-empty-local-services [verbose: bool] {
  run-test "tracked service with empty local services/ passes" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "test-svc"
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    assert-guard-result-shape $repo []
    rm-temp-repo $repo
    true
  } $verbose
}
