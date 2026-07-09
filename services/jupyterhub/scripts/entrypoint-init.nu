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

# JupyterHub's default ConfigurableHTTPProxy spawns `configurable-http-proxy`
# locally. Assert the binary is present so a wrong base image (for example the
# proxy-less k8s-hub) fails immediately with a clear message instead of crashing
# mid-startup after TLS and OAuth preflight already passed.
def preflight-proxy [] {
    let found = (which configurable-http-proxy)
    if ($found | is-empty) {
        error make {
            msg: "ERROR: configurable-http-proxy not found on PATH. The JupyterHub image must bundle the local proxy (use the all-in-one quay.io/jupyterhub/jupyterhub base, not k8s-hub)."
        }
    }
    print $"Proxy preflight OK: configurable-http-proxy at ($found | first | get path)"
}

def preflight-tls [tls_dir: string = $RUNTIME_TLS_DIR] {
    let resolved = (validate-jupyterhub-tls-contract $tls_dir)
    print $"TLS preflight OK: cert=($resolved.cert) key=($resolved.key)"
}

# JupyterHub's OCM service verifies inbound share/token signatures by fetching
# the peer's JWKS over https via Python (PyJWKClient), which trusts peers using
# OpenSSL's default store. Some base images ship a broken default cert layout
# (no /usr/lib/ssl/cert.pem cafile symlink), so the workspace CA baked into
# /etc/ssl/certs/ca-certificates.crt is never loaded and every peer TLS verify
# fails with a silent 500 on /services/ocm/shares. Assert Python's default
# context loads a non-empty CA store so that regression fails fast here.
def preflight-ca [] {
    let code = "import ssl, sys; sys.stdout.write(str(ssl.create_default_context().cert_store_stats()['x509_ca']))"
    let result = (^python3 -c $code | complete)
    let count = ($result.stdout | str trim)
    if $result.exit_code != 0 or $count == "0" or ($count | is-empty) {
        error make {
            msg: $"ERROR: Python TLS trust store check failed \(loaded '($count)' CA certs; expected > 0\). The image CA layout is broken: OpenSSL/Python cannot read /etc/ssl/certs/ca-certificates.crt. Ensure SSL_CERT_FILE points at the CA bundle so the OCM service can verify peer JWKS over TLS. python stderr: ($result.stderr | str trim)"
        }
    }
    print $"CA preflight OK: Python default trust store loaded ($count) CAs"
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
    preflight-proxy
    preflight-tls $RUNTIME_TLS_DIR
    preflight-ca
    preflight-oauth
}
