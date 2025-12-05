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

# Certificate generation - see docs/concepts/tls-management.md

use ./lib.nu *

export def generate-cert [
    --service: string,  # Service name (required)
    --domain: string,  # Domain (required)
    --cert-name: string = "",  # Optional cert name override
    --san: list<string> = [],  # Optional additional SAN entries
    --days: int = 36500,
    --keep-intermediate,
    --country: string = $SUBJECT_COUNTRY,
    --state: string = $SUBJECT_STATE,
    --locality: string = $SUBJECT_LOCALITY,
    --organization: string = $SUBJECT_ORGANIZATION,
    --verbose,
] {
    if ($service | is-empty) or ($domain | is-empty) {
        error make {msg: "Error: --service and --domain are required"}
    }
    
    let ca_name = (read-shared-ca-name)
    if $ca_name == null {
        error make {msg: "CA metadata file not found. Run 'dockypody tls ca' first"}
    }
    
    let cert_hostname = (if ($cert_name | str length) > 0 {
        $cert_name
    } else {
        extract-hostname $domain
    })
    
    let service_dir = ((get-services-dir) | path join $service)
    let cert_dir = ($service_dir | path join "tls" "certificates")
    
    ensure-service-tls-dirs $service
    
    let shared_ca_dir = (get-shared-ca-dir)
    let ca_cert = ($shared_ca_dir | path join $"($ca_name).crt")
    let ca_key = ($shared_ca_dir | path join $"($ca_name).key")
    
    if not (($ca_cert | path exists) and ($ca_key | path exists)) {
        error make {msg: $"CA files not found at ($shared_ca_dir)/($ca_name).{{crt,key}}. Run 'dockypody tls ca' first"}
    }
    
    require-openssl
    
    if $verbose {
        print $"Generating key and CSR for ($service) \(cert name: ($cert_hostname), domain: ($domain)\)"
    }
    
    let csr_file = ($cert_dir | path join $"($cert_hostname).csr")
    let key_file = ($cert_dir | path join $"($cert_hostname).key")
    
    let subject = (build-subject $domain --country $country --state $state --locality $locality --organization $organization)
    let req_result = (^openssl req -new -nodes 
        -out $csr_file
        -keyout $key_file
        -subj $subject | complete)
    
    if $req_result.exit_code != 0 {
        error make {msg: "Failed to generate CSR and key"}
    }
    
    let cnf_file = ($cert_dir | path join $"($cert_hostname).cnf")
    let san_config = (build-san-config $domain $san)
    $san_config | save -f $cnf_file
    
    if $verbose {
        print $"Signing CSR for ($domain), creating certificate."
    }
    let cert_file = ($cert_dir | path join $"($cert_hostname).crt")
    
    let sign_result = (^openssl x509 -req 
        -days $days
        -in $csr_file
        -CA $ca_cert
        -CAkey $ca_key
        -CAcreateserial
        -out $cert_file
        -extfile $cnf_file
        -sha256 | complete)
    
    if $sign_result.exit_code != 0 {
        error make {msg: $"Failed to sign certificate for ($domain)"}
    }
    
    if not $keep_intermediate {
        rm -f $csr_file $cnf_file
        rm -f ($shared_ca_dir | path join $"($ca_name).srl")
    } else {
        if $verbose {
            print $"Keeping intermediate files: ($csr_file), ($cnf_file)"
        }
    }
    
    # Adjust ownership for idp certificates (requires sudo)
    if $cert_hostname == "idp" {
        if $verbose {
            print "Changing ownership for idp certificates."
        }
        let sudo_available = (try {
            (^which sudo | complete | get exit_code)
        } catch {
            1
        }) == 0
        
        if $sudo_available {
            ^sudo chown 1000:root ($cert_dir | path join "idp.*") | ignore
        } else {
            print "Warning: sudo not available, skipping ownership change for idp"
        }
    }
    
    print $"Certificate generated successfully: ($cert_dir)/($cert_hostname).{{crt,key}}"
    if $verbose {
        print $"  Subject: ($subject)"
        print $"  Validity: ($days) days"
        print $"  SANs included: ($domain) + ($san | length) additional + global SANs"
    }
}
