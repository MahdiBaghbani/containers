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

# Makefile -n forwarding smoke tests.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

export def test-smoke-make-certs-filter [verbose: bool] {
    run-test "smoke: make -n certs forwards FILTER to tls certs --filter" {
        let make_ok = ((try { ^which make | complete | get exit_code } catch { 1 }) == 0)
        if not $make_ok {
            if $verbose { print "    make not available; skipping passthrough assertion" }
            true
        } else {
            let root = (get-repo-root)
            let out = (^make -n -C $root certs FILTER=alpha,beta | complete)
            if $out.exit_code != 0 {
                error make {msg: $"make -n certs exited ($out.exit_code): ($out.stderr)"}
            }
            if not ($out.stdout | str contains 'tls certs --filter "alpha,beta"') {
                error make {msg: $"make -n did not forward FILTER as --filter; got: ($out.stdout)"}
            }
            true
        }
    } $verbose
}
