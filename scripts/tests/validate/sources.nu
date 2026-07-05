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

# Source validation across base config, merged config, and version overrides.

use ../../lib/validate/core.nu [
  validate-service-config
  validate-merged-config
  validate-version-overrides-structure
]
use ../lib.nu [run-test]

export def sources-tests [verbose: bool] {
  [
    (run-test "validate-service-config: rejects non-lowercase source key (base)" {
      let config = {
        name: "svc",
        context: "services/svc",
        dockerfile: "services/svc/Dockerfile",
        sources: {"Bad-Key": {url: "https://example.com/x", ref: "v1"}}
      }
      let result = (validate-service-config $config false "svc")
      if $result.valid {
        error make {msg: "Expected invalid source key to be rejected"}
      }
      let has_key_err = ($result.errors | any {|e| $e | str contains "lowercase alphanumeric"})
      if not $has_key_err {
        error make {msg: $"Expected lowercase-key error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-service-config: rejects forbidden source build_arg (base)" {
      let config = {
        name: "svc",
        context: "services/svc",
        dockerfile: "services/svc/Dockerfile",
        sources: {good: {url: "https://example.com/x", ref: "v1", build_arg: "X_REF"}}
      }
      let result = (validate-service-config $config false "svc")
      if $result.valid {
        error make {msg: "Expected forbidden source build_arg to be rejected"}
      }
      let has_ba_err = ($result.errors | any {|e| ($e | str contains "build_arg") and ($e | str contains "forbidden")})
      if not $has_ba_err {
        error make {msg: $"Expected build_arg forbidden error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-merged-config: rejects git source missing ref (complete required)" {
      let merged = {sources: {svc: {url: "https://example.com/x"}}}
      let result = (validate-merged-config $merged "svc" false "")
      if $result.valid {
        error make {msg: "Expected merged git source missing ref to be rejected"}
      }
      let has_ref_err = ($result.errors | any {|e| $e | str contains "Missing required field 'ref'"})
      if not $has_ref_err {
        error make {msg: $"Expected missing-ref error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-overrides-structure: accepts partial source fragment" {
      let overrides = {sources: {svc: {ref: "main"}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if not $result.valid {
        error make {msg: $"Expected partial source override (ref-only) to be valid, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-version-overrides-structure: rejects non-lowercase source key" {
      let overrides = {sources: {"Bad": {ref: "main"}}}
      let result = (validate-version-overrides-structure $overrides "v1")
      if $result.valid {
        error make {msg: "Expected invalid source key in overrides to be rejected"}
      }
      let has_key_err = ($result.errors | any {|e| $e | str contains "lowercase alphanumeric"})
      if not $has_key_err {
        error make {msg: $"Expected lowercase-key error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
