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

# Docker Sentinel Normalization Tests (Tests 31-32).

use ../../lib/build/docker.nu [normalize-docker-label]
use ../lib.nu [run-test]

export def docker-sentinel-tests [verbose: bool] {
    [
        (run-test "Test 31: Docker sentinel <no value> normalizes to empty string" {
            let sentinel = ("<no value>" | normalize-docker-label)
            if ($sentinel | str length) != 0 {
              error make {msg: $"Expected empty string for sentinel, got: '($sentinel)'"}
            }

            let normal_label = ("abc12345deadbeef" | normalize-docker-label)
            if $normal_label != "abc12345deadbeef" {
              error make {msg: $"Normal label should pass through unchanged, got: '($normal_label)'"}
            }

            let padded_sentinel = ("  <no value>  " | normalize-docker-label)
            if ($padded_sentinel | str length) != 0 {
              error make {msg: $"Whitespace-padded sentinel should normalize to empty, got: '($padded_sentinel)'"}
            }

            let empty_label = ("" | normalize-docker-label)
            if ($empty_label | str length) != 0 {
              error make {msg: $"Empty string should pass through as empty, got: '($empty_label)'"}
            }

            if $verbose {
              print "    Sentinel '<no value>' -> ''"
              print "    Normal label passes through unchanged"
            }

            true
          } $verbose)

        (run-test "Test 32: Hash shortening is safe for odd strings including sentinel" {
            # Inline the same logic used by the private short-hash helper in version.nu
            let shorten = {|s: string|
              if ($s | str length) <= 8 { $s } else { $s | str substring 0..7 }
            }

            let cases = [
              {input: "<no value>", expected_max: 8},
              {input: "", expected_max: 8},
              {input: "abc", expected_max: 8},
              {input: "abcdefgh", expected_max: 8},
              {input: "abcdefghi", expected_max: 8},
              {input: "abc123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd", expected_max: 8},
            ]

            for case in $cases {
              let result = (do $shorten $case.input)
              if ($result | str length) > $case.expected_max {
                error make {msg: $"Shortening produced ($result | str length) chars for '($case.input)', max is ($case.expected_max)"}
              }
            }

            # Confirm sentinel "<no value>" (10 chars) shortens without crashing
            let sentinel_short = (do $shorten "<no value>")
            if ($sentinel_short | str length) > 8 {
              error make {msg: $"Sentinel short result too long: '($sentinel_short)'"}
            }

            if $verbose {
              let sentinel_short = (do $shorten "<no value>")
              print $"    '<no value>' shortens to: '($sentinel_short)'"
            }

            true
          } $verbose)
    ]
}
