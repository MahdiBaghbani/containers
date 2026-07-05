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

# Ordering and broken-manifest contract tests.

use ../../lib/plane/guard.nu [guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  make-temp-repo rm-temp-repo seed-tracked-service expect-guard-pass
  assert-audit-result-shape
]

export def test-manifest-missing-name [verbose: bool] {
  run-test "tracked service manifest missing name hard-errors when mirror exists" {
    let repo = (make-temp-repo)
    { platforms: [] } | save -f ($repo | path join "services/nameless-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "nameless-svc")
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail when tracked manifest omits name"}
    }
    if not ($result.msg | str contains "Tracked service manifest missing 'name'") {
      error make {msg: $"Expected missing-name manifest error, got: ($result.msg)"}
    }
    true
  } $verbose
}

export def test-broken-manifest-before-mirror-audit [verbose: bool] {
  run-test "broken tracked service manifest hard-errors before mirror audit" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    mkdir (local-services-path $repo | path join "test-svc")
    let result = (try {
      guard-local-plane-presence $repo
      { ok: true }
    } catch {|err|
      { ok: false, msg: $err.msg }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected guard to fail on broken tracked service manifest"}
    }
    if not ($result.msg | str contains "Unable to read tracked service manifest") {
      error make {msg: $"Expected manifest read error, got: ($result.msg)"}
    }
    if ($result.msg | str contains "Unknown local service mirror") {
      error make {msg: $"Manifest failure must not surface as unknown mirror: ($result.msg)"}
    }
    true
  } $verbose
}

export def test-empty-root-ignores-broken-manifest [verbose: bool] {
  run-test "empty legal local root passes despite broken tracked manifest" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-empty-services-ignores-broken-manifest [verbose: bool] {
  run-test "empty local services/ passes despite broken tracked manifest" {
    let repo = (make-temp-repo)
    "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
    mkdir (local-root-path $repo)
    mkdir (local-services-path $repo)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-mirror-passes-unrelated-broken-manifest [verbose: bool] {
  run-test "local mirror passes when unrelated tracked manifest is broken" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "svc-a"
    "not valid nuon {" | save -f ($repo | path join "services/svc-b.nuon")
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "svc-a")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    let ok = (expect-guard-pass $repo)
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-audit-ignores-broken-unrelated-manifest [verbose: bool] {
  run-test "audit-local-root-topology ignores broken unrelated manifest" {
    let repo = (make-temp-repo)
    seed-tracked-service $repo "svc-a"
    "not valid nuon {" | save -f ($repo | path join "services/svc-b.nuon")
    mkdir (local-root-path $repo)
    let mirror = (local-services-path $repo | path join "svc-a")
    mkdir $mirror
    { versions: {} } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
    assert-audit-result-shape $repo ["svc-a"]
    rm-temp-repo $repo
    true
  } $verbose
}
