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

# defaults-placement checks: forbidden TLS and valid/invalid SSH in defaults.

use ../../lib/validate/core.nu [validate-version-defaults]
use ../lib.nu [run-test]

export def defaults-placement-tests [verbose: bool] {
  [
    (run-test "validate-version-defaults: rejects TLS in global defaults" {
      let defaults = {tls: {enabled: true, mode: "ca-only"}}
      let result = (validate-version-defaults $defaults)
      if $result.valid {
        error make {msg: "Expected TLS in version defaults to be rejected"}
      }
      let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
      if not $has_tls_err {
        error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-defaults: rejects TLS in defaults.platforms.*" {
      let defaults = {platforms: {alpine: {tls: {enabled: true, mode: "ca-only"}}}}
      let result = (validate-version-defaults $defaults)
      if $result.valid {
        error make {msg: "Expected TLS in defaults.platforms.* to be rejected"}
      }
      let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
      if not $has_tls_err {
        error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-defaults: accepts valid SSH in defaults" {
      let defaults = {ssh: {enabled: false, mode: "disabled"}}
      let result = (validate-version-defaults $defaults)
      if not $result.valid {
        error make {msg: $"Expected valid SSH defaults to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-defaults: rejects invalid SSH in defaults" {
      let defaults = {ssh: {enabled: true, mode: "not-a-mode"}}
      let result = (validate-version-defaults $defaults)
      if $result.valid {
        error make {msg: "Expected invalid SSH mode in defaults to be rejected"}
      }
      true
    } $verbose)
    (run-test "validate-version-defaults: accepts valid defaults.platforms.*.ssh" {
      let defaults = {platforms: {alpine: {ssh: {enabled: true, mode: "server", port: 22}}}}
      let result = (validate-version-defaults $defaults)
      if not $result.valid {
        error make {msg: $"Expected valid platform SSH defaults to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-defaults: rejects invalid defaults.platforms.*.ssh" {
      let defaults = {platforms: {alpine: {ssh: {enabled: true, mode: "not-a-mode"}}}}
      let result = (validate-version-defaults $defaults)
      if $result.valid {
        error make {msg: "Expected invalid platform SSH mode in defaults to be rejected"}
      }
      let has_ssh_err = ($result.errors | any {|e| $e | str contains "ssh.mode"})
      if not $has_ssh_err {
        error make {msg: $"Expected ssh.mode error from defaults.platforms.*, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
