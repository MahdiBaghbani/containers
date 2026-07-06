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

# validate-ssh-config happy/invalid paths.

use ../../lib/validate/ssh.nu [validate-ssh-config]
use ../lib.nu [run-test]

export def validate-config-tests [verbose: bool] {
    [
        (run-test "validate-ssh-config: disabled mode valid" {
            let config = { enabled: false, mode: "disabled", default_user: "root", port: 22 }
            validate-ssh-config $config "test-service"
            true
        } $verbose)
        (run-test "validate-ssh-config: client mode valid" {
            let config = { enabled: true, mode: "client", default_user: "root", port: 22 }
            validate-ssh-config $config "test-service"
            true
        } $verbose)
        (run-test "validate-ssh-config: server mode valid" {
            let config = { enabled: true, mode: "server", default_user: "root", port: 22 }
            validate-ssh-config $config "test-service"
            true
        } $verbose)
        (run-test "validate-ssh-config: client-and-server mode valid" {
            let config = { enabled: true, mode: "client-and-server", default_user: "root", port: 22 }
            validate-ssh-config $config "test-service"
            true
        } $verbose)
        (run-test "validate-ssh-config: invalid mode rejected" {
            let config = { enabled: true, mode: "invalid", default_user: "root", port: 22 }
            let result = (validate-ssh-config $config "test-service")
            if $result.valid {
                error make {msg: "Expected validation to fail for invalid SSH mode"}
            }
            true
        } $verbose)
        (run-test "validate-ssh-config: invalid port rejected" {
            let config = { enabled: true, mode: "server", default_user: "root", port: 99999 }
            let result = (validate-ssh-config $config "test-service")
            if $result.valid {
                error make {msg: "Expected validation to fail for invalid SSH port"}
            }
            true
        } $verbose)
        (run-test "validate-ssh-config: missing mode when enabled rejected" {
            let config = { enabled: true, default_user: "root", port: 22 }
            let result = (validate-ssh-config $config "test-service")
            if $result.valid {
                error make {msg: "Expected validation to fail for missing mode when enabled"}
            }
            true
        } $verbose)
    ]
}
