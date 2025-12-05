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

# Build context preparation - TLS and local sources
# See docs/concepts/build-system.md for architecture

use ../tls/lib.nu [get-tls-mode]

export def extract-tls-metadata [
    cfg: record,
    ca_name: string = ""  # CA name from ca.json (read once per build in build.nu)
] {
    let tls_enabled = (try { $cfg.tls.enabled | default false } catch { false })
    
    let tls_mode_raw = (get-tls-mode $cfg)
    let tls_mode = (if $tls_enabled {
        if $tls_mode_raw == null {
            error make {msg: "tls.mode is required when tls.enabled=true (validation should have caught this)"}
        }
        $tls_mode_raw
    } else {
        "disabled"
    })
    
    let tls_cert_name = (try { $cfg.tls.cert_name } catch { "" })
    
    let tls_ca_name = (if $tls_enabled {
        if ($ca_name | str trim | is-empty) {
            error make {msg: "CA name must be provided when TLS is enabled. This is a build system bug - CA name should have been read and validated in build.nu."}
        }
        $ca_name
    } else {
        ""
    })
    
    {
        enabled: $tls_enabled,
        mode: $tls_mode,
        cert_name: $tls_cert_name,
        ca_name: $tls_ca_name
    }
}

export def prepare-tls-context [
    service: string,
    context: string,
    tls_enabled: bool,
    tls_mode: string  # Mode parameter (required, no default to prevent masking validation errors)
] {
    if not $tls_enabled {
        return {copied: false, files: []}
    }
    
    if ($tls_mode | str trim | is-empty) or $tls_mode == "disabled" {
        error make {msg: "tls_mode parameter is required when tls_enabled=true. This is a build system bug."}
    }
    
    if $tls_mode == "ca-only" {
        print "CA-only mode: Skipping copy-tls.nu copy (not needed)"
        return {copied: false, files: []}
    }
    
    # Verify TLS helper script exists before copying
    let tls_helper_script = "scripts/lib/tls/copy.nu"
    if not ($tls_helper_script | path exists) {
        error make {
            msg: ($"TLS helper script not found: ($tls_helper_script)\n\n" +
                  "This script is required for TLS modes 'ca-and-cert' and 'cert-only'.\n" +
                  "The file should be located at scripts/lib/tls/copy.nu.\n\n")
        }
    }
    
    mkdir ($"($context)/scripts/tls")
    cp $tls_helper_script $"($context)/scripts/tls/copy-tls.nu"
    print "Copied TLS helper script to service context: copy-tls.nu"
    {copied: true, files: ["copy-tls.nu"]}
}

export def cleanup-tls-context [
    context: string,
    tls_context: record
] {
    if not $tls_context.copied {
        return
    }
    
    for file in $tls_context.files {
        rm -f $"($context)/scripts/tls/($file)"
    }
    
    try { rmdir $"($context)/scripts/tls" } catch { }
    print "Cleaned up TLS helper script(s) from service context"
}
