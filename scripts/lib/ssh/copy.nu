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

# SSH copy helper - thin wrapper around prepare-ssh-context in build/context.nu.
# Staging is mode-gated: server gets public key only; client/client-and-server
# get the full keypair. Private key is never staged for server mode.

use ../build/context.nu [prepare-ssh-context]

export def copy-ssh-material [
    service: string,
    context: string,
    ssh_enabled: bool,
    ssh_mode: string
] {
    prepare-ssh-context $service $context $ssh_enabled $ssh_mode
}
