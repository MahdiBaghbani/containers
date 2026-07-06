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

# Local-plane build smoke and guard cases.

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    make-temp-repo rm-temp-repo run-dockypody-in-repo
    seed-tracked-service seed-service-with-git-source
]
use ./assertions.nu [assert-routed-failure-names-contract]

export def test-smoke-local-missing-root [verbose: bool] {
    run-test "smoke: routed build --plane local missing root names presence contract" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        let result = (run-dockypody-in-repo $repo [build --plane local --show-build-order --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "requires local root directory" [
            "Unsupported local root"
            "Unknown local service mirror"
            "Incomplete local service mirror"
        ]
    } $verbose
}

export def test-smoke-local-empty-topology [verbose: bool] {
    run-test "smoke: routed build --plane local passes guard on empty legal topology" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let result = (run-dockypody-in-repo $repo [build --plane local --show-build-order --service test-svc])
        rm-temp-repo $repo
        if $result.exit_code != 0 {
            error make {msg: $"Expected guard pass on empty legal topology, exit ($result.exit_code): ($result.stderr)"}
        }
        let combined = ($result.stdout + $result.stderr)
        if ($combined | str contains "requires local root directory") {
            error make {msg: "Empty legal topology must not fail root presence guard"}
        }
        if ($combined | str contains "Unsupported local root") {
            error make {msg: "Empty legal topology must not fail topology audit"}
        }
        true
    } $verbose
}

export def test-smoke-tracked-miss-local-only-build [verbose: bool] {
    run-test "smoke: routed build tracked plane miss for local-only version names guidance" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        {
            versions: [{ name: "devlocal" }]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let result = (run-dockypody-in-repo $repo [
            build --show-build-order --service test-svc --version devlocal
        ])
        rm-temp-repo $repo
        if $result.exit_code == 0 {
            error make {msg: "Expected tracked-plane build miss for local-only version"}
        }
        let combined = ($result.stdout + $result.stderr)
        if not ($combined | str contains "--plane local") {
            error make {msg: $"Expected --plane local guidance, got: ($combined)"}
        }
        if not ($combined | str contains "local fragment") {
            error make {msg: $"Expected local fragment mention, got: ($combined)"}
        }
        if not ($combined | str contains ".dockypody.local/services/test-svc/versions.nuon") {
            error make {msg: $"Expected local fragment path suffix in output, got: ($combined)"}
        }
        true
    } $verbose
}
