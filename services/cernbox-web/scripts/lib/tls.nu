#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Runtime TLS resolution for cernbox-web (backend and frontend probes).

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

# Backend chain: REVAD_TLS_ENABLED -> TLS_ENABLED -> "true".
export def resolve-revad-tls-enabled [] {
    let revad = (env-nonempty-value "REVAD_TLS_ENABLED")
    if $revad != null {
        return $revad
    }
    let tls = (env-nonempty-value "TLS_ENABLED")
    if $tls != null {
        return $tls
    }
    "true"
}

# Frontend chain: WEB_TLS_ENABLED -> backend chain from resolve-revad-tls-enabled.
export def resolve-web-tls-enabled [] {
    let web = (env-nonempty-value "WEB_TLS_ENABLED")
    if $web != null {
        return $web
    }
    resolve-revad-tls-enabled
}
