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

# SSH shared library functions

export def get-ssh-mode [
    cfg: record
] {
    try {
        let ssh = $cfg.ssh
        if $ssh.enabled {
            $ssh.mode
        } else {
            "disabled"
        }
    } catch {
        "disabled"
    }
}

export def is-ssh-enabled [
    cfg: record
] {
    try {
        $cfg.ssh.enabled | default false
    } catch {
        false
    }
}

export def generate-ssh-keypair [
    output_dir: string = "ssh",
    key_name: string = "dockypody-dev-ed25519"
] {
    let private_key = $"($output_dir)/($key_name)"
    let public_key = $"($output_dir)/($key_name).pub"

    if ($private_key | path exists) {
        print $"SSH keypair already exists at ($private_key)"
        return {private_key: $private_key, public_key: $public_key}
    }

    mkdir $output_dir

    # Generate Ed25519 keypair
    ^ssh-keygen -t ed25519 -f $private_key -N "" -C "dockypody-dev@local"

    print $"Generated SSH keypair at ($private_key)"
    {private_key: $private_key, public_key: $public_key}
}

export def read-ssh-config [
    cfg: record
] {
    try {
        $cfg.ssh
    } catch {
        {enabled: false, mode: "disabled"}
    }
}
