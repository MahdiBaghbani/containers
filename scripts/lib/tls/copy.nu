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
#
# All string parameters may contain quotes from Docker/shell expansion.
# The nested quote pattern "'$VAR'" in Dockerfiles passes values like 'true'
# (with literal single quotes) to Nushell. This file normalizes all inputs.

# Strip surrounding quotes (single or double) from a string.
# Docker/shell uses nested quotes "'$VAR'" which results in values like 'true'.
def strip-quotes [value: string] {
    let trimmed = ($value | str trim)
    let len = ($trimmed | str length)
    if $len < 2 {
        return $trimmed
    }
    if ($trimmed | str starts-with "'") and ($trimmed | str ends-with "'") {
        return ($trimmed | str substring 1..($len - 2))
    }
    if ($trimmed | str starts-with '"') and ($trimmed | str ends-with '"') {
        return ($trimmed | str substring 1..($len - 2))
    }
    $trimmed
}

# Normalize a boolean string value. Handles quoted and case variations.
# Returns "true" or "false", or errors if invalid.
def normalize-bool [value: string, param_name: string] {
    let normalized = (strip-quotes $value | str downcase)
    if $normalized == "true" {
        return "true"
    }
    if $normalized == "false" or $normalized == "" {
        return "false"
    }
    error make {msg: $"Invalid value for ($param_name): '($value)'. Expected 'true' or 'false'."}
}

# Normalize and validate mode string. Handles quoted values.
# Valid modes: ca-and-cert, cert-only, disabled, ca-only
def normalize-mode [value: string] {
    let normalized = (strip-quotes $value | str downcase)
    let valid_modes = ["ca-and-cert", "cert-only", "disabled", "ca-only"]
    if $normalized in $valid_modes {
        return $normalized
    }
    error make {msg: $"Invalid TLS mode: '($value)'. Expected one of: ($valid_modes | str join ', ')"}
}

# Main entry point for standalone script execution (called from Dockerfiles)
def main [
    --enabled: string,           # "true" or "false" (may include quotes from shell)
    --mode: string,              # "ca-and-cert" | "cert-only" | "disabled"
    --ca-name: string,           # CA certificate name
    --cert-name: string = "",    # Service certificate name
    --source-certs: string = "", # Source directory for service certificates
    --dest: string,              # Destination directory
] {
    # Normalize all string parameters - they may contain quotes from Docker/shell
    let enabled_norm = (normalize-bool $enabled "--enabled")
    let mode_norm = (normalize-mode $mode)
    let ca_name_norm = (strip-quotes $ca_name)
    let cert_name_norm = (strip-quotes $cert_name)
    let source_certs_norm = (strip-quotes $source_certs)
    let dest_norm = (strip-quotes $dest)
    
    copy-tls-internal $enabled_norm $mode_norm $ca_name_norm $cert_name_norm $source_certs_norm $dest_norm
}

# Exported function for use by other Nushell scripts (values already normalized)
export def copy-tls [
    --enabled: string,           # "true" or "false"
    --mode: string,              # "ca-and-cert" | "cert-only" | "disabled"
    --ca-name: string,           # CA certificate name
    --cert-name: string = "",    # Service certificate name
    --source-certs: string = "", # Source directory for service certificates
    --dest: string,              # Destination directory
] {
    # Normalize inputs in case called from contexts with quoted values
    let enabled_norm = (normalize-bool $enabled "--enabled")
    let mode_norm = (normalize-mode $mode)
    let ca_name_norm = (strip-quotes $ca_name)
    let cert_name_norm = (strip-quotes $cert_name)
    let source_certs_norm = (strip-quotes $source_certs)
    let dest_norm = (strip-quotes $dest)
    
    copy-tls-internal $enabled_norm $mode_norm $ca_name_norm $cert_name_norm $source_certs_norm $dest_norm
}

# Internal implementation - expects normalized values
def copy-tls-internal [
    enabled: string,       # normalized "true" or "false"
    mode: string,          # normalized mode value
    ca_name: string,       # normalized CA name
    cert_name: string,     # normalized cert name
    source_certs: string,  # normalized source path
    dest: string,          # normalized destination path
] {
    if $enabled != "true" {
        print "TLS disabled, skipping certificate copy"
        return
    }
    
    if ($ca_name | is-empty) {
        error make {msg: "TLS_CA_NAME must be provided when TLS_ENABLED=true"}
    }
    
    if $mode == "ca-only" {
        error make {msg: "copy-tls should not be called for ca-only mode. This is a build system bug."}
    }
    
    if ($cert_name | is-empty) {
        error make {msg: "TLS_CERT_NAME must be provided when TLS_MODE is not 'ca-only'"}
    }
    
    if ($source_certs | is-empty) {
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
