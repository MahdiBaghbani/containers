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

# Import get-repo-root from core/repo.nu (canonical implementation)
use ../core/repo.nu [get-repo-root]

export def get-services-dir [] {
    (get-repo-root | path join "services")
}

export def get-shared-ca-dir [] {
    (get-repo-root | path join "tls" "certificate-authority")
}

# Subject defaults (unified across CA and leaf certs)
export const SUBJECT_COUNTRY = "CH"
export const SUBJECT_STATE = "Geneva"
export const SUBJECT_LOCALITY = "Geneva"
export const SUBJECT_ORGANIZATION = "Open Cloud Mesh"

export const GLOBAL_SANS = [
    "DNS:localhost",
    "IP:127.0.0.1",
    "IP:::1"
]

export def require-openssl [] {
    let openssl_available = (try {
        (^which openssl | complete | get exit_code)
    } catch {
        1
    }) == 0
    
    if not $openssl_available {
        error make {msg: "OpenSSL is not installed or not in PATH"}
    }
}

export def read-shared-ca-name [] {
    let ca_metadata_file = (get-shared-ca-dir | path join "ca.json")
    if not ($ca_metadata_file | path exists) {
        return null
    }
    
    try {
        let parsed = (open $ca_metadata_file)
        $parsed.name
    } catch {|err|
        null
    }
}

export def ensure-service-tls-dirs [service_name: string] {
    let service_dir = ((get-services-dir) | path join $service_name)
    let cert_dir = ($service_dir | path join "tls" "certificates")
    let service_ca_dir = ($service_dir | path join "tls" "certificate-authority")
    
    mkdir $cert_dir
    mkdir $service_ca_dir
}

export def copy-shared-ca-to-service [
    service_name: string,
    --force
] {
    let ca_name = (read-shared-ca-name)
    if $ca_name == null {
        error make {msg: "CA metadata file not found. Please run scripts/tls/generate-ca.nu first"}
    }
    
    let services_dir = (get-services-dir)
    let shared_ca_dir = (get-shared-ca-dir)
    let service_dir = ($services_dir | path join $service_name)
    let service_ca_dir = ($service_dir | path join "tls" "certificate-authority")
    
    let shared_crt = ($shared_ca_dir | path join $"($ca_name).crt")
    let shared_key = ($shared_ca_dir | path join $"($ca_name).key")
    
    if not (($shared_crt | path exists) and ($shared_key | path exists)) {
        error make {msg: $"CA files not found. Expected: ($shared_crt), ($shared_key). Please run scripts/tls/generate-ca.nu first"}
    }
    
    mkdir $service_ca_dir
    
    let service_ca_crt = ($service_ca_dir | path join $"($ca_name).crt")
    let file_exists = ($service_ca_crt | path exists)
    
    let force_flag = (try { $force } catch { false })
    if $force_flag or (not $file_exists) {
        cp -f $shared_crt $service_ca_crt
        cp -f $shared_key ($service_ca_dir | path join $"($ca_name).key")
    }
}

# Build SAN config file (main_domain is DNS.1, extra_sans and global_sans added after)
export def build-san-config [
    main_domain: string,
    extra_sans: list = [],
    --global-sans: list = $GLOBAL_SANS
] {
    mut san_lines = ["subjectAltName = @alt_names", "[alt_names]"]
    $san_lines = ($san_lines | append $"DNS.1 = ($main_domain)")
    
    mut idx = 2
    mut seen_domains = [$main_domain]
    
    for entry in $extra_sans {
        if ($entry | str starts-with "DNS:") {
            let val = ($entry | str replace -a "DNS:" "")
            if $val not-in $seen_domains {
                $san_lines = ($san_lines | append $"DNS.($idx) = ($val)")
                $seen_domains = ($seen_domains | append $val)
                $idx = ($idx + 1)
            }
        } else if ($entry | str starts-with "IP:") {
            let val = ($entry | str replace -a "IP:" "")
            $san_lines = ($san_lines | append $"IP.($idx) = ($val)")
            $idx = ($idx + 1)
        }
    }
    
    for entry in $global_sans {
        if ($entry | str starts-with "DNS:") {
            let val = ($entry | str replace -a "DNS:" "")
            if $val not-in $seen_domains {
                $san_lines = ($san_lines | append $"DNS.($idx) = ($val)")
                $seen_domains = ($seen_domains | append $val)
                $idx = ($idx + 1)
            }
        } else if ($entry | str starts-with "IP:") {
            let val = ($entry | str replace -a "IP:" "")
            $san_lines = ($san_lines | append $"IP.($idx) = ($val)")
            $idx = ($idx + 1)
        }
    }
    
    ($san_lines | str join "\n") + "\n"
}

export def build-subject [
    cn: string,
    --country: string = $SUBJECT_COUNTRY,
    --state: string = $SUBJECT_STATE,
    --locality: string = $SUBJECT_LOCALITY,
    --organization: string = $SUBJECT_ORGANIZATION
] {
    $"/C=($country)/ST=($state)/L=($locality)/O=($organization)/CN=($cn)"
}

export def extract-hostname [domain: string] {
    ($domain | split row "." | get 0)
}

# Error constant for CA not found
export const ERROR_CA_NOT_FOUND = "CA metadata file not found. Run 'nu scripts/dockypody.nu tls ca' first"

# Get TLS mode from service config
# Returns null if TLS is not enabled, otherwise returns the mode
export def get-tls-mode [cfg: record] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    
    if not $tls_enabled {
        return null
    }
    
    try { 
        $cfg.tls.mode
    } catch { 
        error make {msg: "tls.mode is required when tls.enabled=true"}
    }
}

# Read CA name from ca.json with detailed error handling
# Used by build operations that need specific error messages
export def read-ca-name [tls_enabled: bool] {
    if not $tls_enabled {
        return ""
    }
    
    let ca_metadata_file = "tls/certificate-authority/ca.json"
    if not ($ca_metadata_file | path exists) {
        error make {msg: $"CA metadata file not found: ($ca_metadata_file). Run 'nu scripts/dockypody.nu tls ca' first"}
    }
    
    let ca_metadata = (try {
        open $ca_metadata_file
    } catch {|err|
        error make {msg: $"CA metadata file '($ca_metadata_file)' has invalid JSON. Error: ($err.msg)"}
    })
    
    if not ("name" in ($ca_metadata | columns)) {
        error make {msg: $"CA metadata file '($ca_metadata_file)' missing required field 'name'"}
    }
    
    let ca_name = $ca_metadata.name
    if ($ca_name | str trim | is-empty) {
        error make {msg: $"CA metadata file '($ca_metadata_file)' has empty 'name' field"}
    }
    
    $ca_name
}

# Require CA to exist, returning the CA name
export def require-ca [] {
    let ca_name = (read-shared-ca-name)
    if $ca_name == null {
        error make {msg: $ERROR_CA_NOT_FOUND}
    }
    $ca_name
}
