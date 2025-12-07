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

# Tests for CI cache shard helpers (scripts/lib/ci/cache-shards.nu)

use ./lib.nu [run-test print-test-summary]
use ../lib/ci/cache-shards.nu [make-node-key merge-node-shards]

def main [--verbose] {
  mut results = []

  # Test: make-node-key handles single-platform nodes
  let t1 = (run-test "make-node-key single-platform" {
    let key = (make-node-key "svc" "v1" "")
    $key == "svc:v1"
  } $verbose)
  $results = ($results | append $t1)

  # Test: make-node-key handles multi-platform nodes
  let t2 = (run-test "make-node-key multi-platform" {
    let key = (make-node-key "svc" "v1" "linux-amd64")
    $key == "svc:v1:linux-amd64"
  } $verbose)
  $results = ($results | append $t2)

  # Test: merge-node-shards combines manifests and deduplicates images
  let t3 = (run-test "merge-node-shards merges manifests and deduplicates images" {
    # Create temporary shard directory
    let tmp_dir = (mktemp -d)

    # Two shards, two nodes pointing to same image_id with different refs
    let shard1 = {
      node_key: "svc:v1",
      image_id: "sha256:abc123",
      refs: ["ref1"]
    }
    let shard2 = {
      node_key: "svc:v2",
      image_id: "sha256:abc123",
      refs: ["ref2"]
    }

    $shard1 | to nuon | save -f $"($tmp_dir)/s1.nuon"
    $shard2 | to nuon | save -f $"($tmp_dir)/s2.nuon"

    # Create fake tarballs matching image_id-derived filenames
    touch $"($tmp_dir)/abc123.tar.zst"

    let result = (merge-node-shards "svc" $tmp_dir)

    let nodes = $result.nodes
    let images = $result.images

    let node_ok = ($nodes | get "svc:v1") == "sha256:abc123" and ($nodes | get "svc:v2") == "sha256:abc123"
    let img = ($images | get "sha256:abc123")
    let refs = ($img.refs | sort)
    let refs_ok = ($refs == ["ref1" "ref2"])
    let owner_ok = $img.owner_service == "svc"

    $node_ok and $refs_ok and $owner_ok
  } $verbose)
  $results = ($results | append $t3)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}
