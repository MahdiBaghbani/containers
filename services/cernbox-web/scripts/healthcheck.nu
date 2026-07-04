#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Baked image healthcheck: probe nginx on 127.0.0.1 using effective WEB TLS.

use ./lib/tls.nu [resolve-web-tls-enabled]

def main [] {
    let web_tls = (resolve-web-tls-enabled)
    let probe = if $web_tls == "false" {
        ^curl -sf http://127.0.0.1/ | complete
    } else {
        ^curl -skf https://127.0.0.1/ | complete
    }
    if $probe.exit_code != 0 {
        let detail = if ($probe.stderr | str trim | is-empty) {
            $probe.stdout | str trim
        } else {
            $probe.stderr | str trim
        }
        print $"healthcheck: curl probe failed: ($detail)"
        exit 1
    }
    exit 0
}
