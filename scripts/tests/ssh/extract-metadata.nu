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

# extract-ssh-metadata disabled and server cases.

use ../../lib/build/context.nu [extract-ssh-metadata]
use ../lib.nu [run-test]

export def extract-metadata-tests [verbose: bool] {
    [
        (run-test "extract-ssh-metadata: disabled returns defaults" {
            let merged = { ssh: { enabled: false, mode: "disabled", default_user: "root", port: 22 } }
            let meta = (extract-ssh-metadata $merged)
            if $meta.enabled != false {
                error make {msg: "Expected enabled=false"}
            }
            if $meta.mode != "disabled" {
                error make {msg: "Expected mode=disabled"}
            }
            true
        } $verbose)
        (run-test "extract-ssh-metadata: server mode extracts correctly" {
            let merged = { ssh: { enabled: true, mode: "server", default_user: "admin", port: 2222 } }
            let meta = (extract-ssh-metadata $merged)
            if $meta.enabled != true {
                error make {msg: "Expected enabled=true"}
            }
            if $meta.mode != "server" {
                error make {msg: "Expected mode=server"}
            }
            if $meta.default_user != "admin" {
                error make {msg: "Expected default_user=admin"}
            }
            if $meta.port != 2222 {
                error make {msg: "Expected port=2222"}
            }
            true
        } $verbose)
    ]
}
