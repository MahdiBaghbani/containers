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

# generate-ca preserve / --force / failure-preservation behavior.

use ../../lib/tls/ca.nu [generate-ca]
use ../lib.nu [run-test]
use ./_temp.nu [make-temp-context rm-temp-context]

export def generate-ca-tests [verbose: bool] {
    [
        (run-test "generate-ca: existing CA without --force is preserved" {
            let tmp = (^mktemp -d | str trim)
            let ca_name = "dockypody"
            let crt = ($tmp | path join $"($ca_name).crt")
            let key = ($tmp | path join $"($ca_name).key")
            "SENTINEL-CRT" | save -f $crt
            "SENTINEL-KEY" | save -f $key

            generate-ca --ca-dir $tmp --ca-name $ca_name

            let crt_after = (open --raw $crt | decode utf-8)
            rm-temp-context $tmp
            if not ($crt_after | str contains "SENTINEL-CRT") {
                error make {msg: "Existing CA cert should be untouched without --force"}
            }
            true
        } $verbose)
        (run-test "generate-ca --force regenerates an existing CA" {
            let openssl_ok = ((try { ^which openssl | complete | get exit_code } catch { 1 }) == 0)
            if not $openssl_ok {
                if $verbose { print "    openssl not available; skipping regeneration assertion" }
                true
            } else {
                let tmp = (^mktemp -d | str trim)
                let ca_name = "dockypody"
                let crt = ($tmp | path join $"($ca_name).crt")
                let key = ($tmp | path join $"($ca_name).key")
                "SENTINEL-CRT" | save -f $crt
                "SENTINEL-KEY" | save -f $key

                generate-ca --ca-dir $tmp --ca-name $ca_name --force

                let crt_after = (open --raw $crt | decode utf-8)
                rm-temp-context $tmp
                if ($crt_after | str contains "SENTINEL-CRT") {
                    error make {msg: "--force should overwrite the existing CA cert"}
                }
                if not ($crt_after | str contains "BEGIN CERTIFICATE") {
                    error make {msg: "Regenerated CA cert should be a real PEM certificate"}
                }
                true
            }
        } $verbose)
        (run-test "generate-ca --force preserves existing CA when generation fails" {
            let tmp = (^mktemp -d | str trim)
            let ca_name = "dockypody"
            let crt = ($tmp | path join $"($ca_name).crt")
            let key = ($tmp | path join $"($ca_name).key")
            "SENTINEL-CRT" | save -f $crt
            "SENTINEL-KEY" | save -f $key

            let bin = (^mktemp -d | str trim)
            let stub = ($bin | path join "openssl")
            "#!/bin/sh\nexit 1\n" | save -f $stub
            ^chmod +x $stub

            let orig_path = ($env.PATH | default [])
            let patched_path = (if (($orig_path | describe) | str starts-with "list") {
                $orig_path | prepend $bin
            } else {
                [$bin $orig_path] | str join (char esep)
            })

            let errored = (with-env {PATH: $patched_path} {
                try {
                    generate-ca --ca-dir $tmp --ca-name $ca_name --force
                    false
                } catch {
                    true
                }
            })

            let crt_after = (open --raw $crt | decode utf-8)
            let key_after = (open --raw $key | decode utf-8)
            let tmp_key_leftover = (($tmp | path join $"($ca_name).key.tmp") | path exists)
            let tmp_crt_leftover = (($tmp | path join $"($ca_name).crt.tmp") | path exists)
            rm-temp-context $tmp
            rm-temp-context $bin

            if not $errored {
                error make {msg: "Expected generate-ca to error when openssl fails"}
            }
            if not ($crt_after | str contains "SENTINEL-CRT") {
                error make {msg: "Existing CA cert must be preserved when --force regeneration fails"}
            }
            if not ($key_after | str contains "SENTINEL-KEY") {
                error make {msg: "Existing CA key must be preserved when --force regeneration fails"}
            }
            if $tmp_key_leftover or $tmp_crt_leftover {
                error make {msg: "Temp CA artifacts should be cleaned up after a failed regeneration"}
            }
            true
        } $verbose)
    ]
}
