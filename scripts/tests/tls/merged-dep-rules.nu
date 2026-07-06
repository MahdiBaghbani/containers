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

# Merged TLS dependency behavior (validate-tls-config-merged).

use ../../lib/validate/tls.nu [validate-tls-config-merged]
use ../lib.nu [run-test]

export def merged-dep-rules-tests [verbose: bool] {
    [
        (run-test "validate-tls-config-merged: TLS without common-tools dep -> error" {
            let cfg = {
                tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc.crt"},
                dependencies: {}
            }
            let result = (validate-tls-config-merged $cfg "my-service")
            if $result.valid {
                error make {msg: "Expected validation failure when common-tools dep is missing"}
            }
            let has_common_tools_err = ($result.errors | any {|e| $e | str contains "common-tools"})
            if not $has_common_tools_err {
                error make {msg: $"Expected error mentioning 'common-tools', got: ($result.errors)"}
            }
            true
        } $verbose)
        (run-test "validate-tls-config-merged: TLS with common-tools dep -> valid" {
            let cfg = {
                tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc.crt"},
                dependencies: {
                    ct: {service: "common-tools", build_arg: "COMMON_TOOLS_IMAGE"}
                }
            }
            let result = (validate-tls-config-merged $cfg "my-service")
            if not $result.valid {
                error make {msg: $"Expected validation to pass, got errors: ($result.errors)"}
            }
            true
        } $verbose)
        (run-test "validate-tls-config-merged: common-tools itself skips dep check" {
            let cfg = {
                tls: {enabled: true, mode: "ca-only"},
                dependencies: {}
            }
            let result = (validate-tls-config-merged $cfg "common-tools")
            if not $result.valid {
                error make {msg: $"common-tools should not require a common-tools dep, got: ($result.errors)"}
            }
            true
        } $verbose)
        (run-test "validate-tls-config-merged: TLS disabled -> no common-tools required" {
            let cfg = {
                tls: {enabled: false},
                dependencies: {}
            }
            let result = (validate-tls-config-merged $cfg "some-service")
            if not $result.valid {
                error make {msg: $"TLS-disabled service should not require common-tools, got: ($result.errors)"}
            }
            true
        } $verbose)
    ]
}
