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

# prepare-ssh-context / cleanup-ssh-context staging behavior.

use ../../lib/build/context.nu [prepare-ssh-context cleanup-ssh-context]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp-context rm-temp-context seed-fake-ssh-keys seed-fake-sshd-module]

export def prepare-context-tests [verbose: bool] {
    [
        (run-test "prepare-ssh-context: disabled -> dir created, no files" {
            let ctx = (make-temp-context)
            let result = (prepare-ssh-context "test-service" $ctx false "disabled")
            if not $result.dir_created {
                rm-temp-context $ctx
                error make {msg: "Expected dir_created=true for disabled SSH (directory always created)"}
            }
            if $result.copied {
                rm-temp-context $ctx
                error make {msg: "Expected copied=false for disabled SSH"}
            }
            if not ($result.files | is-empty) {
                rm-temp-context $ctx
                error make {msg: "Expected empty files list for disabled SSH"}
            }
            let ssh_dir = ($ctx | path join "ssh")
            if not ($ssh_dir | path exists) {
                rm-temp-context $ctx
                error make {msg: "Expected ssh dir to exist even when SSH disabled"}
            }
            rm-temp-context $ctx
            true
        } $verbose)
        (run-test "prepare-ssh-context: server mode -> public key staged, private key NOT staged" {
            let fake_repo = (make-temp-context)
            let fake_ssh_dir = ($fake_repo | path join "ssh")
            mkdir $fake_ssh_dir
            seed-fake-ssh-keys $fake_ssh_dir
            seed-fake-sshd-module $fake_repo

            let ctx = ($fake_repo | path join "ctx")
            mkdir $ctx

            let result = (do {
                cd $fake_repo
                prepare-ssh-context "test-service" $ctx true "server"
            })

            if not $result.dir_created {
                rm-temp-context $fake_repo
                error make {msg: "Expected dir_created=true when SSH enabled"}
            }

            let ssh_dir = ($ctx | path join "ssh")
            if not ($ssh_dir | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected ssh dir to be created in build context"}
            }

            let staged_key = ($ctx | path join "ssh" "dockypody")
            let staged_pub = ($ctx | path join "ssh" "dockypody.pub")

            if ($staged_key | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Private key must NOT be staged in server mode"}
            }
            if not ($staged_pub | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected public key staged in server mode"}
            }

            let staged_module = ($ctx | path join "scripts" "lib" "sshd.nu")
            if not ($staged_module | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected sshd shared module staged in server mode"}
            }

            do {
                cd $fake_repo
                cleanup-ssh-context $ctx $result
            }

            if ($staged_pub | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected public key removed after cleanup"}
            }
            if ($staged_module | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected sshd shared module removed after cleanup"}
            }

            rm-temp-context $fake_repo
            true
        } $verbose)
        (run-test "prepare-ssh-context: client mode -> full keypair staged" {
            let fake_repo = (make-temp-context)
            let fake_ssh_dir = ($fake_repo | path join "ssh")
            mkdir $fake_ssh_dir
            seed-fake-ssh-keys $fake_ssh_dir
            seed-fake-sshd-module $fake_repo

            let ctx = ($fake_repo | path join "ctx")
            mkdir $ctx

            let result = (do {
                cd $fake_repo
                prepare-ssh-context "test-service" $ctx true "client"
            })

            if not $result.dir_created {
                rm-temp-context $fake_repo
                error make {msg: "Expected dir_created=true when SSH enabled"}
            }

            let staged_key = ($ctx | path join "ssh" "dockypody")
            let staged_pub = ($ctx | path join "ssh" "dockypody.pub")

            if not ($staged_key | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected private key staged in client mode"}
            }
            if not ($staged_pub | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected public key staged in client mode"}
            }

            do {
                cd $fake_repo
                cleanup-ssh-context $ctx $result
            }

            if ($staged_key | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected private key removed after cleanup"}
            }

            rm-temp-context $fake_repo
            true
        } $verbose)
        (run-test "prepare-ssh-context: sshd shared module always staged even when disabled" {
            let fake_repo = (make-temp-context)
            seed-fake-sshd-module $fake_repo

            let ctx = ($fake_repo | path join "ctx")
            mkdir $ctx

            let result = (do {
                cd $fake_repo
                prepare-ssh-context "test-service" $ctx false "disabled"
            })

            let staged_module = ($ctx | path join "scripts" "lib" "sshd.nu")
            if not ($staged_module | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected sshd shared module staged even when SSH disabled"}
            }

            do {
                cd $fake_repo
                cleanup-ssh-context $ctx $result
            }

            if ($staged_module | path exists) {
                rm-temp-context $fake_repo
                error make {msg: "Expected sshd shared module removed after cleanup"}
            }

            rm-temp-context $fake_repo
            true
        } $verbose)
    ]
}
