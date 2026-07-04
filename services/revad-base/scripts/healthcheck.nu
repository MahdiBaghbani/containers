#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# Baked development-image healthcheck: probe the gRPC listen port for REVAD_CONTAINER_MODE.

use ./lib/utils.nu [get_env_or_default]
use ./lib/ports.nu [resolve-grpc-port-for-mode]

# ss prints a header even when no sockets match; require a LISTEN data row.
def ss-has-listener [stdout: string] {
    $stdout
    | lines
    | any {|line|
        let trimmed = ($line | str trim)
        ($trimmed | str length) > 0 and ($trimmed | str starts-with "LISTEN")
    }
}

def main [] {
    let mode = (get_env_or_default "REVAD_CONTAINER_MODE" "")
    if ($mode | str length) == 0 {
        print "healthcheck: REVAD_CONTAINER_MODE is required"
        exit 1
    }

    let port = (try {
        resolve-grpc-port-for-mode $mode
    } catch {|e|
        print $"healthcheck: ($e.msg)"
        exit 1
    })

    let probe = (^ss -ltn $"sport = :($port)" | complete)
    if $probe.exit_code != 0 {
        print $"healthcheck: ss probe failed for port ($port): ($probe.stderr | str trim)"
        exit 1
    }
    if not (ss-has-listener $probe.stdout) {
        print $"healthcheck: no listener on gRPC port ($port)"
        exit 1
    }
    exit 0
}
