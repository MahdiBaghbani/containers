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

# Build context preparation - TLS helper script and CA material
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

    let tls_scripts_dir = $"($context)/scripts/tls"
    if ($tls_scripts_dir | path exists) and ((ls $tls_scripts_dir | length) == 0) {
        rmdir $tls_scripts_dir
    }
    print "Cleaned up TLS helper script(s) from service context"
}

# Detect whether the Dockerfile requires CA cert and/or key in the build context.
#
# Rules (deterministic string scan):
#   needs_ca_crt = true  when Dockerfile has "COPY ./tls " or "COPY ./tls/" (broad
#                        tls-dir copy, conservative - acceptable to over-stage .crt),
#                        or an explicit "certificate-authority/<ca_name>.crt" literal,
#                        or a variable "certificate-authority/${TLS_CA_NAME}.crt".
#   needs_ca_key = true  only when Dockerfile has an explicit
#                        "certificate-authority/<ca_name>.key" literal or a variable
#                        "certificate-authority/${TLS_CA_NAME}.key".
#
# Fail-closed: if the Dockerfile references "certificate-authority/" AND "TLS_CA_NAME"
# but contains no explicit .crt or .key extension, staging cannot be deterministic
# and an error is raised with an actionable message.
#
# cert-only mode always returns false/false because it uses a public CA.
export def detect-ca-requirements [
    dockerfile_text: string,
    ca_name: string,
    tls_mode: string
] {
    if $tls_mode == "cert-only" or $tls_mode == "disabled" or ($tls_mode | is-empty) {
        return {needs_ca_crt: false, needs_ca_key: false}
    }

    if ($ca_name | str trim | is-empty) {
        error make {msg: "detect-ca-requirements: ca_name must not be empty when TLS is active"}
    }

    # "COPY ./tls " (trailing space) and "COPY ./tls/" (trailing slash) both
    # match broad tls-dir copies. The slash form also covers sub-paths like
    # "COPY ./tls/certificate-authority/..." and "COPY ./tls/certificates/..."
    # (conservative: may over-stage .crt, which is acceptable).
    let copies_tls_broad = (
        ($dockerfile_text | str contains "COPY ./tls ")
        or ($dockerfile_text | str contains "COPY ./tls/")
    )

    # Literal patterns using the resolved CA name.
    let ca_crt_literal = ($dockerfile_text | str contains $"certificate-authority/($ca_name).crt")
    let ca_key_literal = ($dockerfile_text | str contains $"certificate-authority/($ca_name).key")

    # Variable patterns: ${TLS_CA_NAME}.crt / ${TLS_CA_NAME}.key in Dockerfiles.
    # Substring "TLS_CA_NAME}.crt" matches "${TLS_CA_NAME}.crt" without needing
    # to escape the dollar/brace in a Nushell string check.
    let ca_crt_var = ($dockerfile_text | str contains "TLS_CA_NAME}.crt")
    let ca_key_var = ($dockerfile_text | str contains "TLS_CA_NAME}.key")

    # Fail-closed: CA path + TLS_CA_NAME variable referenced but no explicit
    # .crt or .key extension found means we cannot determine what to stage.
    let has_ca_path = ($dockerfile_text | str contains "certificate-authority/")
    let has_tls_ca_name_var = ($dockerfile_text | str contains "TLS_CA_NAME")
    let has_any_crt = ($ca_crt_literal or $ca_crt_var)
    let has_any_key = ($ca_key_literal or $ca_key_var)

    if $has_ca_path and $has_tls_ca_name_var and not $has_any_crt and not $has_any_key {
        error make {msg: (
            "detect-ca-requirements: Dockerfile references 'certificate-authority/' " +
            "and 'TLS_CA_NAME' but contains no explicit .crt or .key extension.\n" +
            "Add at least one of the following so CA staging can be deterministic:\n" +
            "  certificate-authority/${TLS_CA_NAME}.crt\n" +
            "  certificate-authority/${TLS_CA_NAME}.key"
        )}
    }

    let needs_ca_crt = ($copies_tls_broad or $ca_crt_literal or $ca_crt_var)
    let needs_ca_key = ($ca_key_literal or $ca_key_var)

    {needs_ca_crt: $needs_ca_crt, needs_ca_key: $needs_ca_key}
}

# Stage CA certificate (and optionally key) into the build context just-in-time.
# Returns a record describing what was created so cleanup-ca-context can remove it.
export def prepare-ca-context [
    context: string,
    tls_meta: record,      # {enabled, mode, cert_name, ca_name}
    ca_reqs: record        # {needs_ca_crt, needs_ca_key}
] {
    if not $ca_reqs.needs_ca_crt and not $ca_reqs.needs_ca_key {
        return {staged_dir: false, files: []}
    }

    let ca_name = $tls_meta.ca_name
    let ca_dir_src = "tls/certificate-authority"
    let ca_dir_ctx = $"($context)/tls/certificate-authority"

    mkdir $ca_dir_ctx

    mut staged_files = []

    if $ca_reqs.needs_ca_crt {
        let src = $"($ca_dir_src)/($ca_name).crt"
        if not ($src | path exists) {
            error make {msg: $"CA cert not found: ($src). Run 'nu scripts/dockypody.nu tls ca' first"}
        }
        cp -f $src $"($ca_dir_ctx)/($ca_name).crt"
        $staged_files = ($staged_files | append $"($ca_name).crt")
        print $"Staged CA cert into build context: tls/certificate-authority/($ca_name).crt"
    }

    if $ca_reqs.needs_ca_key {
        let src = $"($ca_dir_src)/($ca_name).key"
        if not ($src | path exists) {
            error make {msg: $"CA key not found: ($src). Run 'nu scripts/dockypody.nu tls ca' first"}
        }
        cp -f $src $"($ca_dir_ctx)/($ca_name).key"
        $staged_files = ($staged_files | append $"($ca_name).key")
        print $"Staged CA key into build context: tls/certificate-authority/($ca_name).key"
    }

    {staged_dir: true, files: $staged_files}
}

# Remove CA material staged by prepare-ca-context.
export def cleanup-ca-context [
    context: string,
    ca_context: record  # returned by prepare-ca-context
] {
    if not $ca_context.staged_dir {
        return
    }

    let ca_dir_ctx = $"($context)/tls/certificate-authority"

    # Remove the entire staged directory regardless of leftover files.
    try { rm -rf $ca_dir_ctx } catch { }
    # Remove the tls dir only if it exists and is now empty.
    let tls_dir = $"($context)/tls"
    if ($tls_dir | path exists) and ((ls $tls_dir | length) == 0) {
        rmdir $tls_dir
    }
    print "Cleaned up staged CA material from build context"
}
