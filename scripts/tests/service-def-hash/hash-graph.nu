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

# Service definition hash graph (Tests 7-8).

use ../../lib/build/hash.nu [collect-dep-hashes]
use ../lib.nu [run-test]

export def hash-graph-tests [verbose: bool] {
    [
        (run-test "Test 7: Hash graph - hard failure on in-order missing dependency hash" {
            let build_order = ["dep-service:v1.0.0", "test-service:v1.0.0"]
            let dep_node_keys = ["dep-service:v1.0.0"]
            let computed_hashes = {}

            let errored = (try {
              collect-dep-hashes "test-service:v1.0.0" $dep_node_keys $computed_hashes $build_order
              false
            } catch {|err|
              if not ($err.msg | str contains "invariant violated") {
                error make { msg: $"Expected invariant violation error, got: ($err.msg)" }
              }
              true
            })

            if not $errored {
              error make { msg: "Expected collect-dep-hashes to hard-fail on an in-order missing dependency hash" }
            }

            if $verbose {
              print "    in-order missing dependency hash correctly hard-failed"
            }

            true
          } $verbose)
        ,
        (run-test "Test 8: Hash graph - out-of-scope dependency warned and omitted" {
            let build_order = ["test-service:v1.0.0"]
            let dep_node_keys = ["dep-out:v1.0.0"]
            let computed_hashes = {}

            let result = (collect-dep-hashes "test-service:v1.0.0" $dep_node_keys $computed_hashes $build_order)
            if not ($result | is-empty) {
              error make { msg: $"Out-of-scope dependency should be omitted, got: ($result | to nuon)" }
            }

            let build_order2 = ["dep-in:v1.0.0", "test-service:v1.0.0"]
            let dep_node_keys2 = ["dep-in:v1.0.0"]
            let computed_hashes2 = {"dep-in:v1.0.0": "abc123"}
            let result2 = (collect-dep-hashes "test-service:v1.0.0" $dep_node_keys2 $computed_hashes2 $build_order2)
            if ($result2 | get "dep-in:v1.0.0") != "abc123" {
              error make { msg: $"Expected in-scope dependency hash to be collected, got: ($result2 | to nuon)" }
            }

            if $verbose {
              print "    out-of-scope dependency omitted; in-scope dependency collected"
            }

            true
          } $verbose)
    ]
}
