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

# Merged-config TLS dependency contract tests.

use ../../lib/validate/core.nu [validate-tls-config-merged]
use ../lib.nu [run-test]

export def tls-merged-dep-tests [verbose: bool] {
  [
    (run-test "validate-tls-config-merged: TLS-enabled passes when common-tools supplied via merge" {
      let merged = {
        tls: {enabled: true, mode: "ca-only"},
        dependencies: {ct: {service: "common-tools", build_arg: "COMMON_TOOLS_REF"}}
      }
      let result = (validate-tls-config-merged $merged "svc")
      if not $result.valid {
        error make {msg: $"Expected TLS-enabled service with merged common-tools dep to pass, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
    (run-test "validate-tls-config-merged: TLS-enabled fails when common-tools absent after merge" {
      let merged = {tls: {enabled: true, mode: "ca-only"}}
      let result = (validate-tls-config-merged $merged "svc")
      if $result.valid {
        error make {msg: "Expected TLS-enabled service without common-tools dep to fail"}
      }
      let has_ct_err = ($result.errors | any {|e| ($e | str contains "common-tools") and ($e | str contains "missing")})
      if not $has_ct_err {
        error make {msg: $"Expected missing common-tools dependency error, got: ($result.errors | str join ', ')"}
      }
      true
    } $verbose)
  ]
}
