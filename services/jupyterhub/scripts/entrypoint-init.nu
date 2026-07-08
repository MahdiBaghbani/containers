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

# JupyterHub entrypoint preflight: validate TLS contract and wait for the OAuth
# handoff file before CMD runs.

use ./lib/tls.nu [validate-jupyterhub-tls-contract]
use ./lib/oauth.nu [oauth-env-creds-present oauth-handoff-file wait-for-oauth-handoff]

const RUNTIME_TLS_DIR = "/tls"
# Bounded wait for the sender NC to provision and publish the OAuth client.
# Operator/test tunable via JUPYTERHUB_OAUTH_WAIT_TIMEOUT_SEC.
const OAUTH_WAIT_TIMEOUT_DEFAULT_SEC = 300

def oauth-wait-timeout-sec [] {
    let raw = (try { $env.JUPYTERHUB_OAUTH_WAIT_TIMEOUT_SEC } catch { "" } | str trim)
    if ($raw | is-empty) {
        return $OAUTH_WAIT_TIMEOUT_DEFAULT_SEC
    }
    let parsed = (try { $raw | into int } catch { null })
    if $parsed == null or $parsed < 0 {
        return $OAUTH_WAIT_TIMEOUT_DEFAULT_SEC
    }
    $parsed
}

def preflight-tls [tls_dir: string = $RUNTIME_TLS_DIR] {
    let resolved = (validate-jupyterhub-tls-contract $tls_dir)
    print $"TLS preflight OK: cert=($resolved.cert) key=($resolved.key)"
}

def preflight-oauth [] {
    if (oauth-env-creds-present) {
        print "OAuth client present in env; skipping handoff wait"
        return
    }
    let oauth_file = (oauth-handoff-file)
    if $oauth_file == null {
        # No handoff configured; jupyterhub_config.py fails clearly if unresolved.
        print "No OAuth handoff configured; skipping handoff wait"
        return
    }
    let timeout = (oauth-wait-timeout-sec)
    print $"Waiting up to ($timeout)s for OAuth handoff at ($oauth_file) ..."
    if not (wait-for-oauth-handoff $oauth_file $timeout) {
        error make {
            msg: $"ERROR: OAuth handoff file not ready at ($oauth_file) after ($timeout)s"
        }
    }
    print "OAuth handoff ready"
}

def --wrapped main [...args] {
    preflight-tls $RUNTIME_TLS_DIR
    preflight-oauth
}
