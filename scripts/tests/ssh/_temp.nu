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

# Hermetic temp context setup/cleanup for ssh suite tests.

export def make-temp-context [] {
    ^mktemp -d | str trim
}

export def rm-temp-context [dir: string] {
    try { rm -rf $dir } catch { }
}

export def seed-fake-ssh-keys [ssh_dir: string] {
    '{"key_name":"dockypody","comment":"docky@pody","default_user":"root"}' | save -f ($ssh_dir | path join "ssh.json")
    let fake_key = ($ssh_dir | path join "dockypody")
    let fake_pub = ($ssh_dir | path join "dockypody.pub")
    "FAKE PRIVATE KEY" | save -f $fake_key
    "FAKE PUBLIC KEY" | save -f $fake_pub
}

export def seed-fake-sshd-module [repo: string] {
    let sshd_mod_dir = ($repo | path join "scripts" "lib" "ssh")
    mkdir $sshd_mod_dir
    "# fake sshd module" | save -f ($sshd_mod_dir | path join "sshd.nu")
}
