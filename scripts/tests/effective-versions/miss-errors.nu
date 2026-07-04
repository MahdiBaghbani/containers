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

# format-version-miss-error tests.

use ../../lib/plane/versions.nu [format-version-miss-error]
use ../../lib/plane/guard.nu [PLANE_TRACKED]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment
]

export def test-format-miss-local-only [verbose: bool] {
  run-test "format-version-miss-error guides --plane local for tracked-plane local-only miss" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    save-local-fragment $repo "test-svc" {
      versions: [{ name: "devlocal" }]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "devlocal" $plane_ctx --style build
    })
    if not ($msg | str contains "--plane local") {
      error make {msg: $"Expected --plane local guidance, got: ($msg)"}
    }
    let expected_fragment = (local-services-path $repo | path join "test-svc" | path join $LOCAL_MIRROR_FILE | path expand)
    if not ($msg | str contains ($expected_fragment | into string)) {
      error make {msg: $"Expected fragment path ($expected_fragment) in message, got: ($msg)"}
    }
    if not ($msg | str contains "local fragment") {
      error make {msg: $"Expected local fragment mention, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-format-miss-generic [verbose: bool] {
  run-test "format-version-miss-error keeps generic tracked miss without local-only guidance" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "nope" $plane_ctx --style short
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Generic miss must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-format-miss-fragment-generic [verbose: bool] {
  run-test "format-version-miss-error does not suggest --plane local for generic miss with fragment present" {
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
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "typo" $plane_ctx --style build
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Generic miss with fragment present must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-format-miss-inspect-generic [verbose: bool] {
  run-test "format-version-miss-error inspect style uses tracked-version options for generic miss" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let msg = (run-in-temp-repo $repo {||
      format-version-miss-error "test-svc" "nope" $plane_ctx --style inspect
    })
    if ($msg | str contains "--plane local") {
      error make {msg: $"Inspect generic miss must not mention --plane local, got: ($msg)"}
    }
    if not ($msg | str contains "Use one of the available tracked versions") {
      error make {msg: $"Expected inspect tracked-version option, got: ($msg)"}
    }
    if not ($msg | str contains "Available versions: v1") {
      error make {msg: $"Expected available versions list, got: ($msg)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}
