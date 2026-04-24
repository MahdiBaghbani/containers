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

# Read ssh.json SSOT from ssh_dir; returns null if file is missing.
export def read-ssh-metadata [
    ssh_dir: string = "ssh"
] {
    let meta_file = $"($ssh_dir)/ssh.json"
    if not ($meta_file | path exists) {
        return null
    }
    try {
        open $meta_file
    } catch {
        null
    }
}

# Write ssh.json SSOT to ssh_dir.
export def write-ssh-metadata [
    meta: record,
    ssh_dir: string = "ssh"
] {
    mkdir $ssh_dir
    let meta_file = $"($ssh_dir)/ssh.json"
    $meta | to json | save -f $meta_file
    print $"Wrote ssh.json to ($meta_file)"
}

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

# Generate (or recover) the SSH keypair described by ssh.json.
#
# State machine:
#   no json + keypair present -> scan for .pub, derive metadata, write ssh.json; skip keygen
#   json present + keypair present -> skip (print paths); unless --force
#   keypair missing -> generate using json values; write json if absent
#
# Returns {private_key: string, public_key: string}.
export def generate-ssh-keypair [
    ssh_dir: string = "ssh",
    --force  # Overwrite existing keypair
] {
    mut meta = (read-ssh-metadata $ssh_dir)

    if $meta == null {
        # No ssh.json - scan for an existing keypair.
        let pub_files = (try { glob $"($ssh_dir)/*.pub" } catch { [] })
        if ($pub_files | length) > 0 {
            let pub_path = ($pub_files | first)
            let stem = ($pub_path | path basename | str replace ".pub" "")
            let comment = (try {
                let content = (open --raw $pub_path | str trim)
                let parts = ($content | split row " ")
                if ($parts | length) >= 3 { $parts | last } else { "docky@pody" }
            } catch { "docky@pody" })
            let derived = {key_name: $stem, comment: $comment, default_user: "root"}
            write-ssh-metadata $derived $ssh_dir
            let priv = $"($ssh_dir)/($stem)"
            print "Existing keypair found; created ssh.json from filename and public key"
            print $"  Private key: ($priv)"
            print $"  Public key:  ($pub_path)"
            return {private_key: $priv, public_key: $pub_path}
        }
        # No keypair found either - bootstrap with defaults.
        $meta = {key_name: "dockypody", comment: "docky@pody", default_user: "root"}
        write-ssh-metadata $meta $ssh_dir
    }

    let key_name = ($meta.key_name? | default "dockypody")
    let comment  = ($meta.comment?  | default "docky@pody")

    let private_key = $"($ssh_dir)/($key_name)"
    let public_key  = $"($ssh_dir)/($key_name).pub"

    if ($private_key | path exists) and not $force {
        print $"SSH keypair already exists at ($private_key) - skipping generation"
        print $"  Private key: ($private_key)"
        print $"  Public key:  ($public_key)"
        return {private_key: $private_key, public_key: $public_key}
    }

    if ($private_key | path exists) and $force {
        rm -f $private_key
        try { rm -f $public_key } catch { }
        print "Removed existing keypair for --force regeneration"
    }

    mkdir $ssh_dir

    let r = (^ssh-keygen -t ed25519 -f $private_key -N "" -C $comment | complete)
    if $r.exit_code != 0 {
        error make {msg: $"ssh-keygen failed exit=($r.exit_code): ($r.stderr | str trim)"}
    }

    print "Generated SSH keypair:"
    print $"  Private key: ($private_key)"
    print $"  Public key:  ($public_key)"
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
