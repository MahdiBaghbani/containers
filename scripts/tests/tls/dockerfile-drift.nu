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

# Runtime-owner and stale inline /tls chown drift checks.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]
use ./_temp.nu [find-stale-inline-tls-chown]

export def dockerfile-drift-tests [verbose: bool] {
    [
        (run-test "Dockerfile drift: copy-tls services use expected --runtime-owner and no inline /tls chown" {
            let repo_root = (get-repo-root)
            let dockerfile_contracts = [
                {path: "services/idp/Dockerfile", runtime_owner: "--runtime-owner \"'1000:1000'\""}
                {path: "services/jupyterhub/Dockerfile", runtime_owner: "--runtime-owner \"'1000:1000'\""}
                {path: "services/ocis/Dockerfile.alpine", runtime_owner: "--runtime-owner \"'1000:1000'\""}
                {path: "services/opencloud/Dockerfile.alpine", runtime_owner: "--runtime-owner \"'1000:1000'\""}
                {path: "services/cernbox-web/Dockerfile", runtime_owner: "--runtime-owner \"'nginx:nginx'\""}
            ]
            for contract in $dockerfile_contracts {
                let df = $contract.path
                let path = ($repo_root | path join $df)
                if not ($path | path exists) {
                    error make {msg: $"Dockerfile not found: ($path)"}
                }
                let content = (open --raw $path | decode utf-8)
                if not ($content | str contains $contract.runtime_owner) {
                    error make {msg: $"($df): expected exact ($contract.runtime_owner) in copy-tls invocation"}
                }
                let stale = (find-stale-inline-tls-chown $content)
                if not ($stale | is-empty) {
                    error make {msg: $"($df): stale inline chown targeting /tls must be removed: ($stale | first | str trim)"}
                }
            }
            true
        } $verbose)
    ]
}
