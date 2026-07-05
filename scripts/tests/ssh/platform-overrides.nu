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

# validate-platform-ssh valid + invalid cases.

use ../../lib/validate/ssh.nu [validate-platform-ssh]
use ../lib.nu [run-test]

export def platform-overrides-tests [verbose: bool] {
    [
        (run-test "validate-platform-ssh: valid platform override" {
            let platform = { name: "dev", ssh: { enabled: true, mode: "server", default_user: "root", port: 22 } }
            validate-platform-ssh $platform "test-service"
            true
        } $verbose)
        (run-test "validate-platform-ssh: invalid platform override rejected" {
            let platform = { name: "dev", ssh: { enabled: true, mode: "bad", default_user: "root", port: 22 } }
            let result = (validate-platform-ssh $platform "test-service")
            if $result.valid {
                error make {msg: "Expected validation to fail for invalid platform SSH override"}
            }
            true
        } $verbose)
    ]
}
