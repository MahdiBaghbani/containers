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

# JupyterHub entrypoint preflight: validate TLS contract before CMD runs.

use ./lib/tls.nu [validate-jupyterhub-tls-contract]

const RUNTIME_TLS_DIR = "/tls"

def preflight-tls [tls_dir: string = $RUNTIME_TLS_DIR] {
    let resolved = (validate-jupyterhub-tls-contract $tls_dir)
    print $"TLS preflight OK: cert=($resolved.cert) key=($resolved.key)"
}

def --wrapped main [...args] {
    preflight-tls $RUNTIME_TLS_DIR
}
