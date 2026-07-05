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

# validate-local-path boundary contract tests.

use ../../lib/validate/core.nu [validate-local-path]
use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp rm-temp]

export def local-path-tests [verbose: bool] {
  [
    (run-test "validate-local-path: accepts directory inside repo root" {
      let repo_root = (get-repo-root)
      let result = (validate-local-path "services" $repo_root)
      if not $result.valid {
        error make {msg: $"Expected 'services' to be valid, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: rejects non-existent path" {
      let repo_root = (get-repo-root)
      let result = (validate-local-path "does-not-exist-xyz" $repo_root)
      if $result.valid {
        error make {msg: "Expected non-existent path to be rejected"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: rejects path outside repo root" {
      let tmp = (make-temp)
      let repo_root = ($tmp | path join "standalone")
      mkdir $repo_root
      mkdir ($tmp | path join "outside")
      let result = (validate-local-path "../outside" $repo_root)
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected ../outside to be rejected when repo root has no repos/ parent"}
      }
      let has_outside_err = ($result.errors | any {|e| $e | str contains "outside repository root"})
      if not $has_outside_err {
        error make {msg: $"Expected 'outside repository root' message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: accepts sibling clone under a repos/ parent" {
      let tmp = (make-temp)
      let repos_dir = ($tmp | path join "repos")
      let repo_root = ($repos_dir | path join "myrepo")
      let sibling = ($repos_dir | path join "sibling")
      mkdir $repo_root
      mkdir $sibling
      let result = (validate-local-path "../sibling" $repo_root)
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected sibling repos clone to be accepted, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: rejects a file (not a directory)" {
      let tmp = (make-temp)
      let repo_root = ($tmp | path join "repo")
      mkdir $repo_root
      "content" | save -f ($repo_root | path join "afile.txt")
      let result = (validate-local-path "afile.txt" $repo_root)
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected a file path to be rejected (not a directory)"}
      }
      let has_dir_err = ($result.errors | any {|e| $e | str contains "is not a directory"})
      if not $has_dir_err {
        error make {msg: $"Expected 'is not a directory' message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: accepts absolute path inside repo root" {
      let tmp = (make-temp)
      let repo_root = ($tmp | path join "repo")
      let inner = ($repo_root | path join "sub")
      mkdir $inner
      let result = (validate-local-path $inner $repo_root)
      rm-temp $tmp
      if not $result.valid {
        error make {msg: $"Expected absolute path inside repo to be valid, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-local-path: rejects absolute path outside repo root" {
      let tmp = (make-temp)
      let repo_root = ($tmp | path join "repo")
      let outside = ($tmp | path join "elsewhere")
      mkdir $repo_root
      mkdir $outside
      let result = (validate-local-path $outside $repo_root)
      rm-temp $tmp
      if $result.valid {
        error make {msg: "Expected absolute path outside repo root to be rejected"}
      }
      true
    } $verbose)
  ]
}
