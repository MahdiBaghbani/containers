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

# Docker integration test suite (opt-in only)
#
# This suite exercises basic Docker reachability: CLI availability and daemon
# connectivity. Full end-to-end build and push tests are not yet implemented.
#
# It is intentionally excluded from 'test --suite all'.
#
# Opt-in options (either works):
#   1. Set env var: DOCKYPODY_DOCKER_INTEGRATION=1
#      Then: nu scripts/dockypody.nu test --suite docker-integration
#   2. Pass --docker flag directly:
#      nu scripts/tests/docker-integration.nu --docker
#
# Without either opt-in the suite prints a skip notice and exits 0, so it is
# safe to invoke in any context and will never fail due to a missing daemon.

use ./lib.nu [run-test print-test-summary]

def main [--verbose, --docker] {
    let docker_flag = (try { $docker } catch { false })
    let env_opt_in = (($env.DOCKYPODY_DOCKER_INTEGRATION? | default "") == "1")
    let enabled = ($docker_flag or $env_opt_in)

    if not $enabled {
        print "Docker integration suite: SKIPPED"
        print "  This suite checks Docker CLI availability and daemon reachability."
        print "  It is excluded from 'test --suite all' by design."
        print "  To run: set env DOCKYPODY_DOCKER_INTEGRATION=1 or pass --docker directly."
        exit 0
    }

    let verbose_flag = (try { $verbose } catch { false })
    mut results = []

    # Smoke test 1: Docker CLI is available
    let t1 = (run-test "Docker CLI reachable" {
        let result = (try {
            ^docker --version | complete
        } catch {
            {exit_code: 127, stdout: "", stderr: "docker not found"}
        })
        if $result.exit_code != 0 {
            error make {msg: $"docker --version failed \(exit=($result.exit_code)\): ($result.stderr)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t1)

    # Smoke test 2: Docker daemon is reachable
    let t2 = (run-test "Docker daemon reachable" {
        let result = (try {
            ^docker info | complete
        } catch {
            {exit_code: 127, stdout: "", stderr: "docker not found"}
        })
        if $result.exit_code != 0 {
            error make {msg: $"docker info failed \(exit=($result.exit_code)\): ($result.stderr | str substring 0..200)"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t2)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
