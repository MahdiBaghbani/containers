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

# resolve-inspect-version-spec miss routing tests.

use ../../lib/inspect/effective-config.nu [resolve-inspect-version-spec]
use ../../lib/plane/guard.nu [PLANE_TRACKED]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment expect-error
]

export def test-resolve-inspect-generic-miss [verbose: bool] {
  run-test "resolve-inspect-version-spec routes generic miss through inspect formatter" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let ok = (run-in-temp-repo $repo {||
      expect-error {||
        resolve-inspect-version-spec "test-svc" "nope" $plane_ctx
      } "Use one of the available tracked versions"
    })
    rm-temp-repo $repo
    $ok
  } $verbose
}

export def test-resolve-inspect-fragment-generic-miss [verbose: bool] {
  run-test "resolve-inspect-version-spec generic miss with fragment does not suggest --plane local" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let result = (run-in-temp-repo $repo {||
      try {
        resolve-inspect-version-spec "test-svc" "typo" $plane_ctx
        { ok: true }
      } catch {|err|
        { ok: false, msg: $err.msg }
      }
    })
    rm-temp-repo $repo
    if $result.ok {
      error make {msg: "Expected resolve-inspect-version-spec to fail for generic miss"}
    }
    if ($result.msg | str contains "--plane local") {
      error make {msg: $"Generic inspect miss with fragment must not mention --plane local, got: ($result.msg)"}
    }
    if not ($result.msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions in inspect miss, got: ($result.msg)"}
    }
    true
  } $verbose
}
