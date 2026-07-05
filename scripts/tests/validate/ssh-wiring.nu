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

# SSH validation through service, platform, and override paths.

use ../../lib/validate/core.nu [
  validate-service-config
  validate-platforms-manifest
  validate-version-overrides-structure
]
use ../lib.nu [run-test]

export def ssh-wiring-base-tests [verbose: bool] {
  [
    (run-test "validate-service-config: accepts valid base SSH config" {
      let config = {
        name: "svc",
        context: "services/svc",
        ssh: {enabled: true, mode: "server", default_user: "root", port: 22}
      }
      let result = (validate-service-config $config true "svc")
      if not $result.valid {
        error make {msg: $"Expected base SSH config to be valid, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-config: rejects invalid base SSH config" {
      let config = {
        name: "svc",
        context: "services/svc",
        ssh: {enabled: true, mode: "bogus"}
      }
      let result = (validate-service-config $config true "svc")
      if $result.valid {
        error make {msg: "Expected invalid base SSH mode to be rejected"}
      }
      let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
      if not $has_ssh_err {
        error make {msg: $"Expected ssh.mode error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-platforms-manifest: rejects invalid platform SSH via entrypoint" {
      let manifest = {
        default: "alpine",
        platforms: [
          {name: "alpine", dockerfile: "services/svc/Dockerfile.alpine", ssh: {enabled: true, mode: "bogus"}}
        ]
      }
      let result = (validate-platforms-manifest $manifest)
      if $result.valid {
        error make {msg: "Expected invalid platform SSH mode to be rejected via validate-platforms-manifest"}
      }
      let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
      if not $has_ssh_err {
        error make {msg: $"Expected ssh.mode error from platforms manifest entrypoint, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}

export def ssh-wiring-override-tests [verbose: bool] {
  [
    (run-test "validate-version-overrides-structure: accepts valid platforms.*.ssh override" {
      let overrides = {platforms: {alpine: {ssh: {enabled: true, mode: "server", port: 22}}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if not $result.valid {
        error make {msg: $"Expected valid platform SSH override to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-overrides-structure: rejects invalid platforms.*.ssh override" {
      let overrides = {platforms: {alpine: {ssh: {enabled: true, mode: "bogus"}}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if $result.valid {
        error make {msg: "Expected invalid platform SSH override mode to be rejected"}
      }
      let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
      if not $has_ssh_err {
        error make {msg: $"Expected ssh.mode error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
