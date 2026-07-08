#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Service-local TLS path resolution and validation for JupyterHub.

# Env value when set and non-whitespace; otherwise null (treated as unset).
def env-nonempty-value [name: string] {
    try {
        let val = ($env | get $name)
        if ($val | str trim | is-empty) {
            null
        } else {
            $val
        }
    } catch {
        null
    }
}

export def tls-default-paths [cert_name: string, tls_dir: string] {
    {
        cert: ($tls_dir | path join $"($cert_name).crt")
        key: ($tls_dir | path join $"($cert_name).key")
    }
}

# Resolve cert/key paths from env without checking files on disk.
export def resolve-jupyterhub-tls-paths [tls_dir: string] {
    let cert_name = (env-nonempty-value "DOCKYPODY_TLS_CERT_NAME")
    let cert_override = (env-nonempty-value "JUPYTERHUB_SSL_CERT")
    let key_override = (env-nonempty-value "JUPYTERHUB_SSL_KEY")

    let defaults = if $cert_name != null {
        (tls-default-paths $cert_name $tls_dir)
    } else {
        {cert: null, key: null}
    }

    {
        cert_name: $cert_name
        cert: (if $cert_override != null { $cert_override } else { $defaults.cert })
        key: (if $key_override != null { $key_override } else { $defaults.key })
        cert_override: $cert_override
        key_override: $key_override
    }
}

export def validate-jupyterhub-tls-contract [tls_dir: string] {
    let paths = (resolve-jupyterhub-tls-paths $tls_dir)
    let cert_name = $paths.cert_name

    if $paths.cert_override == null {
        if $cert_name == null {
            error make {
                msg: "ERROR: TLS required but DOCKYPODY_TLS_CERT_NAME is unset and JUPYTERHUB_SSL_CERT is unset"
            }
        }
        let cert_path = $paths.cert
        if not ($cert_path | path exists) {
            error make {
                msg: $"ERROR: TLS enabled but certificate not found at ($cert_path)"
            }
        }
    } else if not ($paths.cert_override | path exists) {
        error make {
            msg: $"ERROR: JUPYTERHUB_SSL_CERT override not found at ($paths.cert_override)"
        }
    }

    if $paths.key_override == null {
        if $cert_name == null {
            error make {
                msg: "ERROR: TLS required but DOCKYPODY_TLS_CERT_NAME is unset and JUPYTERHUB_SSL_KEY is unset"
            }
        }
        let key_path = $paths.key
        if not ($key_path | path exists) {
            error make {
                msg: $"ERROR: TLS enabled but key not found at ($key_path)"
            }
        }
    } else if not ($paths.key_override | path exists) {
        error make {
            msg: $"ERROR: JUPYTERHUB_SSL_KEY override not found at ($paths.key_override)"
        }
    }

    {cert: $paths.cert, key: $paths.key}
}
