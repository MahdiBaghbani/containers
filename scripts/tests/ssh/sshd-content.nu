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

# sshd.nu internal-sftp subsystem drift check.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]

export def sshd-content-tests [verbose: bool] {
    [
        (run-test "sshd.nu: uses internal-sftp subsystem" {
            let repo_root = (get-repo-root)
            let sshd_path = ($repo_root | path join "scripts" "lib" "ssh" "sshd.nu")
            let content = (open --raw $sshd_path)
            if not ($content | str contains "Subsystem sftp internal-sftp") {
                error make {msg: "sshd.nu must contain 'Subsystem sftp internal-sftp'"}
            }
            true
        } $verbose)
    ]
}
