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

# All-services continue-on-failure regression (synthetic, no Docker).

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]
use ./_fixtures.nu [
  ALL_SERVICES_A ALL_SERVICES_B ALL_SERVICES_C ALL_SERVICES_D
  make-temp-build-repo rm-temp-repo
  seed-all-services-continue-fixture seed-all-services-dep-cache-fixture
  make-docker-stub-fail-on
  run-dockypody-in-repo
]

def run-synthetic-build [
  repo: string,
  args: list,
  fail_pattern: string,
  ci: bool = false
] {
  let log_file = ($repo | path join "docker-invocations.log")
  let stub_dir = (make-docker-stub-fail-on $log_file $fail_pattern)
  let patched_path = ([$stub_dir] | append ($env.PATH | default []))
  let entry = (get-repo-root | path join "scripts" "dockypody.nu")
  let result = (if $ci {
    with-env {PATH: $patched_path, GITHUB_ACTIONS: "true"} {
      run-dockypody-in-repo $repo $entry $args
    }
  } else {
    with-env {PATH: $patched_path, GITHUB_ACTIONS: ""} {
      run-dockypody-in-repo $repo $entry $args
    }
  })
  try { rm -rf $stub_dir } catch { }
  $result
}

export def all-services-continue-on-failure-tests [verbose: bool] {
  [
    (run-test "Test 31a: All-services transitive failures skip dependents" {
      let repo = (make-temp-build-repo)
      seed-all-services-continue-fixture $repo

      let out = (run-synthetic-build $repo [build --all-services] $ALL_SERVICES_A)

      let combined = ($out.stdout + $out.stderr)
      rm-temp-repo $repo

      if $out.exit_code == 0 {
        error make {msg: $"Expected non-zero exit when one all-services build fails, got 0. Output: ($combined)"}
      }

      if not ($combined | str contains "=== Build Summary ===") {
        error make {msg: $"Expected build summary in output: ($combined)"}
      }
      if not ($combined | str contains "STATUS: FAILED") {
        error make {msg: $"Expected STATUS: FAILED in summary: ($combined)"}
      }
      if not ($combined | str contains $"ERROR: Failed to build ($ALL_SERVICES_A):v1") {
        error make {msg: $"Expected failed service in output: ($combined)"}
      }
      if not ($combined | str contains $"Skipping ($ALL_SERVICES_B):v1") {
        error make {msg: $"Expected direct dependent to be skipped: ($combined)"}
      }
      if not ($combined | str contains $"Dependency failed: [($ALL_SERVICES_A):v1]") {
        error make {msg: $"Expected direct dependency reason: ($combined)"}
      }
      if not ($combined | str contains $"Skipping ($ALL_SERVICES_C):v1") {
        error make {msg: $"Expected transitive dependent to be skipped: ($combined)"}
      }
      if not ($combined | str contains $"Dependency failed: [($ALL_SERVICES_B):v1]") {
        error make {msg: $"Expected transitive dependency reason: ($combined)"}
      }
      if not ($combined | str contains $"OK: Successfully built ($ALL_SERVICES_D):v1") {
        error make {msg: $"Expected independent service to build: ($combined)"}
      }

      if $verbose {
        print $"    exit=($out.exit_code), A failed, B/C skipped, D built"
      }
      true
    } $verbose)
    ,
    (run-test "Test 31b: All-services forwards --dep-cache to synthetic builds" {
      let repo = (make-temp-build-repo)
      seed-all-services-dep-cache-fixture $repo
      let orchestrate_path = (get-repo-root | path join "scripts" "lib" "build" "orchestrate.nu")
      let node_build_call = (
        open $orchestrate_path
        | lines
        | where {|line| $line | str contains "build-single-version $node_service"}
        | first
      )
      if not ($node_build_call | str contains "$f.dep_cache") {
        rm-temp-repo $repo
        error make {msg: "All-services build stub call does not pass $f.dep_cache"}
      }
      let out = (run-synthetic-build $repo [build --all-services --dep-cache soft] "never-fails" true)
      let combined = ($out.stdout + $out.stderr)
      rm-temp-repo $repo

      if $out.exit_code != 0 {
        error make {msg: $"Expected soft dep-cache synthetic build to pass, got ($out.exit_code): ($combined)"}
      }
      if not ($combined | str contains "CI: Dependency") {
        error make {msg: $"Expected CI dep-cache decision from synthetic build: ($combined)"}
      }
      if ($combined | str contains "CI strict mode") {
        error make {msg: $"All-services ignored --dep-cache soft and used strict mode: ($combined)"}
      }
      if not ($combined | str contains $"OK: Successfully built ($ALL_SERVICES_D):v1") {
        error make {msg: $"Expected independent service success with soft dep-cache: ($combined)"}
      }

      if $verbose {
        print "    --dep-cache soft reached the CI synthetic build path"
      }
      true
    } $verbose)
    ,
    (run-test "Test 31c: All-services --fail-fast aborts after first failure" {
      let repo = (make-temp-build-repo)
      seed-all-services-continue-fixture $repo
      let out = (run-synthetic-build $repo [build --all-services --fail-fast] $ALL_SERVICES_A)
      let combined = ($out.stdout + $out.stderr)
      rm-temp-repo $repo

      if $out.exit_code == 0 {
        error make {msg: $"Expected fail-fast build to exit non-zero: ($combined)"}
      }
      if not ($combined | str contains $"ERROR: Failed to build ($ALL_SERVICES_A):v1") {
        error make {msg: $"Expected first failure in fail-fast output: ($combined)"}
      }
      if ($combined | str contains $"OK: Successfully built ($ALL_SERVICES_D):v1") {
        error make {msg: $"Fail-fast build continued to independent service: ($combined)"}
      }

      if $verbose {
        print "    --fail-fast aborted before later services"
      }
      true
    } $verbose)
  ]
}
