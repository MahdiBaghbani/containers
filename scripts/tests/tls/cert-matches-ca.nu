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

# Issuer/subject/malformed cert-matches-ca coverage.

use ../../lib/tls/validation.nu [cert-matches-ca]
use ../lib.nu [run-test]
use ./_temp.nu [rm-temp-context]

export def cert-matches-ca-tests [verbose: bool] {
    [
        (run-test "cert-matches-ca: non-existent files -> false" {
            let result = (cert-matches-ca "/tmp/__nonexistent__.crt" "/tmp/__nonexistent_ca__.crt")
            if $result {
                error make {msg: "cert-matches-ca should return false for non-existent files"}
            }
            true
        } $verbose)
        (run-test "cert-matches-ca: mismatched issuer/subject -> false, self-signed -> true" {
            let openssl_ok = ((try { ^which openssl | complete | get exit_code } catch { 1 }) == 0)
            if not $openssl_ok {
                if $verbose { print "    openssl not available; skipping cert-matches-ca cert test" }
                true
            } else {
                let tmp = (^mktemp -d | str trim)
                let ca1_crt = ($tmp | path join "ca1.crt")
                let ca1_key = ($tmp | path join "ca1.key")
                let ca2_crt = ($tmp | path join "ca2.crt")
                let ca2_key = ($tmp | path join "ca2.key")

                let r1 = (^openssl req -newkey rsa:2048 -days 1 -nodes -x509 -subj "/CN=TestCA1ForDockyPody" -out $ca1_crt -keyout $ca1_key | complete)
                let r2 = (^openssl req -newkey rsa:2048 -days 1 -nodes -x509 -subj "/CN=TestCA2ForDockyPody" -out $ca2_crt -keyout $ca2_key | complete)

                if $r1.exit_code != 0 or $r2.exit_code != 0 {
                    rm-temp-context $tmp
                    if $verbose { print "    openssl cert generation failed; skipping" }
                    true
                } else {
                    let mismatched = (cert-matches-ca $ca1_crt $ca2_crt)
                    let self_signed = (cert-matches-ca $ca1_crt $ca1_crt)
                    rm-temp-context $tmp

                    if $mismatched {
                        error make {msg: "cert-matches-ca should return false for mismatched issuer/subject"}
                    }
                    if not $self_signed {
                        error make {msg: "cert-matches-ca should return true for self-signed cert against itself"}
                    }
                    true
                }
            }
        } $verbose)
        (run-test "cert-matches-ca: malformed cert content -> false" {
            let tmp = (^mktemp -d | str trim)
            let bad_cert = ($tmp | path join "bad.crt")
            let bad_ca = ($tmp | path join "bad-ca.crt")
            "THIS IS NOT VALID PEM CONTENT" | save -f $bad_cert
            "ALSO INVALID PEM MATERIAL" | save -f $bad_ca
            let result = (cert-matches-ca $bad_cert $bad_ca)
            rm-temp-context $tmp
            if $result {
                error make {msg: "cert-matches-ca should return false for malformed cert content"}
            }
            true
        } $verbose)
    ]
}
