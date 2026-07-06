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

# Dockerfile SSH gate / chmod drift checks.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

export def dockerfile-drift-tests [verbose: bool] {
    let dockerfiles = [
        "services/opencloud/Dockerfile.alpine"
        "services/ocis/Dockerfile.alpine"
        "services/mitmproxy/Dockerfile"
        "services/nextcloud-base/Dockerfile"
        "services/revad-base/Dockerfile.development"
    ]

    [
        (run-test "Dockerfile drift: server-family uses correct SSH build-time gate" {
            let repo_root = (get-repo-root)
            let gate = 'if [ "$SSH_ENABLED" = "true" ] && { [ "$SSH_MODE" = "server" ] || [ "$SSH_MODE" = "client-and-server" ]; }; then'
            let missing = ($dockerfiles | filter {|rel|
                let path = ($repo_root | path join $rel)
                if not ($path | path exists) {
                    true
                } else {
                    let content = (open --raw $path)
                    not ($content | str contains $gate)
                }
            })
            if not ($missing | is-empty) {
                let list = ($missing | str join ", ")
                error make {msg: $"SSH gate pattern missing or wrong in: ($list)"}
            }
            true
        } $verbose)
        (run-test "Dockerfile drift: server-family has no 'chmod 600 /opt/dockypody/ssh/ssh.json'" {
            let repo_root = (get-repo-root)
            let forbidden = 'chmod 600 /opt/dockypody/ssh/ssh.json'
            let offenders = ($dockerfiles | filter {|rel|
                let path = ($repo_root | path join $rel)
                if not ($path | path exists) {
                    false
                } else {
                    let content = (open --raw $path)
                    $content | str contains $forbidden
                }
            })
            if not ($offenders | is-empty) {
                let list = ($offenders | str join ", ")
                error make {msg: $"Forbidden chmod found in: ($list)"}
            }
            true
        } $verbose)
    ]
}
