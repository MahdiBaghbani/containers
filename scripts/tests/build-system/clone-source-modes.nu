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

# Clone-source local/ref/sha behavior and invalid-input tests (Tests 40-46).

use ../../lib/build/clone-source.nu [run-clone-source]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    rm-temp-context
    with-git-file-protocol-allowed
    seed-local-git-repo
    seed-git-repo-with-submodule
]

export def clone-source-modes-tests [verbose: bool] {
    [
        (run-test "Test 40: clone-source local mode copies directory contents" {
            let src = (^mktemp -d | str trim)
            let dest = (^mktemp -d | str trim)
            "local fixture" | save -f ($src | path join "marker.txt")

            run-clone-source --mode local --local-dir $src --dest $dest

            if not (($dest | path join "marker.txt") | path exists) {
              rm-temp-context $src
              rm-temp-context $dest
              error make {msg: "Expected marker.txt copied into destination"}
            }

            rm-temp-context $src
            rm-temp-context $dest
            true
        } $verbose)

        (run-test "Test 41: clone-source ref mode clones local git repository" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let branch = (^git -C $origin branch --show-current | str trim)
            let dest = ($base | path join "checkout")
            let url = $"file://($origin)"

            run-clone-source --mode git --ref-kind ref --url $url --ref $branch --dest $dest

            let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
            if $cloned_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected cloned HEAD ($cloned_head) to match origin ($head)"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 42: clone-source sha mode fetches local git repository" {
            let base = (^mktemp -d | str trim)
            let origin = ($base | path join "origin")
            let head = (seed-local-git-repo $origin)
            let dest = ($base | path join "checkout")
            let url = $"file://($origin)"

            run-clone-source --mode git --ref-kind sha --url $url --ref $head --dest $dest

            let cloned_head = (^git -C $dest rev-parse HEAD | str trim)
            if $cloned_head != $head {
              rm-temp-context $base
              error make {msg: $"Expected cloned HEAD ($cloned_head) to match SHA ($head)"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 43: clone-source ref mode skips submodules when disabled" {
            let base = (^mktemp -d | str trim)
            let fixture = (seed-git-repo-with-submodule $base)
            let dest = ($base | path join "checkout")

            run-clone-source --mode git --ref-kind ref --url $fixture.url --ref $fixture.branch --dest $dest --submodules "false"

            let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
            if ($sub_marker | path exists) {
              rm-temp-context $base
              error make {msg: "Expected submodule content absent when SOURCE_SUBMODULES=false"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 44: clone-source ref mode recurses submodules by default" {
            let base = (^mktemp -d | str trim)
            let fixture = (seed-git-repo-with-submodule $base)
            let dest = ($base | path join "checkout")

            with-git-file-protocol-allowed {
              run-clone-source --mode git --ref-kind ref --url $fixture.url --ref $fixture.branch --dest $dest
            }

            let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
            if not ($sub_marker | path exists) {
              rm-temp-context $base
              error make {msg: "Expected submodule content present when SOURCE_SUBMODULES defaults to true"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 45: clone-source sha mode recurses submodules by default" {
            let base = (^mktemp -d | str trim)
            let fixture = (seed-git-repo-with-submodule $base)
            let dest = ($base | path join "checkout")

            with-git-file-protocol-allowed {
              run-clone-source --mode git --ref-kind sha --url $fixture.url --ref $fixture.head --dest $dest
            }

            let sub_marker = ($dest | path join "submodule" "sub-marker.txt")
            if not ($sub_marker | path exists) {
              rm-temp-context $base
              error make {msg: "Expected submodule content present when SOURCE_SUBMODULES defaults to true in sha mode"}
            }

            rm-temp-context $base
            true
        } $verbose)

        (run-test "Test 46: clone-source main entrypoint rejects invalid inputs" {
            let helper = "scripts/lib/build/clone-source.nu"
            let dest = (^mktemp -d | str trim)

            let bad_sha = (^nu $helper --mode git --ref-kind sha --url "https://example.com/repo.git" --ref "not-a-sha" --dest $dest | complete)
            if $bad_sha.exit_code == 0 {
              rm-temp-context $dest
              error make {msg: "Expected non-zero exit for invalid SHA at main entrypoint"}
            }
            let bad_sha_out = ($bad_sha.stderr | str join "") + ($bad_sha.stdout | str join "")
            if not ($bad_sha_out | str contains "40-character SHA") {
              rm-temp-context $dest
              error make {msg: $"Expected SHA validation error, got: ($bad_sha_out)"}
            }

            let bad_kind = (^nu $helper --mode git --ref-kind bogus --url "https://example.com/repo.git" --ref "main" --dest $dest | complete)
            if $bad_kind.exit_code == 0 {
              rm-temp-context $dest
              error make {msg: "Expected non-zero exit for invalid ref-kind at main entrypoint"}
            }
            let bad_kind_out = ($bad_kind.stderr | str join "") + ($bad_kind.stdout | str join "")
            if not ($bad_kind_out | str contains "Invalid SOURCE_MODE/SOURCE_REF_KIND") {
              rm-temp-context $dest
              error make {msg: $"Expected ref-kind validation error, got: ($bad_kind_out)"}
            }

            let no_dest = (^nu $helper --mode git --ref-kind ref --url "https://example.com/repo.git" --ref "main" | complete)
            if $no_dest.exit_code == 0 {
              rm-temp-context $dest
              error make {msg: "Expected non-zero exit when SOURCE_DEST is missing at main entrypoint"}
            }
            let no_dest_out = ($no_dest.stderr | str join "") + ($no_dest.stdout | str join "")
            if not ($no_dest_out | str contains "SOURCE_DEST must be provided") {
              rm-temp-context $dest
              error make {msg: $"Expected missing-dest validation error, got: ($no_dest_out)"}
            }

            rm-temp-context $dest
            true
        } $verbose)
    ]
}
