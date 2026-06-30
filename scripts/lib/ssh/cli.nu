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

# SSH CLI facade - mirrors tls/cli.nu structure

use ./lib.nu [generate-ssh-keypair]

# Show SSH CLI help
export def ssh-help [] {
    print "Usage: nu scripts/dockypody.nu ssh <subcommand> [options]"
    print ""
    print "Subcommands:"
    print "  key   Generate default SSH keypair (reads key_name/comment from ssh/ssh.json)"
    print ""
    print "Options:"
    print "  --force   Overwrite existing keypair"
}

# SSH CLI entrypoint - called from dockypody.nu
export def ssh-cli [
    subcommand: string,  # Subcommand: key, help
    flags: record        # Flags: { force }
] {
    let force = (try { $flags.force } catch { false })

    match $subcommand {
        "help" => {
            ssh-help
        }
        "key" => {
            if $force {
                generate-ssh-keypair --force
            } else {
                generate-ssh-keypair
            }
        }
        _ => {
            print $"Unknown ssh subcommand: ($subcommand)"
            print ""
            ssh-help
            exit 1
        }
    }
}
