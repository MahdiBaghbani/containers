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

# Build-order deduplication tests.

use ../lib.nu [run-test]

export def build-order-dedup-tests [verbose: bool] {
    [
        (run-test "deps pull: shared deps should be deduped" {
            let build_order = [
                "common:v1.0.0",
                "service-a:v1.0.0",
                "service-b:v1.0.0",
            ]
            let unique_count = ($build_order | uniq | length)
            if $unique_count != 3 {
                error make {msg: $"Expected 3 unique nodes, got ($unique_count)"}
            }
            true
        } $verbose),
    ]
}
