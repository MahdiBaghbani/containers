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

# Registries domain test suite

use ../lib/registries/info.nu [get-registry-info]
use ../lib/registries/core.nu [login-ghcr login-default-registry]
use ./lib.nu [run-test print-test-summary]

def main [--verbose] {
  mut results = []

  # Test: get-registry-info returns expected structure
  let test1 = (run-test "get-registry-info returns record with required fields" {
    let info = (get-registry-info)
    let has_ci_platform = ("ci_platform" in ($info | columns))
    let has_github_registry = ("github_registry" in ($info | columns))
    let has_owner = ("owner" in ($info | columns))
    let has_repo = ("repo" in ($info | columns))
    $has_ci_platform and $has_github_registry and $has_owner and $has_repo
  } $verbose)
  $results = ($results | append $test1)

  # Test: get-registry-info returns github registry as ghcr.io
  let test2 = (run-test "get-registry-info returns ghcr.io as github_registry" {
    let info = (get-registry-info)
    $info.github_registry == "ghcr.io"
  } $verbose)
  $results = ($results | append $test2)

  # Test: get-registry-info detects local CI platform when not in CI
  let test3 = (run-test "get-registry-info detects ci_platform" {
    let info = (get-registry-info)
    # Should be one of: local, github, forgejo
    let valid_platforms = ["local" "github" "forgejo"]
    $info.ci_platform in $valid_platforms
  } $verbose)
  $results = ($results | append $test3)

  # Test: get-registry-info returns owner and repo
  let test4 = (run-test "get-registry-info returns non-empty owner" {
    let info = (get-registry-info)
    ($info.owner | str length) > 0
  } $verbose)
  $results = ($results | append $test4)

  # Test: login-ghcr returns ok: false when GITHUB_TOKEN is missing
  let test5 = (run-test "login-ghcr fails without GITHUB_TOKEN" {
    with-env { GITHUB_TOKEN: "", GITHUB_ACTOR: "" } {
      let result = (login-ghcr)
      (not $result.ok) and ($result.reason | str contains "no token")
    }
  } $verbose)
  $results = ($results | append $test5)

  # Test: login-default-registry returns no-op for local platform
  let test6 = (run-test "login-default-registry no-op for local platform" {
    with-env {} {
      # When GITHUB_ACTIONS is not set, should return no-op
      let result = (login-default-registry)
      $result.ok and ($result.reason | str contains "no-op")
    }
  } $verbose)
  $results = ($results | append $test6)

  # Test: login-default-registry returns no-op when ci_platform detects github but GITHUB_ACTIONS is not "true"
  let test7 = (run-test "login-default-registry no-op when GITHUB_ACTIONS not true" {
    with-env { GITHUB_REPOSITORY: "test/owner" } {
      # Even if GITHUB_REPOSITORY is set, if GITHUB_ACTIONS is not "true", should return no-op
      let result = (login-default-registry)
      $result.ok and ($result.reason | str contains "no-op")
    }
  } $verbose)
  $results = ($results | append $test7)

  print-test-summary $results

  let failed = ($results | where {|r| not $r} | length)
  if $failed > 0 {
    exit 1
  }
}

