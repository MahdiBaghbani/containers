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

# validate-version-overrides-ssh valid + warn behavior.

use ../../lib/validate/ssh.nu [validate-version-overrides-ssh]
use ../lib.nu [run-test]

export def version-overrides-tests [verbose: bool] {
    [
        (run-test "validate-version-overrides-ssh: valid version override" {
            let version = { version: "v1.0.0", ssh: { enabled: true, mode: "client", default_user: "root", port: 22 } }
            validate-version-overrides-ssh $version "test-service"
            true
        } $verbose)
        (run-test "validate-version-overrides-ssh: warns on version override" {
            let version = { version: "v1.0.0", ssh: { enabled: true, mode: "client", default_user: "root", port: 22 } }
            let result = (validate-version-overrides-ssh $version "test-service")
            if not $result.valid {
                error make {msg: "Expected validation to pass with warning"}
            }
            if ($result.warnings | is-empty) {
                error make {msg: "Expected warning for version-level SSH override"}
            }
            true
        } $verbose)
    ]
}
