#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

use ./lib.nu *

def main [
    --ca-name: string = "dockypody",
    --days: int = 36500,
    --country: string = $SUBJECT_COUNTRY,
    --state: string = $SUBJECT_STATE,
    --locality: string = $SUBJECT_LOCALITY,
    --organization: string = $SUBJECT_ORGANIZATION,
    --verbose,
] {
    let ca_dir = (get-shared-ca-dir)
    mkdir $ca_dir
    
    require-openssl
    
    let ca_key = ($ca_dir | path join $"($ca_name).key")
    let ca_cert = ($ca_dir | path join $"($ca_name).crt")
    
    if (($ca_cert | path exists) and ($ca_key | path exists)) {
        if $verbose {
            print $"CA already exists at ($ca_dir)/($ca_name).{{crt,key}}"
        }
        print "Skipping CA generation. Delete files to regenerate."
        
        let ca_metadata_file = ($ca_dir | path join "ca.json")
        if not ($ca_metadata_file | path exists) {
            {"name": $ca_name} | to json | save -f $ca_metadata_file
            if $verbose {
                print $"Created CA metadata file: ($ca_metadata_file)"
            }
        }
        return
    }
    
    if $verbose {
        print "Generating Certificate Authority private key..."
    }
    let keygen_result = (^openssl genrsa -out $ca_key 2048 | complete)
    if $keygen_result.exit_code != 0 {
        error make {msg: "Failed to generate CA private key"}
    }
    
    if $verbose {
        print "Generating self-signed Certificate Authority certificate..."
    }
    let subject = (build-subject $ca_name --country $country --state $state --locality $locality --organization $organization)
    let cert_result = (^openssl req -new -x509 
        -days $days
        -key $ca_key 
        -out $ca_cert 
        -subj $subject
        -sha256 | complete)
    
    if $cert_result.exit_code != 0 {
        error make {msg: "Failed to generate CA certificate"}
    }
    
    let ca_metadata_file = ($ca_dir | path join "ca.json")
    {"name": $ca_name} | to json | save -f $ca_metadata_file
    
    print ""
    print "Certificate Authority setup complete."
    print $"Private Key: ($ca_key)"
    print $"Certificate: ($ca_cert)"
    if $verbose {
        print $"Subject: ($subject)"
        print $"Validity: ($days) days"
    }
}
