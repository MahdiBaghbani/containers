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

# TLS certificate validation (read-only - no working-tree writes)
# See docs/concepts/tls-management.md for details

use ./lib.nu [get-tls-mode]

export def compare-file-hashes [file1: string, file2: string] {
    if not (($file1 | path exists) and ($file2 | path exists)) {
        return false
    }
    let hash1 = (open $file1 | hash sha256)
    let hash2 = (open $file2 | hash sha256)
    $hash1 == $hash2
}

export def get-cert-issuer [cert_file: string] {
    try {
        ^openssl x509 -in $cert_file -issuer -noout
        | str trim
        | str replace "issuer=" ""
    } catch {
        ""
    }
}

export def get-ca-subject [ca_file: string] {
    try {
        ^openssl x509 -in $ca_file -subject -noout
        | str trim
        | str replace "subject=" ""
    } catch {
        ""
    }
}

export def cert-matches-ca [cert_file: string, ca_file: string] {
    let issuer = (get-cert-issuer $cert_file)
    let subject = (get-ca-subject $ca_file)
    if ($issuer | is-empty) or ($subject | is-empty) {
        return false
    }
    $issuer == $subject
}

export def check-cert-expiration [cert_file: string, cert_label: string] {
    try {
        let end_date = (^openssl x509 -in $cert_file -enddate -noout | str trim | str replace "notAfter=" "")
        $"  INFO: ($cert_label) expires: ($end_date)"
    } catch {
        ""
    }
}

# Validate CA and service certificates without writing to the working tree.
# Uses shared CA at tls/certificate-authority/ and service certs at
# services/<svc>/tls/certificates/ directly.
export def validate-ca [
    service: string,
    cfg: record,
    ca_name: string
] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    if not $tls_enabled {
        return
    }

    if ($ca_name | str trim | is-empty) {
        error make {msg: "CA name must be provided when TLS is enabled. This is a build system bug."}
    }

    let tls_mode_raw = (get-tls-mode $cfg)
    if $tls_mode_raw == null {
        return
    }
    let tls_mode = $tls_mode_raw

    let cert_name = (try { $cfg.tls.cert_name } catch { "" })

    if $tls_mode == "ca-only" and ($cert_name | str trim | is-not-empty) {
        print $"WARNING: Service '($service)' has mode='ca-only' but cert_name='($cert_name)' is provided. cert_name will be ignored in ca-only mode."
    }

    if $tls_mode != "ca-only" {
        if ($cert_name | is-empty) {
            error make {msg: $"Service '($service)' has TLS enabled with mode '($tls_mode)' but no cert_name specified in config"}
        }
    }

    if $tls_mode == "cert-only" {
        let service_cert_crt = $"services/($service)/tls/certificates/($cert_name).crt"
        if not ($service_cert_crt | path exists) {
            error make {msg: $"Service certificate not found: ($service_cert_crt). Run 'nu scripts/dockypody.nu tls certs' first"}
        }
        let exp = (check-cert-expiration $service_cert_crt $"Service certificate '($cert_name)'")
        if not ($exp | is-empty) { print $exp }
        print "OK: Cert-only mode: Service certificate validated (using public CA)"
        return
    }

    # ca-only or ca-and-cert: validate against shared CA
    let shared_ca_crt = $"tls/certificate-authority/($ca_name).crt"
    if not ($shared_ca_crt | path exists) {
        error make {msg: $"Shared CA not found: ($shared_ca_crt). Run 'nu scripts/dockypody.nu tls ca' first"}
    }

    let ca_exp = (check-cert-expiration $shared_ca_crt $"Shared CA '($ca_name)'")
    if not ($ca_exp | is-empty) { print $ca_exp }

    if $tls_mode == "ca-only" {
        print $"OK: CA-only mode: Shared CA validated"
        return
    }

    # ca-and-cert: also validate service leaf cert
    let service_cert_crt = $"services/($service)/tls/certificates/($cert_name).crt"
    if not ($service_cert_crt | path exists) {
        error make {msg: $"Service certificate not found: ($service_cert_crt). Run 'nu scripts/dockypody.nu tls certs' first"}
    }

    let cert_exp = (check-cert-expiration $service_cert_crt $"Service certificate '($cert_name)'")
    if not ($cert_exp | is-empty) { print $cert_exp }

    if not (cert-matches-ca $service_cert_crt $shared_ca_crt) {
        error make {msg: $"Certificate '($cert_name).crt' for service '($service)' does not match shared CA '($ca_name)'. Regenerate certificates with 'nu scripts/dockypody.nu tls certs'."}
    }

    print $"OK: CA and cert validated for service '($service)'"
}
