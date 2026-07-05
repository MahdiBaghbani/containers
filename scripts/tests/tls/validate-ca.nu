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

# Certificate validation mode and malformed-cert coverage.

use ../../lib/tls/validation.nu [validate-ca]
use ../lib.nu [run-test]
use ./_temp.nu [rm-temp-context]

export def validate-ca-tests [verbose: bool] {
    [
        (run-test "validate-ca: TLS disabled is a no-op" {
            validate-ca "some-service" {tls: {enabled: false}} "any-ca"
            true
        } $verbose)
        (run-test "validate-ca: TLS enabled but empty ca_name -> error" {
            let errored = (try {
                validate-ca "some-service" {tls: {enabled: true, mode: "ca-only"}} ""
                false
            } catch { true })
            if not $errored {
                error make {msg: "Expected error for empty ca_name with TLS enabled"}
            }
            true
        } $verbose)
        (run-test "validate-ca: ca-only mode missing CA cert -> error" {
            let fake_repo = (^mktemp -d | str trim)
            let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            mkdir $ca_dir

            let errored = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "ca-only"}} "test-ca"
                    false
                } catch { true }
            })
            rm-temp-context $fake_repo
            if not $errored {
                error make {msg: "Expected error when CA cert file is missing"}
            }
            true
        } $verbose)
        (run-test "validate-ca: ca-only mode with present CA cert -> ok" {
            let fake_repo = (^mktemp -d | str trim)
            let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            mkdir $ca_dir

            let ca_name = "test-ca"
            "-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----\n" | save -f ($ca_dir | path join $"($ca_name).crt")

            let ok = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "ca-only"}} $ca_name
                    true
                } catch {
                    false
                }
            })
            rm-temp-context $fake_repo
            if not $ok {
                error make {msg: "Expected validate-ca to succeed for ca-only mode with present CA cert"}
            }
            true
        } $verbose)
        (run-test "validate-ca: ca-and-cert mode missing CA cert -> error" {
            let fake_repo = (^mktemp -d | str trim)
            let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            mkdir $ca_dir

            let errored = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                    false
                } catch { true }
            })
            rm-temp-context $fake_repo
            if not $errored {
                error make {msg: "Expected error for ca-and-cert with missing CA cert"}
            }
            true
        } $verbose)
        (run-test "validate-ca: ca-and-cert mode CA present but service cert missing -> error" {
            let fake_repo = (^mktemp -d | str trim)
            let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            mkdir $ca_dir
            "FAKE CA CERT" | save -f ($ca_dir | path join "test-ca.crt")

            let errored = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                    false
                } catch { true }
            })
            rm-temp-context $fake_repo
            if not $errored {
                error make {msg: "Expected error for ca-and-cert with missing service cert"}
            }
            true
        } $verbose)
        (run-test "validate-ca: cert-only mode missing service cert -> error" {
            let fake_repo = (^mktemp -d | str trim)

            let errored = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "cert-only", cert_name: "svc"}} "test-ca"
                    false
                } catch { true }
            })
            rm-temp-context $fake_repo
            if not $errored {
                error make {msg: "Expected error for cert-only with missing service cert"}
            }
            true
        } $verbose)
        (run-test "validate-ca: malformed shared and service cert -> rejected" {
            let fake_repo = (^mktemp -d | str trim)
            let ca_dir = ($fake_repo | path join "tls" "certificate-authority")
            let svc_dir = ($fake_repo | path join "services" "my-svc" "tls" "certificates")
            mkdir $ca_dir
            mkdir $svc_dir
            "NOT VALID CA PEM" | save -f ($ca_dir | path join "test-ca.crt")
            "NOT VALID SERVICE PEM" | save -f ($svc_dir | path join "svc.crt")

            let errored = (do {
                cd $fake_repo
                try {
                    validate-ca "my-svc" {tls: {enabled: true, mode: "ca-and-cert", cert_name: "svc"}} "test-ca"
                    false
                } catch { true }
            })
            rm-temp-context $fake_repo
            if not $errored {
                error make {msg: "validate-ca should reject malformed cert material that cannot match CA"}
            }
            true
        } $verbose)
    ]
}
