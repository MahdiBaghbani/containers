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
use ../ssh/lib.nu [read-ssh-metadata]

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
    if ($tls_scripts_dir | path exists) and ((ls -a $tls_scripts_dir | length) == 0) {
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
    if ($tls_dir | path exists) and ((ls -a $tls_dir | length) == 0) {
        rmdir $tls_dir
    }
    print "Cleaned up staged CA material from build context"
}

# SSH metadata extraction
export def extract-ssh-metadata [
    cfg: record
] {
    let ssh_enabled = (try { $cfg.ssh.enabled | default false } catch { false })

    let ssh_mode = (if $ssh_enabled {
        let mode_raw = (try { $cfg.ssh.mode } catch { "" })
        if ($mode_raw | str trim | is-empty) {
            error make {msg: "ssh.mode is required when ssh.enabled=true (validation should have caught this)"}
        }
        $mode_raw
    } else {
        "disabled"
    })

    # default_user priority: cfg.ssh.default_user -> ssh/ssh.json.default_user -> "root"
    let ssh_json = (try { read-ssh-metadata } catch { null })
    let fallback_user = if $ssh_json != null {
        $ssh_json.default_user? | default "root"
    } else {
        "root"
    }
    let ssh_default_user = (try { $cfg.ssh.default_user | default $fallback_user } catch { $fallback_user })

    let ssh_port = (try { $cfg.ssh.port | default 22 } catch { 22 })
    let ssh_listen = (try { $cfg.ssh.listen | default "0.0.0.0" } catch { "0.0.0.0" })

    {
        enabled: $ssh_enabled,
        mode: $ssh_mode,
        default_user: $ssh_default_user,
        port: $ssh_port,
        listen: $ssh_listen
    }
}

# Prepare SSH build context - stage key material into build context.
# Staging is mode-gated so the private key is never baked into server images:
#   server            -> public key only (+ known_hosts if present)
#   client            -> private + public (+ known_hosts if present)
#   client-and-server -> private + public (+ known_hosts if present)
# Always creates the ssh directory so Dockerfile COPY ./ssh/ never fails,
# regardless of whether SSH is enabled.
# Returns {dir_created: bool, copied: bool, files: list<string>, sshd_module_staged: bool}.
export def prepare-ssh-context [
    service: string,
    context: string,
    ssh_enabled: bool,
    ssh_mode: string
] {
    let ssh_src = "ssh"
    let ssh_dest = $"($context)/ssh"

    # Always create the ssh directory so Dockerfile COPY ./ssh/ never fails.
    mkdir $ssh_dest

    # Stage ssh.json if present so sshd.nu can read key_name at container runtime.
    let ssh_json_src = $"($ssh_src)/ssh.json"
    if ($ssh_json_src | path exists) {
        cp $ssh_json_src $"($ssh_dest)/ssh.json"
        print "Staged ssh.json into build context"
    }

    # Always stage the shared sshd runtime module so Dockerfile
    # COPY ./scripts/lib/sshd.nu never fails.
    let sshd_module_src = "scripts/lib/ssh/sshd.nu"
    if not ($sshd_module_src | path exists) {
        error make {
            msg: ($"sshd shared module not found: ($sshd_module_src)\n\n" +
                  "This script is required for Dockerfile COPY ./scripts/lib/sshd.nu.\n" +
                  "The file should be located at scripts/lib/ssh/sshd.nu.\n\n")
        }
    }
    mkdir $"($context)/scripts/lib"
    cp $sshd_module_src $"($context)/scripts/lib/sshd.nu"
    print "Staged sshd shared module into build context: scripts/lib/sshd.nu"

    if not $ssh_enabled {
        return {dir_created: true, copied: false, files: [], sshd_module_staged: true}
    }

    if ($ssh_mode | str trim | is-empty) or $ssh_mode == "disabled" {
        error make {msg: "ssh_mode parameter is required when ssh_enabled=true. This is a build system bug."}
    }

    # Resolve key_name from ssh.json (fallback: "dockypody").
    let ssh_meta = (try { read-ssh-metadata $ssh_src } catch { null })
    let key_name = if $ssh_meta != null {
        $ssh_meta.key_name? | default "dockypody"
    } else {
        "dockypody"
    }

    mut staged_files = []

    let private_key = $"($ssh_src)/($key_name)"
    let public_key  = $"($ssh_src)/($key_name).pub"

    if $ssh_mode == "server" {
        # Server mode: stage only the public key. Never stage the private key -
        # doing so risks baking it into the image layer.
        if ($public_key | path exists) {
            cp $public_key $"($ssh_dest)/($key_name).pub"
            $staged_files = ($staged_files | append $"($key_name).pub")
            print $"Staged SSH public key for ($service)"
        } else {
            print $"WARNING: SSH public key not found at ($public_key). SSH server authorization may fail."
        }
    } else {
        # client / client-and-server: stage the full keypair.
        if ($private_key | path exists) {
            cp $private_key $"($ssh_dest)/($key_name)"
            cp $public_key $"($ssh_dest)/($key_name).pub"
            $staged_files = ($staged_files | append [$"($key_name)" $"($key_name).pub"])
            print $"Staged SSH keypair for ($service)"
        } else {
            print $"WARNING: SSH keypair not found at ($private_key). SSH connections may fail."
        }
    }

    let known_hosts = $"($ssh_src)/known_hosts"
    if ($known_hosts | path exists) {
        cp $known_hosts $"($ssh_dest)/known_hosts"
        $staged_files = ($staged_files | append "known_hosts")
    }

    let has_files = (($staged_files | length) > 0)
    {dir_created: true, copied: $has_files, files: $staged_files, sshd_module_staged: true}
}

# Cleanup SSH build context.
# Removes the staged ssh directory and the shared sshd module unconditionally
# when the context was created, so the build context is always clean afterward.
export def cleanup-ssh-context [
    context: string,
    ssh_context: record
] {
    let dir_was_created = ($ssh_context.dir_created? | default $ssh_context.copied)
    if not $dir_was_created {
        return
    }

    let ssh_dir = $"($context)/ssh"
    try { rm -rf $ssh_dir } catch { }

    # Remove the staged sshd shared module and empty parent dirs.
    let sshd_module = $"($context)/scripts/lib/sshd.nu"
    try { rm -f $sshd_module } catch { }
    let lib_dir = $"($context)/scripts/lib"
    if ($lib_dir | path exists) and ((ls -a $lib_dir | length) == 0) {
        try { rmdir $lib_dir } catch { }
    }
    let scripts_dir = $"($context)/scripts"
    if ($scripts_dir | path exists) and ((ls -a $scripts_dir | length) == 0) {
        try { rmdir $scripts_dir } catch { }
    }

    print "Cleaned up staged SSH material from build context"
}

# Detect whether the Dockerfile copies the shared clone-source helper into
# the build context. Matches non-comment COPY lines that stage
# ./scripts/lib/clone-source.nu from the build context, for example:
#   COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu
export def detect-clone-source-requirements [
    dockerfile_text: string,
] {
    let helper_path = "./scripts/lib/clone-source.nu"
    let needs = (
        $dockerfile_text
        | lines
        | any {|line|
            let stripped = ($line | str trim)
            if ($stripped | is-empty) or ($stripped | str starts-with "#") {
                false
            } else {
                (($stripped | str upcase | str starts-with "COPY")
                    and ($line | str contains $helper_path))
            }
        }
    )
    {needs_clone_helper: $needs}
}

# Stage the shared clone-source helper into the build context just-in-time.
# Returns {staged: bool, files: list<string>} for cleanup-clone-source-context.
export def prepare-clone-source-context [
    service: string,
    context: string,
    clone_reqs: record,  # {needs_clone_helper: bool} from detect-clone-source-requirements
] {
    if not ($clone_reqs.needs_clone_helper? | default false) {
        return {staged: false, files: []}
    }

    let helper_src = "scripts/lib/build/clone-source.nu"
    if not ($helper_src | path exists) {
        error make {
            msg: ($"clone-source helper not found: ($helper_src)\n\n" +
                  "This script is required for Dockerfile COPY ./scripts/lib/clone-source.nu.\n" +
                  "The file should be located at scripts/lib/build/clone-source.nu.\n\n")
        }
    }

    mkdir $"($context)/scripts/lib"
    cp $helper_src $"($context)/scripts/lib/clone-source.nu"
    print $"Staged clone-source helper into build context for ($service): scripts/lib/clone-source.nu"
    {staged: true, files: ["clone-source.nu"]}
}

# Remove clone-source helper staged by prepare-clone-source-context.
export def cleanup-clone-source-context [
    context: string,
    clone_context: record,
] {
    if not ($clone_context.staged? | default false) {
        return
    }

    let helper_path = $"($context)/scripts/lib/clone-source.nu"
    try { rm -f $helper_path } catch { }

    let lib_dir = $"($context)/scripts/lib"
    if ($lib_dir | path exists) and ((ls -a $lib_dir | length) == 0) {
        try { rmdir $lib_dir } catch { }
    }
    let scripts_dir = $"($context)/scripts"
    if ($scripts_dir | path exists) and ((ls -a $scripts_dir | length) == 0) {
        try { rmdir $scripts_dir } catch { }
    }

    print "Cleaned up staged clone-source helper from build context"
}
