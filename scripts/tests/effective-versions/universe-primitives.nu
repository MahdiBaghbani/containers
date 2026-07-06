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

# Version universe primitive tests.

use ../../lib/plane/versions.nu [
  merge-version-universe
  resolve-tracked-source-id-universe
  describe-version-universe
  version-local-only-in-fragment
]
use ../../lib/plane/guard.nu [PLANE_TRACKED]
use ../../lib/plane/presence.nu [local-root-path]
use ../lib.nu [run-test]
use ./fixtures.nu [
  make-temp-repo rm-temp-repo run-in-temp-repo
  seed-tracked-versions save-local-fragment
]

export def test-merge-unit [verbose: bool] {
  run-test "merge-version-universe unit: replace and append order" {
    let tracked = [
      { name: "a" }
      { name: "b" }
    ]
    let fragment = [
      { name: "b", tag: "replaced" }
      { name: "c", tag: "new1" }
      { name: "d", tag: "new2" }
    ]
    let merged = (merge-version-universe $tracked $fragment)
    let names = ($merged | each {|v| $v.name })
    if $names != ["a" "b" "c" "d"] {
      error make {msg: $"Unexpected merge order: ($names | to json)"}
    }
    let b = ($merged | where {|v| $v.name == "b" } | first)
    if (try { $b.tag } catch { "" }) != "replaced" {
      error make {msg: "Same-named version must be fully replaced"}
    }
    true
  } $verbose
}

export def test-source-id-universe [verbose: bool] {
  run-test "resolve-tracked-source-id-universe unions defaults and version overrides" {
    let tracked = {
      defaults: { sources: { base_src: { url: "u", ref: "r" } } }
      versions: [
        { name: "v1", overrides: { sources: { ver_src: { ref: "x" } } } }
      ]
    }
    let ids = (resolve-tracked-source-id-universe $tracked)
    if $ids != ["base_src" "ver_src"] {
      error make {msg: $"Expected [base_src, ver_src], got ($ids | to json)"}
    }
    true
  } $verbose
}

export def test-local-only-detector [verbose: bool] {
  run-test "version-local-only-in-fragment detects tracked-plane local-only miss" {
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
    let universe = (run-in-temp-repo $repo {||
      describe-version-universe "test-svc" $plane_ctx
    })
    if not (version-local-only-in-fragment $universe "devlocal") {
      error make {msg: "Expected devlocal to be local-only in fragment"}
    }
    if (version-local-only-in-fragment $universe "v1") {
      error make {msg: "Tracked version v1 must not be classified local-only"}
    }
    if (version-local-only-in-fragment $universe "missing") {
      error make {msg: "Unknown version must not be classified local-only"}
    }
    rm-temp-repo $repo
    true
  } $verbose
}
