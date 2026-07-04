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

# Tracked/local passthrough tests.

use ../../lib/plane/versions.nu [load-effective-versions-manifest]
use ../../lib/plane/guard.nu [PLANE_TRACKED guard-local-plane-presence]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo seed-tracked-versions
]

export def test-tracked-passthrough-null [verbose: bool] {
  run-test "tracked passthrough with null plane_ctx" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" null
    })
    if $out.default != "v1" {
      error make {msg: $"Expected default v1, got ($out.default)"}
    }
    if ($out.versions | length) != 1 {
      error make {msg: "Expected one tracked version"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-tracked-passthrough-plane [verbose: bool] {
  run-test "tracked passthrough with tracked plane_ctx" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if $out.default != "v1" {
      error make {msg: $"Expected default v1, got ($out.default)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-local-no-fragment [verbose: bool] {
  run-test "local plane passthrough with no fragment" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = (guard-local-plane-presence $repo)
    let out = (run-in-temp-repo $repo {||
      load-effective-versions-manifest "test-svc" $plane_ctx
    })
    if $out.default != "v1" {
      error make {msg: $"Expected tracked default, got ($out.default)"}
    }
    if ($out.versions | length) != 1 {
      error make {msg: "Expected tracked versions unchanged"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}
