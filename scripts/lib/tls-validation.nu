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

# TLS certificate validation and synchronization
# See docs/concepts/tls-management.md for details

use ./common.nu [get-tls-mode]

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

export def sync-and-validate-ca [
    service: string,
    cfg: record,
    ca_name: string  # CA name passed as parameter (already validated in build.nu)
] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    if not $tls_enabled {
        return
    }
    
    if ($ca_name | str trim | is-empty) {
        error make {msg: "CA name must be provided when TLS is enabled. This is a build system bug - CA name should have been read and validated in build.nu."}
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
            error make {msg: $"Service certificate not found: ($service_cert_crt). Please run scripts/tls/generate-all-certs.nu first"}
        }
        let service_cert_exp = (check-cert-expiration $service_cert_crt $"Service certificate '($cert_name)'")
        if not ($service_cert_exp | is-empty) {
            print $service_cert_exp
        }
        print $"OK: Cert-only mode: Service certificate validated (CA validation and sync skipped - using public CA)"
        return
    }
    
    let shared_ca_crt = $"tls/certificate-authority/($ca_name).crt"
    let service_ca_crt = $"services/($service)/tls/certificate-authority/($ca_name).crt"
    
    if not ($shared_ca_crt | path exists) {
        error make {msg: $"Shared CA not found: ($shared_ca_crt). Please run scripts/tls/generate-ca.nu first"}
    }
    
    let shared_ca_exp = (check-cert-expiration $shared_ca_crt $"Shared CA '($ca_name)'")
    if not ($shared_ca_exp | is-empty) {
        print $shared_ca_exp
    }
    
    if not ($service_ca_crt | path exists) {
        print $"Service CA not found, copying from shared CA..."
        let shared_ca_key = $"tls/certificate-authority/($ca_name).key"
        let service_ca_dir = $"services/($service)/tls/certificate-authority"
        mkdir $service_ca_dir
        cp -f $shared_ca_crt $service_ca_crt
        cp -f $shared_ca_key ($"($service_ca_dir)/($ca_name).key")
        print $"OK: Copied shared CA to service directory"
        
        if $tls_mode == "ca-only" {
            return
        }
    }
    
    if (compare-file-hashes $shared_ca_crt $service_ca_crt) {
        print $"OK: CA sync: Service CA matches shared CA \(($ca_name)\) - skipping sync"
        
        if $tls_mode == "ca-only" {
            return
        }
    } else {
        print $"WARNING: CA Mismatch for service '($service)':"
        
        let shared_ca_hash = (open $shared_ca_crt | hash sha256 | str substring 0..8)
        let service_ca_hash = (open $service_ca_crt | hash sha256 | str substring 0..8)
        
        print $"   - Shared CA: ($ca_name) \(hash: ($shared_ca_hash)...\)"
        print $"   - Service CA: ($ca_name) \(hash: ($service_ca_hash)...\)"
        
        if $tls_mode == "ca-only" {
            print $"   -> Copying shared CA to service directory"
            let shared_ca_key = $"tls/certificate-authority/($ca_name).key"
            cp -f $shared_ca_crt $service_ca_crt
            cp -f $shared_ca_key ($"services/($service)/tls/certificate-authority/($ca_name).key")
            return
        }
        
        print $"   - Validating certificate issuer..."
    }
    
    if $tls_mode == "ca-and-cert" {
        let service_cert_crt = $"services/($service)/tls/certificates/($cert_name).crt"
        
        if not ($service_cert_crt | path exists) {
            error make {msg: $"Service certificate not found: ($service_cert_crt). Please run scripts/tls/generate-all-certs.nu first"}
        }
        
        let service_cert_exp = (check-cert-expiration $service_cert_crt $"Service certificate '($cert_name)'")
        if not ($service_cert_exp | is-empty) {
            print $service_cert_exp
        }
        
        if not (compare-file-hashes $shared_ca_crt $service_ca_crt) {
            let matches_shared = (cert-matches-ca $service_cert_crt $shared_ca_crt)
            let matches_service = (cert-matches-ca $service_cert_crt $service_ca_crt)
            
            if $matches_shared {
                print $"   OK: Certificate '($cert_name).crt' issuer matches: shared CA"
                print $"   -> Copying shared CA to service directory"
                print $"   -> Service certificates belong to shared CA"
                let shared_ca_key = $"tls/certificate-authority/($ca_name).key"
                cp -f $shared_ca_crt $service_ca_crt
                cp -f $shared_ca_key ($"services/($service)/tls/certificate-authority/($ca_name).key")
            } else if $matches_service {
                print $"   OK: Certificate '($cert_name).crt' issuer matches: service CA"
                print $"   -> Using service CA \(differs from shared CA\)"
                print $"   WARNING: Service CA differs from shared CA"
            } else {
                print $"   ERROR: Certificate '($cert_name).crt' does not match shared CA or service CA"
                error make {msg: "Certificate issuer validation failed. Please regenerate certificates."}
            }
        }
    }
}
