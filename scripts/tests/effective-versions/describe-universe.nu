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

# describe-version-universe tests.

use ../../lib/plane/versions.nu [describe-version-universe]
use ../../lib/plane/guard.nu [PLANE_TRACKED]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment
]

export def test-describe-universe-local-only [verbose: bool] {
  run-test "describe-version-universe lists local-only names on tracked plane" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    save-local-fragment $repo "test-svc" {
      versions: [
        { name: "local-only-v" }
      ]
    }
    mkdir (local-root-path $repo)
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if $universe.plane != $PLANE_TRACKED {
      error make {msg: $"Expected tracked plane, got ($universe.plane)"}
    }
    if not $universe.fragment_present {
      error make {msg: "Expected fragment_present true"}
    }
    if $universe.local_only_names != ["local-only-v"] {
      error make {msg: $"Expected local_only_names [local-only-v], got ($universe.local_only_names | to json)"}
    }
    if $universe.tracked_names != ["v1"] {
      error make {msg: $"Expected tracked_names [v1], got ($universe.tracked_names | to json)"}
    }
    let expected_fragment = (local-services-path $repo | path join "test-svc" | path join $LOCAL_MIRROR_FILE)
    if ($universe.fragment_path | path expand) != ($expected_fragment | path expand) {
      error make {msg: $"Expected fragment_path ($expected_fragment), got ($universe.fragment_path)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-describe-universe-no-fragment [verbose: bool] {
  run-test "describe-version-universe reports fragment_present false without mirror" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [{ name: "v1" }]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if $universe.fragment_present {
      error make {msg: "Expected fragment_present false when no local mirror exists"}
    }
    if $universe.local_only_names != [] {
      error make {msg: $"Expected empty local_only_names, got ($universe.local_only_names | to json)"}
    }
    if $universe.effective_names != ["v1"] {
      error make {msg: $"Expected effective_names [v1] on tracked plane, got ($universe.effective_names | to json)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}

export def test-describe-universe-overlap [verbose: bool] {
  run-test "describe-version-universe separates overlapping and local-only fragment names" {
    let repo = (make-temp-repo)
    seed-tracked-versions $repo {
      default: "v1"
      versions: [
        { name: "v1" }
        { name: "v2" }
      ]
    }
    mkdir (local-root-path $repo)
    save-local-fragment $repo "test-svc" {
      versions: [
        { name: "v2", overrides: {} }
        { name: "devlocal", overrides: {} }
      ]
    }
    let plane_ctx = { plane: $PLANE_TRACKED, repo_root: $repo }
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if not $universe.fragment_present {
      error make {msg: "Expected fragment_present true when mirror exists"}
    }
    if $universe.tracked_names != ["v1" "v2"] {
      error make {msg: $"Expected tracked_names [v1, v2], got ($universe.tracked_names | to json)"}
    }
    if $universe.local_only_names != ["devlocal"] {
      error make {msg: $"Expected local_only_names [devlocal], got ($universe.local_only_names | to json)"}
    }
    if $universe.effective_names != ["v1" "v2"] {
      error make {msg: $"Tracked plane effective_names must stay tracked-only, got ($universe.effective_names | to json)"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}
