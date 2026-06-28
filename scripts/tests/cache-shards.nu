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
use ../lib/ci/cache-shards.nu [make-node-key merge-node-shards make-shard-name]
use ../lib/build/cache.nu [
    write-manifest read-manifest
    get-owner-cache-dir get-manifest-path get-image-tarball-path
    parse-dep-cache-mode
]

def rm-tmp [dir: string] {
    try { rm -rf $dir } catch { }
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    # ------------------------------------------------------------------
    # make-node-key
    # ------------------------------------------------------------------

    let t1 = (run-test "make-node-key single-platform" {
        (make-node-key "svc" "v1" "") == "svc:v1"
    } $verbose_flag)
    $results = ($results | append $t1)

    let t2 = (run-test "make-node-key multi-platform" {
        (make-node-key "svc" "v1" "linux-amd64") == "svc:v1:linux-amd64"
    } $verbose_flag)
    $results = ($results | append $t2)

    # ------------------------------------------------------------------
    # make-shard-name
    # ------------------------------------------------------------------

    let t_shard_name_single = (run-test "make-shard-name single-platform uses 'single' suffix" {
        (make-shard-name "dep-tools" "v1.0.0" "") == "shard-dep-tools-v1.0.0-single"
    } $verbose_flag)
    $results = ($results | append $t_shard_name_single)

    let t_shard_name_platform = (run-test "make-shard-name multi-platform uses platform suffix" {
        (make-shard-name "parent-svc" "v2.0.0" "production") == "shard-parent-svc-v2.0.0-production"
    } $verbose_flag)
    $results = ($results | append $t_shard_name_platform)

    # ------------------------------------------------------------------
    # merge-node-shards
    # ------------------------------------------------------------------

    let t3 = (run-test "merge-node-shards merges manifests and deduplicates images" {
        let tmp_dir = (^mktemp -d | str trim)
        let owner_name = ($tmp_dir | path basename)
        let owner_cache = $"/tmp/docker-images/($owner_name)"

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
            rm-tmp $tmp_dir
            rm-tmp $owner_cache
            error make {msg: $err.msg}
        })

        rm-tmp $tmp_dir
        rm-tmp $owner_cache

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
    } $verbose_flag)
    $results = ($results | append $t3)

    # ------------------------------------------------------------------
    # Cache path helpers (get-owner-cache-dir, get-manifest-path,
    # get-image-tarball-path)
    # ------------------------------------------------------------------

    let t_cache_dir = (run-test "get-owner-cache-dir returns /tmp/docker-images/<service>" {
        let dir = (get-owner-cache-dir "my-svc")
        $dir == "/tmp/docker-images/my-svc"
    } $verbose_flag)
    $results = ($results | append $t_cache_dir)

    let t_manifest_path = (run-test "get-manifest-path returns .../manifest.nuon" {
        let p = (get-manifest-path "my-svc")
        $p == "/tmp/docker-images/my-svc/manifest.nuon"
    } $verbose_flag)
    $results = ($results | append $t_manifest_path)

    let t_tarball_path = (run-test "get-image-tarball-path strips sha256: prefix" {
        let p = (get-image-tarball-path "my-svc" "sha256:deadbeef")
        $p == "/tmp/docker-images/my-svc/deadbeef.tar.zst"
    } $verbose_flag)
    $results = ($results | append $t_tarball_path)

    let t_tarball_no_prefix = (run-test "get-image-tarball-path works without sha256: prefix" {
        let p = (get-image-tarball-path "my-svc" "deadbeef")
        $p == "/tmp/docker-images/my-svc/deadbeef.tar.zst"
    } $verbose_flag)
    $results = ($results | append $t_tarball_no_prefix)

    # ------------------------------------------------------------------
    # parse-dep-cache-mode
    # ------------------------------------------------------------------

    let t_mode_empty_local = (run-test "parse-dep-cache-mode: empty local -> off" {
        (parse-dep-cache-mode "" true) == "off"
    } $verbose_flag)
    $results = ($results | append $t_mode_empty_local)

    let t_mode_empty_ci = (run-test "parse-dep-cache-mode: empty CI -> soft" {
        (parse-dep-cache-mode "" false) == "soft"
    } $verbose_flag)
    $results = ($results | append $t_mode_empty_ci)

    let t_mode_explicit = (run-test "parse-dep-cache-mode: explicit mode passthrough" {
        let modes = ["off" "soft" "strict"]
        $modes | all {|m| (parse-dep-cache-mode $m true) == $m}
    } $verbose_flag)
    $results = ($results | append $t_mode_explicit)

    let t_mode_invalid = (run-test "parse-dep-cache-mode: invalid mode -> error" {
        let errored = (try {
            parse-dep-cache-mode "bogus-mode" true
            false
        } catch { true })
        $errored
    } $verbose_flag)
    $results = ($results | append $t_mode_invalid)

    # ------------------------------------------------------------------
    # write-manifest / read-manifest round-trip
    # ------------------------------------------------------------------

    let t_roundtrip = (run-test "write-manifest + read-manifest round-trip" {
        let tmp_marker = (^mktemp -d | str trim)
        let test_svc = $"__test-rt-($tmp_marker | path basename)__"
        rm-tmp $tmp_marker
        let cache_dir = (get-owner-cache-dir $test_svc)

        let node_image_map = {
            nodes: {"svc:v1:prod": "sha256:aaa", "svc:v1:dev": "sha256:bbb"},
            images: {
                "sha256:aaa": {refs: ["reg/svc:v1-prod"], owner_service: $test_svc},
                "sha256:bbb": {refs: ["reg/svc:v1-dev"], owner_service: $test_svc}
            }
        }

        try {
            write-manifest $test_svc $node_image_map
        } catch {|err|
            rm-tmp $cache_dir
            error make {msg: $err.msg}
        }

        let manifest = (try {
            read-manifest $test_svc
        } catch {|err|
            rm-tmp $cache_dir
            error make {msg: $err.msg}
        })

        rm-tmp $cache_dir

        if $manifest == null {
            error make {msg: "read-manifest returned null after write-manifest"}
        }
        if $manifest.owner_service != $test_svc {
            error make {msg: $"owner_service mismatch: ($manifest.owner_service)"}
        }
        let nodes = $manifest.nodes
        if ($nodes | get "svc:v1:prod") != "sha256:aaa" {
            error make {msg: "node svc:v1:prod not found or wrong image_id"}
        }
        if ($nodes | get "svc:v1:dev") != "sha256:bbb" {
            error make {msg: "node svc:v1:dev not found or wrong image_id"}
        }
        let img = ($manifest.images | get "sha256:aaa")
        if $img.owner_service != $test_svc {
            error make {msg: $"image owner_service mismatch: ($img.owner_service)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_roundtrip)

    let t_read_missing = (run-test "read-manifest: missing manifest returns null" {
        let manifest = (read-manifest "__no-such-svc-xyzzy__")
        $manifest == null
    } $verbose_flag)
    $results = ($results | append $t_read_missing)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
