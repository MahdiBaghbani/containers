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

# merge-node-shards manifest merge rules, image dedup, refs, and owner_service.

use ../../lib/ci/cache-shards.nu [merge-node-shards]
use ../lib.nu [run-test]
use ./_fixtures.nu [cleanup-merge-fixture make-merge-fixture]

export def merge-shards-tests [verbose: bool] {
    [
        (run-test "merge-node-shards merges manifests and deduplicates images" {
            let fx = (make-merge-fixture)
            let tmp_dir = $fx.tmp_dir
            let owner_name = $fx.owner_name
            let owner_cache = $fx.owner_cache

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

            # Fake tarball matching image_id-derived filename
            touch $"($tmp_dir)/abc123.tar.zst"

            let result = (try {
                merge-node-shards $owner_name $tmp_dir
            } catch {|err|
                cleanup-merge-fixture $tmp_dir $owner_cache
                error make {msg: $err.msg}
            })

            cleanup-merge-fixture $tmp_dir $owner_cache

            let nodes = $result.nodes
            let images = $result.images

            let node_ok = (
                (($nodes | get "svc:v1") == "sha256:abc123")
                and (($nodes | get "svc:v2") == "sha256:abc123")
            )
            let img = ($images | get "sha256:abc123")
            let refs_ok = (($img.refs | sort) == ["ref1" "ref2"])
            let owner_ok = ($img.owner_service == $owner_name)

            $node_ok and $refs_ok and $owner_ok
        } $verbose)
    ]
}
