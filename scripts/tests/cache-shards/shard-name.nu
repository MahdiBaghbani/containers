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

# make-shard-name single- and platform-suffixed forms.

use ../../lib/ci/cache-shards.nu [make-shard-name]
use ../lib.nu [run-test]

export def shard-name-tests [verbose: bool] {
    [
        (run-test "make-shard-name single-platform uses 'single' suffix" {
            (make-shard-name "dep-tools" "v1.0.0" "") == "shard-dep-tools-v1.0.0-single"
        } $verbose)
        (run-test "make-shard-name multi-platform uses platform suffix" {
            (make-shard-name "parent-svc" "v2.0.0" "production") == "shard-parent-svc-v2.0.0-production"
        } $verbose)
    ]
}
