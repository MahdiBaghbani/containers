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

# CA generation - see docs/concepts/tls-management.md

use ./lib.nu *

export def generate-ca [
    --ca-name: string = "dockypody",
    --days: int = 36500,
    --country: string = $SUBJECT_COUNTRY,
    --state: string = $SUBJECT_STATE,
    --locality: string = $SUBJECT_LOCALITY,
    --organization: string = $SUBJECT_ORGANIZATION,
    --ca-dir: string = "",  # Override shared CA directory (testing/advanced use)
    --force,                # Regenerate the CA even if it already exists
    --verbose,
] {
    let ca_dir = (if ($ca_dir | str length) > 0 { $ca_dir } else { (get-shared-ca-dir) })
    mkdir $ca_dir

    let ca_key = ($ca_dir | path join $"($ca_name).key")
    let ca_cert = ($ca_dir | path join $"($ca_name).crt")
    let ca_exists = (($ca_cert | path exists) and ($ca_key | path exists))

    if $ca_exists and (not $force) {
        if $verbose {
            print $"CA already exists at ($ca_dir)/($ca_name).{{crt,key}}"
        }
        print "Skipping CA generation. Delete files or pass --force to regenerate."

        let ca_metadata_file = ($ca_dir | path join "ca.json")
        if not ($ca_metadata_file | path exists) {
            {"name": $ca_name} | to json | save -f $ca_metadata_file
            if $verbose {
                print $"Created CA metadata file: ($ca_metadata_file)"
            }
        }
        return
    }

    require-openssl

    if $ca_exists and $force {
        print "WARNING: Regenerating the shared CA (--force)."
        print "WARNING: Existing service certificates were signed by the previous CA"
        print "WARNING: and will no longer validate against it. Regenerate them with:"
        print "WARNING:   nu scripts/dockypody.nu tls certs"
    }

    # Generate into temp paths first, then swap into place only after both the
    # key and cert succeed. This keeps an existing CA intact if generation fails
    # part-way (e.g. openssl error), instead of deleting it up front.
    let ca_key_tmp = ($ca_dir | path join $"($ca_name).key.tmp")
    let ca_cert_tmp = ($ca_dir | path join $"($ca_name).crt.tmp")
    if ($ca_key_tmp | path exists) { rm -f $ca_key_tmp }
    if ($ca_cert_tmp | path exists) { rm -f $ca_cert_tmp }

    if $verbose {
        print "Generating Certificate Authority private key..."
    }
    let keygen_result = (^openssl genrsa -out $ca_key_tmp 2048 | complete)
    if $keygen_result.exit_code != 0 {
        try { rm -f $ca_key_tmp }
        error make {msg: "Failed to generate CA private key"}
    }
    
    if $verbose {
        print "Generating self-signed Certificate Authority certificate..."
    }
    let subject = (build-subject $ca_name --country $country --state $state --locality $locality --organization $organization)
    let cert_result = (^openssl req -new -x509 
        -days $days
        -key $ca_key_tmp 
        -out $ca_cert_tmp 
        -subj $subject
        -sha256 | complete)
    
    if $cert_result.exit_code != 0 {
        try { rm -f $ca_key_tmp }
        try { rm -f $ca_cert_tmp }
        error make {msg: "Failed to generate CA certificate"}
    }

    # Both artifacts exist; swap them into their final names.
    mv -f $ca_key_tmp $ca_key
    mv -f $ca_cert_tmp $ca_cert

    # A regenerated CA invalidates the old serial file; drop it after success.
    if $ca_exists and $force {
        let ca_srl = ($ca_dir | path join $"($ca_name).srl")
        if ($ca_srl | path exists) {
            rm -f $ca_srl
        }
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
