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

# parse-pull-modes tests.

use ../../lib/build/pull.nu [parse-pull-modes]
use ../lib.nu [run-test]

export def parse-pull-modes-tests [verbose: bool] {
    [
        (run-test "parse-pull-modes: empty string returns empty list" {
            let result = (parse-pull-modes "")
            if not ($result | is-empty) {
                error make {msg: $"Expected empty list, got: ($result)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: 'deps' returns [deps]" {
            let result = (parse-pull-modes "deps")
            if ($result | length) != 1 {
                error make {msg: $"Expected 1 element, got ($result | length)"}
            }
            if not ("deps" in $result) {
                error make {msg: $"Expected 'deps' in result, got: ($result)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: 'externals' returns [externals]" {
            let result = (parse-pull-modes "externals")
            if ($result | length) != 1 {
                error make {msg: $"Expected 1 element, got ($result | length)"}
            }
            if not ("externals" in $result) {
                error make {msg: $"Expected 'externals' in result, got: ($result)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: 'deps,externals' returns both" {
            let result = (parse-pull-modes "deps,externals")
            if ($result | length) != 2 {
                error make {msg: $"Expected 2 elements, got ($result | length)"}
            }
            if not ("deps" in $result) {
                error make {msg: $"Expected 'deps' in result"}
            }
            if not ("externals" in $result) {
                error make {msg: $"Expected 'externals' in result"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: 'deps,deps,externals' deduplicates" {
            let result = (parse-pull-modes "deps,deps,externals")
            if ($result | length) != 2 {
                error make {msg: $"Expected 2 unique elements, got ($result | length)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: handles whitespace" {
            let result = (parse-pull-modes " deps , externals ")
            if ($result | length) != 2 {
                error make {msg: $"Expected 2 elements after trimming, got ($result | length)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: invalid mode causes error" {
            let result = (try {
                parse-pull-modes "invalid"
                false
            } catch {|err|
                if not ($err.msg | str contains "Invalid pull mode") {
                    error make {msg: $"Expected 'Invalid pull mode' in error, got: ($err.msg)"}
                }
                true
            })
            $result
        } $verbose),
        (run-test "parse-pull-modes: whitespace-only returns empty list" {
            let result = (parse-pull-modes "  ")
            if not ($result | is-empty) {
                error make {msg: $"Expected empty list for whitespace input, got: ($result)"}
            }
            true
        } $verbose),
        (run-test "parse-pull-modes: comma-only input causes error" {
            let result = (try {
                parse-pull-modes ","
                false
            } catch {|err|
                if not ($err.msg | str contains "Missing value") {
                    error make {msg: $"Expected 'Missing value' in error, got: ($err.msg)"}
                }
                true
            })
            $result
        } $verbose),
    ]
}
