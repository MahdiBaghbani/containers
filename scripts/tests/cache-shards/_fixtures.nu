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

# Temp fixture helpers for cache-shards suite tests.

use ../../lib/build/cache.nu [get-owner-cache-dir]

export def rm-tmp [dir: string] {
    try { rm -rf $dir } catch { }
}

# Returns tmp_dir, owner_name, and owner_cache for merge-node-shards tests.
export def make-merge-fixture [] {
    let tmp_dir = (^mktemp -d | str trim)
    let owner_name = ($tmp_dir | path basename)
    {
        tmp_dir: $tmp_dir
        owner_name: $owner_name
        owner_cache: $"/tmp/docker-images/($owner_name)"
    }
}

export def cleanup-merge-fixture [tmp_dir: string, owner_cache: string] {
    rm-tmp $tmp_dir
    rm-tmp $owner_cache
}

# Returns test_svc and cache_dir for manifest round-trip tests.
export def make-roundtrip-service [] {
    let tmp_marker = (^mktemp -d | str trim)
    let test_svc = $"__test-rt-($tmp_marker | path basename)__"
    rm-tmp $tmp_marker
    {
        test_svc: $test_svc
        cache_dir: (get-owner-cache-dir $test_svc)
    }
}
