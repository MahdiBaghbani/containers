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

# Clone-source cache population/reuse and ref-kind auto-detect tests (Tests 48-51).

use ../../lib/build/clone-source.nu [run-clone-source]
use ../lib.nu [run-test]
use ./_fixtures.nu [rm-temp-context seed-local-git-repo]

export def clone-source-cache-tests [verbose: bool] {
    [
        (run-test "Test 48: clone-source cache-dir ref mode populates cache and dest" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let branch = (^git -C $origin branch --show-current | str trim)
            let cache = ($base | path join "cache")
            let dest = ($base | path join "checkout")
            let url = $"file://($origin)"

            run-clone-source --mode git --ref-kind ref --url $url --ref $branch --cache-dir $cache --dest $dest

            if not (($cache | path join ".git") | path exists) {
              rm-temp-context $base
              error make {msg: "Expected cache-dir to be populated with .git"}
            }
            let dest_head = (^git -C $dest rev-parse HEAD | str trim)
            if $dest_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected dest HEAD ($dest_head) to match origin ($head)"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 49: clone-source reuses populated cache without refetching" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let branch = (^git -C $origin branch --show-current | str trim)
            let cache = ($base | path join "cache")
            let dest1 = ($base | path join "checkout1")
            let dest2 = ($base | path join "checkout2")
            let url = $"file://($origin)"

            run-clone-source --mode git --ref-kind ref --url $url --ref $branch --cache-dir $cache --dest $dest1

            # Second run uses a bogus URL. It must succeed by reusing the populated
            # cache; a refetch would fail against the nonexistent remote.
            run-clone-source --mode git --ref-kind ref --url "file:///nonexistent/repo.git" --ref $branch --cache-dir $cache --dest $dest2

            let dest2_head = (^git -C $dest2 rev-parse HEAD | str trim)
            if $dest2_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected reused-cache dest HEAD ($dest2_head) to match origin ($head)"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 50: clone-source auto-detects ref-kind from ref" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let branch = (^git -C $origin branch --show-current | str trim)
            let url = $"file://($origin)"

            # Empty ref-kind with a full 40-hex SHA -> sha path.
            let dest_sha = ($base | path join "by-sha")
            run-clone-source --mode git --url $url --ref $head --dest $dest_sha
            let sha_head = (^git -C $dest_sha rev-parse HEAD | str trim)
            if $sha_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected auto-detected sha HEAD ($sha_head) to match ($head)"}
            }

            # Empty ref-kind with a branch name -> ref path.
            let dest_ref = ($base | path join "by-ref")
            run-clone-source --mode git --url $url --ref $branch --dest $dest_ref
            let ref_head = (^git -C $dest_ref rev-parse HEAD | str trim)
            if $ref_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected auto-detected ref HEAD ($ref_head) to match ($head)"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 50b: clone-source main entrypoint auto-detects when --ref-kind is omitted" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let dest = ($base | path join "checkout")
            let url = $"file://($origin)"
            let helper = "scripts/lib/build/clone-source.nu"

            let out = (^nu $helper --mode git --url $url --ref $head --dest $dest | complete)
            if $out.exit_code != 0 {
              rm-temp-context $base
              let detail = (($out.stderr | str join "") + ($out.stdout | str join ""))
              error make {msg: $"Expected CLI entrypoint to accept omitted --ref-kind, got: ($detail)"}
            }

            let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
            if $cloned_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected cloned HEAD ($cloned_head) to match origin ($head) when --ref-kind is omitted"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 51: clone-source local mode ignores cache-dir" {
            let base = (^mktemp -d | str trim)
            let src = ($base | path join "src")
            mkdir $src
            "local fixture" | save -f ($src | path join "marker.txt")
            let cache = ($base | path join "cache")
            let dest = ($base | path join "dest")

            run-clone-source --mode local --local-dir $src --cache-dir $cache --dest $dest

            if not (($dest | path join "marker.txt") | path exists) {
              rm-temp-context $base
              error make {msg: "Expected marker.txt copied into destination in local mode"}
            }
            if ($cache | path exists) {
              rm-temp-context $base
              error make {msg: "Expected cache-dir untouched in local mode"}
            }

            rm-temp-context $base
            true
        } $verbose)
    ]
}
