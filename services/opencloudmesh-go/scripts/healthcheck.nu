#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Baked development-image healthcheck: probe HTTPS listen_addr (:443).

# Map a curl-style probe record to a healthcheck exit code.
# Returns 0 on success; otherwise prints a concise failure and returns 1.
export def decide-health [probe: record]: any -> int {
    if $probe.exit_code == 0 {
        return 0
    }
    let detail = if ($probe.stderr | str trim | is-empty) {
        $probe.stdout | str trim
    } else {
        $probe.stderr | str trim
    }
    print $"healthcheck: HTTPS :443 probe failed: ($detail)"
    1
}

def main [] {
    # config.toml sets listen_addr = ":443" with static TLS; curl is in the image.
    let probe = (^curl -skf https://127.0.0.1:443/ | complete)
    exit (decide-health $probe)
}
