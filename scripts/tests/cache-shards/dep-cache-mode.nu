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

# parse-dep-cache-mode empty local/CI defaults, passthrough, and invalid mode.

use ../../lib/build/cache.nu [parse-dep-cache-mode]
use ../lib.nu [run-test]

export def dep-cache-mode-tests [verbose: bool] {
    [
        (run-test "parse-dep-cache-mode: empty local -> off" {
            (parse-dep-cache-mode "" true) == "off"
        } $verbose)
        (run-test "parse-dep-cache-mode: empty CI -> soft" {
            (parse-dep-cache-mode "" false) == "soft"
        } $verbose)
        (run-test "parse-dep-cache-mode: explicit mode passthrough" {
            let modes = ["off" "soft" "strict"]
            $modes | all {|m| (parse-dep-cache-mode $m true) == $m}
        } $verbose)
        (run-test "parse-dep-cache-mode: invalid mode -> error" {
            let errored = (try {
                parse-dep-cache-mode "bogus-mode" true
                false
            } catch { true })
            $errored
        } $verbose)
    ]
}
