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

# Copy service TLS certificates to build context
# See docs/concepts/tls-management.md
# Note: This file is also copied to Docker build context and run standalone

# Main entry point for standalone script execution
def main [
    --enabled: string,           # "true" or "false"
    --mode: string, # "ca-and-cert" | "cert-only" | "disabled"
    --ca-name: string,            # CA certificate name
    --cert-name: string = "",    # Service certificate name
    --source-certs: string = "", # Source directory for service certificates
    --dest: string,              # Destination directory
] {
    copy-tls --enabled $enabled --mode $mode --ca-name $ca_name --cert-name $cert_name --source-certs $source_certs --dest $dest
}

export def copy-tls [
    --enabled: string,           # "true" or "false"
    --mode: string, # "ca-and-cert" | "cert-only" | "disabled"
    --ca-name: string,            # CA certificate name
    --cert-name: string = "",    # Service certificate name
    --source-certs: string = "", # Source directory for service certificates
    --dest: string,              # Destination directory
] {
    if $enabled != "true" {
        print "TLS disabled, skipping certificate copy"
        return
    }
    
    if ($ca_name | str trim | is-empty) {
        error make {msg: "TLS_CA_NAME must be provided when TLS_ENABLED=true"}
    }
    
    if $mode == "ca-only" {
        error make {msg: "copy-tls should not be called for ca-only mode. This is a build system bug."}
    }
    
    if ($cert_name | str trim | is-empty) {
        error make {msg: "TLS_CERT_NAME must be provided when TLS_MODE is not 'ca-only'"}
    }
    
    if ($source_certs | str trim | is-empty) {
        error make {msg: "--source-certs must be provided when copying service certificates"}
    }
    
    mkdir $dest
    
    let cert_crt = ($source_certs | path join $"($cert_name).crt")
    let cert_key = ($source_certs | path join $"($cert_name).key")
    
    if not ($cert_crt | path exists) {
        error make {msg: $"Service certificate not found: ($cert_crt)"}
    }
    
    print $"Copying service certificate: ($cert_name).crt"
    cp $cert_crt ($dest | path join $"($cert_name).crt")
    
    if ($cert_key | path exists) {
        print $"Copying service key: ($cert_name).key"
        cp $cert_key ($dest | path join $"($cert_name).key")
    }
    
    print $"OK: TLS certificates copied: ($cert_name).{{crt,key}}"
}
