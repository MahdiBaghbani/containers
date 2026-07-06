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

# Forbidden override and infrastructure-field checks.

use ../../lib/validate/core.nu [validate-version-overrides-structure]
use ../lib.nu [run-test]

export def overrides-guards-tests [verbose: bool] {
  [
    (run-test "validate-version-overrides-structure: rejects platforms.*.tls override" {
      let overrides = {platforms: {alpine: {tls: {enabled: true, mode: "ca-only"}}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if $result.valid {
        error make {msg: "Expected TLS in overrides.platforms.* to be rejected"}
      }
      let has_tls_err = ($result.errors | any {|e| $e | str contains "tls: Section forbidden"})
      if not $has_tls_err {
        error make {msg: $"Expected 'tls: Section forbidden' message, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-overrides-structure: forbids external_images.*.name" {
      let overrides = {external_images: {build: {name: "golang"}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if $result.valid {
        error make {msg: "Expected external_images.*.name in overrides to be rejected"}
      }
      let has_name_err = ($result.errors | any {|e| $e | str contains "external_images.build.name"})
      if not $has_name_err {
        error make {msg: $"Expected external_images name forbidden error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-overrides-structure: forbids dependencies.*.service" {
      let overrides = {dependencies: {ct: {service: "common-tools"}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if $result.valid {
        error make {msg: "Expected dependencies.*.service in overrides to be rejected"}
      }
      true
    } $verbose)
  ]
}
