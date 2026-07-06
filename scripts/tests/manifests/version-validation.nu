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

# Version-manifest validation cases.

use ../../lib/validate/core.nu [validate-version-manifest]
use ../lib.nu [run-test]

export def test-detect-forbidden-latest-in-tags [verbose: bool] {
  run-test "Detect forbidden 'latest' in tags" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true, tags: ["latest"]}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect forbidden 'latest' in tags"}
    }
    true
  } $verbose
}

export def test-detect-duplicate-version-names [verbose: bool] {
  run-test "Detect duplicate version names" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v1.0.0"}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect duplicate version names"}
    }
    true
  } $verbose
}

export def test-detect-tag-collision-across-versions [verbose: bool] {
  run-test "Detect tag collision across versions" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true, tags: ["stable"]},
        {name: "v2.0.0", tags: ["stable"]}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect tag collision"}
    }
    true
  } $verbose
}

export def test-detect-multiple-latest-versions [verbose: bool] {
  run-test "Detect multiple latest versions" {
    let bad_manifest = {
      default: "v1.0.0",
      versions: [
        {name: "v1.0.0", latest: true},
        {name: "v2.0.0", latest: true}
      ]
    }
    # validate-version-manifest now requires platforms parameter
    let result = (validate-version-manifest $bad_manifest null)
    if $result.valid {
      error make {msg: "Failed to detect multiple latest versions"}
    }
    # Assert the explicit multiple-latest message is emitted (not only masked by
    # the downstream 'latest' tag collision)
    let has_latest_msg = ($result.errors | any {|e| $e | str contains "Only one version can have 'latest: true'"})
    if not $has_latest_msg {
      error make {msg: $"Expected explicit multiple-latest message, got: ($result.errors | str join ', ')"}
    }
    true
  } $verbose
}
