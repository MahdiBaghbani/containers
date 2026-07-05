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

# Local-plane validate topology and guard ordering cases.

use ../../lib/plane/presence.nu [local-root-path local-services-path]
use ../../lib/plane/audit.nu [LOCAL_MIRROR_FILE]
use ../lib.nu [run-test]
use ./_fixtures.nu [
    make-temp-repo rm-temp-repo run-dockypody-in-repo
    seed-tracked-service seed-service-with-git-source
]
use ./assertions.nu [assert-routed-failure-names-contract]

export def test-smoke-local-bad-topology [verbose: bool] {
    run-test "smoke: routed validate --plane local bad topology names unknown mirror contract" {
        let repo = (make-temp-repo)
        seed-tracked-service $repo
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo)
        mkdir (local-services-path $repo | path join "shadow-svc")
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Unknown local service mirror" []
    } $verbose
}

export def test-smoke-local-validate-additive-version-source [verbose: bool] {
    run-test "smoke: routed validate --plane local rejects additive id in fragment versions" {
        let repo = (make-temp-repo)
        seed-service-with-git-source $repo
        "FROM scratch" | save -f ($repo | path join "services/test-svc/Dockerfile")
        {
            name: "test-svc"
            context: "services/test-svc"
            dockerfile: "services/test-svc/Dockerfile"
        } | save -f ($repo | path join "services/test-svc.nuon")
        mkdir (local-root-path $repo)
        let mirror = (local-services-path $repo | path join "test-svc")
        mkdir $mirror
        mkdir ($repo | path join "local-src")
        {
            versions: [
                {
                    name: "v1"
                    overrides: {
                        sources: {
                            extra_src: { path: "local-src" }
                        }
                    }
                }
            ]
        } | save -f ($mirror | path join $LOCAL_MIRROR_FILE)
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Additive source id" []
    } $verbose
}

export def test-smoke-local-guard-ordering [verbose: bool] {
    run-test "smoke: routed validate guard ordering manifest read before mirror audit" {
        let repo = (make-temp-repo)
        "not valid nuon {" | save -f ($repo | path join "services/test-svc.nuon")
        mkdir (local-root-path $repo)
        mkdir (local-services-path $repo)
        mkdir (local-services-path $repo | path join "test-svc")
        let result = (run-dockypody-in-repo $repo [validate --plane local --service test-svc])
        rm-temp-repo $repo
        assert-routed-failure-names-contract $result "Unable to read tracked service manifest" [
            "Unknown local service mirror"
        ]
    } $verbose
}
