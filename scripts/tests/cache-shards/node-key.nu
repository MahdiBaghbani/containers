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

# make-node-key single- and multi-platform cases.

use ../../lib/ci/cache-shards.nu [make-node-key]
use ../lib.nu [run-test]

export def node-key-tests [verbose: bool] {
    [
        (run-test "make-node-key single-platform" {
            (make-node-key "svc" "v1" "") == "svc:v1"
        } $verbose)
        (run-test "make-node-key multi-platform" {
            (make-node-key "svc" "v1" "linux-amd64") == "svc:v1:linux-amd64"
        } $verbose)
    ]
}
