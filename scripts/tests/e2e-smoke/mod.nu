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

# Public e2e smoke suite (daemon auto-run)
#
# Included in `test --suite all`. A bounded daemon probe decides the path:
# - no daemon: print SKIPPED: and exit 0
# - daemon available: build common-tools (debian + rhel), gaia, idp; run
#   `gaia help`; start idp detached; poll /health/ready; stop with -t 10
#   under 12s; cleanup

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test print-test-summary]

const IDP_CONTAINER = "dockypody-e2e-smoke-idp"
const IDP_HOST_PORT = 19000
const IDP_MGMT_PORT = 9000
const HEALTH_TIMEOUT_SEC = 90
const HEALTH_POLL_SEC = 2
const STOP_TIMEOUT_SEC = 10
const STOP_MAX_SEC = 12

# Bounded daemon probe: contacts the daemon briefly, never starts containers.
# Returns exact status strings: "daemon available" or "no daemon".
def docker-daemon-probe [] {
    let result = (try {
        ^docker version --format "{{.Server.Version}}" | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: "docker not found"}
    })
    if $result.exit_code == 0 {
        "daemon available"
    } else {
        "no daemon"
    }
}

def dockypody-entry [] {
    get-repo-root | path join "scripts" "dockypody.nu"
}

def run-dockypody-build [service: string, --platform: string = ""] {
    let entry = (dockypody-entry)
    let result = (if ($platform | str length) > 0 {
        ^nu $entry build --service $service --platform $platform | complete
    } else {
        ^nu $entry build --service $service | complete
    })
    if $result.exit_code != 0 {
        let detail = ([$result.stderr $result.stdout] | str join "\n" | str trim)
        error make {msg: $"build ($service) failed \(exit=($result.exit_code)\): ($detail | str substring 0..400)"}
    }
    true
}

def cleanup-idp-container [] {
    ^docker rm -f $IDP_CONTAINER | complete | ignore
}

def poll-idp-ready [] {
    let url = $"http://127.0.0.1:($IDP_HOST_PORT)/health/ready"
    mut waited = 0
    while $waited < $HEALTH_TIMEOUT_SEC {
        let ok = (try {
            http get $url | ignore
            true
        } catch {
            false
        })
        if $ok {
            return true
        }
        sleep ($"($HEALTH_POLL_SEC)sec" | into duration)
        $waited = $waited + $HEALTH_POLL_SEC
    }
    error make {msg: $"idp /health/ready not ready after ($HEALTH_TIMEOUT_SEC)s at ($url)"}
}

def stop-idp-with-time10 [] {
    let started = (date now)
    let result = (^docker stop -t $STOP_TIMEOUT_SEC $IDP_CONTAINER | complete)
    let elapsed = ((date now) - $started)
    if $result.exit_code != 0 {
        error make {msg: $"docker stop -t ($STOP_TIMEOUT_SEC) failed: ($result.stderr)"}
    }
    let max_dur = ($"($STOP_MAX_SEC)sec" | into duration)
    if $elapsed >= $max_dur {
        error make {msg: $"docker stop -t ($STOP_TIMEOUT_SEC) took ($elapsed), expected under ($STOP_MAX_SEC)s"}
    }
    true
}

def main [--verbose] {
    let verbose_flag = (try { $verbose } catch { false })

    if (docker-daemon-probe) == "no daemon" {
        print "SKIPPED: e2e-smoke requires a reachable Docker daemon"
        exit 0
    }

    mut results = []

    let t_ct_debian = (run-test "build common-tools debian" {
        run-dockypody-build "common-tools" --platform debian
    } $verbose_flag)
    $results = ($results | append $t_ct_debian)

    let t_gaia_build = (run-test "build gaia" {
        run-dockypody-build "gaia"
    } $verbose_flag)
    $results = ($results | append $t_gaia_build)

    let t_gaia_help = (run-test "gaia help produces nonempty output" {
        let out = (^docker run --rm --entrypoint /usr/local/bin/gaia gaia:latest help | complete)
        if $out.exit_code != 0 {
            error make {msg: $"gaia help failed \(exit=($out.exit_code)\): ($out.stderr)"}
        }
        let text = ($out.stdout | str trim)
        if ($text | is-empty) {
            error make {msg: "gaia help produced empty stdout"}
        }
        true
    } $verbose_flag)
    $results = ($results | append $t_gaia_help)

    let t_ct_rhel = (run-test "build common-tools rhel for idp" {
        run-dockypody-build "common-tools" --platform rhel
    } $verbose_flag)
    $results = ($results | append $t_ct_rhel)

    let t_idp_build = (run-test "build idp" {
        run-dockypody-build "idp"
    } $verbose_flag)
    $results = ($results | append $t_idp_build)

    let t_idp_lifecycle = (run-test "idp start, health ready, stop -t 10 under 12s" {
        cleanup-idp-container

        let run_out = (
            ^docker run -d --name $IDP_CONTAINER
                -p $"127.0.0.1:($IDP_HOST_PORT):($IDP_MGMT_PORT)"
                -e "KC_BOOTSTRAP_ADMIN_USERNAME=admin"
                -e "KC_BOOTSTRAP_ADMIN_PASSWORD=admin"
                -e "KC_HTTP_ENABLED=true"
                -e "KC_HOSTNAME_STRICT=false"
                -e "KC_HEALTH_ENABLED=true"
                -e "KC_HTTP_MANAGEMENT_SCHEME=http"
                idp:latest
            | complete
        )
        if $run_out.exit_code != 0 {
            cleanup-idp-container
            error make {msg: $"idp docker run failed: ($run_out.stderr)"}
        }

        try {
            poll-idp-ready
            stop-idp-with-time10
        } catch {|err|
            cleanup-idp-container
            error make {msg: $err.msg}
        }

        cleanup-idp-container
        true
    } $verbose_flag)
    $results = ($results | append $t_idp_lifecycle)

    print-test-summary $results

    let failed = ($results | where {|r| not $r} | length)
    if $failed > 0 {
        exit 1
    }
}
