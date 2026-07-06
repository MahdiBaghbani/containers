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

# Dependency-node candidate and shard tests

use ../../lib/build/dep-nodes.nu [get-dependency-node-candidates get-matching-dependency-shards]
use ../lib.nu [run-test]

export def test-dep-nodes-common-tools-all-platforms [verbose: bool] {
  run-test "dep-nodes: common-tools no target -> all platform candidates" {
    let candidates = (get-dependency-node-candidates ["common-tools"])
    if ($candidates | is-empty) {
      error make {msg: "Expected non-empty candidates for common-tools"}
    }
    let platforms = ($candidates | each {|c| $c.platform} | uniq | sort)
    for plat in ["debian" "alpine"] {
      if not ($plat in $platforms) {
        error make {msg: $"Expected platform '($plat)' in candidates, got: ($platforms | str join ',')"}
      }
    }
    ($candidates | all {|c| $c.service == "common-tools"})
  } $verbose
}

export def test-dep-nodes-common-tools-debian [verbose: bool] {
  run-test "dep-nodes: common-tools target=debian -> only debian candidates" {
    let candidates = (get-dependency-node-candidates ["common-tools"] "debian")
    if ($candidates | is-empty) {
      error make {msg: "Expected debian candidates for common-tools"}
    }
    let non_debian = ($candidates | where {|c| $c.platform != "debian"})
    if not ($non_debian | is-empty) {
      error make {msg: $"Expected only debian, found non-debian: ($non_debian | length)"}
    }
    true
  } $verbose
}

export def test-dep-nodes-common-tools-unknown-target [verbose: bool] {
  run-test "dep-nodes: common-tools unknown target -> all platform fallback" {
    let candidates = (get-dependency-node-candidates ["common-tools"] "nonexistent-platform")
    if ($candidates | is-empty) {
      error make {msg: "Expected fallback candidates for unknown target platform"}
    }
    let platforms = ($candidates | each {|c| $c.platform} | uniq)
    if ($platforms | length) < 2 {
      error make {msg: $"Expected multiple platforms in fallback, got: ($platforms | str join ',')"}
    }
    true
  } $verbose
}

export def test-dep-nodes-shards-default-platform [verbose: bool] {
  run-test "dep-nodes: get-matching-dependency-shards uses default platform for single-platform target" {
    let candidates = (get-matching-dependency-shards ["common-tools"] "")
    if ($candidates | is-empty) {
      error make {msg: "Expected candidates from get-matching-dependency-shards"}
    }
    # Single-platform target must resolve to the default platform (debian).
    let platforms = ($candidates | each {|c| $c.platform} | uniq)
    if not ("debian" in $platforms) {
      error make {msg: $"Expected default 'debian', got: ($platforms | str join ',')"}
    }
    # Must NOT include other platforms when a single default is available.
    let non_default = ($candidates | where {|c| $c.platform != "debian"})
    if not ($non_default | is-empty) {
      error make {msg: $"Expected only default platform, got: ($non_default | length) extras"}
    }
    true
  } $verbose
}

export def test-dep-nodes-shards-explicit-platform [verbose: bool] {
  run-test "dep-nodes: get-matching-dependency-shards with explicit matching platform" {
    let candidates = (get-matching-dependency-shards ["common-tools"] "debian")
    if ($candidates | is-empty) {
      error make {msg: "Expected candidates for debian target"}
    }
    let non_debian = ($candidates | where {|c| $c.platform != "debian"})
    if not ($non_debian | is-empty) {
      error make {msg: $"Expected only debian, found: ($non_debian | length)"}
    }
    true
  } $verbose
}
