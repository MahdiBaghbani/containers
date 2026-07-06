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

# Routed tls ca --force hermetic smoke test.

use ../../lib/core/repo.nu [get-repo-root]
use ../lib.nu [run-test]
use ./_fixtures.nu [rm-temp-context]

export def test-smoke-tls-ca-force-routing [verbose: bool] {
    run-test "smoke: routed tls ca forwards --force (hermetic, no repo writes)" {
        let root = (get-repo-root)
        let entry = ($root | path join "scripts" "dockypody.nu")

        let fake_repo = (^mktemp -d | str trim)
        let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
        mkdir $ca_dir
        let ca_name = "dockypody"
        let crt = ($ca_dir | path join $"($ca_name).crt")
        let key = ($ca_dir | path join $"($ca_name).key")
        "SENTINEL-CRT" | save -f $crt
        "SENTINEL-KEY" | save -f $key

        let bin = (^mktemp -d | str trim)
        $"#!/bin/sh\necho '($fake_repo)'\n" | save -f ($bin | path join "git")
        "#!/bin/sh\nexit 1\n" | save -f ($bin | path join "openssl")
        ^chmod +x ($bin | path join "git")
        ^chmod +x ($bin | path join "openssl")

        let orig_path = ($env.PATH | default [])
        let patched_path = (if (($orig_path | describe) | str starts-with "list") {
            $orig_path | prepend $bin
        } else {
            [$bin $orig_path] | str join (char esep)
        })

        let outcomes = (with-env {PATH: $patched_path} {
            let forced = (^nu $entry tls ca --force | complete)
            let unforced = (^nu $entry tls ca | complete)
            {forced_errored: ($forced.exit_code != 0), unforced_ok: ($unforced.exit_code == 0)}
        })

        let crt_after = (open --raw $crt | decode utf-8)
        let key_after = (open --raw $key | decode utf-8)
        let tmp_leftover = (
            (($ca_dir | path join $"($ca_name).crt.tmp") | path exists)
                or (($ca_dir | path join $"($ca_name).key.tmp") | path exists)
        )
        rm-temp-context $fake_repo
        rm-temp-context $bin

        if not $outcomes.forced_errored {
            error make {msg: "routed 'tls ca' force=true should reach generation and error under failing openssl"}
        }
        if not $outcomes.unforced_ok {
            error make {msg: "routed 'tls ca' force=false should take the existing-CA skip path without error"}
        }
        if not ($crt_after | str contains "SENTINEL-CRT") {
            error make {msg: "existing CA cert must be preserved (no real write on failed force)"}
        }
        if not ($key_after | str contains "SENTINEL-KEY") {
            error make {msg: "existing CA key must be preserved (no real write on failed force)"}
        }
        if $tmp_leftover {
            error make {msg: "temp CA artifacts should be cleaned up after failed generation"}
        }
        true
    } $verbose
}
