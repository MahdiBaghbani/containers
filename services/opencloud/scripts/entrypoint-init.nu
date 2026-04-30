#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images

# OpenCloud entrypoint init: ship default configs and fix ownership before hand-off.
# sshd module is staged flat into the image at /usr/bin/lib/sshd.nu during Docker build.
# ocmproviders module staged flat at /usr/bin/lib/ocmproviders.nu during Docker build.

use /usr/bin/lib/sshd.nu [start-sshd-if-enabled]
use /usr/bin/lib/ocmproviders.nu [has-indexed-providers generate-ocmproviders]

const TEMPLATE_DIR        = "/opt/dockypody/templates/opencloud"
const CONFIG_DIR          = "/etc/opencloud"
const STATE_DIR           = "/var/lib/opencloud"
const ASSETS_DIR          = "/var/lib/opencloud/web/assets/apps"
const PROVIDERS_DEFAULT   = "/etc/opencloud/ocmproviders.json"
const OPENCLOUD_CONFIG_FILE = "/etc/opencloud/opencloud.yaml"

# ocmproviders.json is handled with explicit precedence below; only generic
# templates remain in CONFIG_FILES.
const CONFIG_FILES = ["web-ui-config.json"]

# Copy $src to $dst only when $dst does not already exist.
def ship-if-missing [src: string, dst: string] {
    if not ($dst | path exists) {
        print $"[entrypoint-init] shipping default ($dst)"
        ^cp $src $dst
    }
}

# Handle ocmproviders.json with three-level precedence:
#   1. OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE set  -> validate path exists, use verbatim
#   2. env unset, OCM_PROVIDER_0_DOMAIN present        -> generate to default path
#   3. env unset, no indexed providers                 -> copy template as fallback
def handle-ocmproviders [] {
    let explicit = ($env.OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE? | default "" | str trim)
    if not ($explicit | is-empty) {
        if not ($explicit | path exists) {
            error make {msg: $"[entrypoint-init] OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE path does not exist: ($explicit)"}
        }
        print $"[entrypoint-init] ocmproviders: explicit file mode path=($explicit)"
        return
    }
    if (has-indexed-providers) {
        print "[entrypoint-init] ocmproviders: generate mode"
        generate-ocmproviders $PROVIDERS_DEFAULT
        return
    }
    ship-if-missing $"($TEMPLATE_DIR)/ocmproviders.json" $PROVIDERS_DEFAULT
}

# Resolve admin password with four-level precedence:
#   OPENCLOUD_ADMIN_PASSWORD  - public DockyPody wrapper var
#   ADMIN_PASSWORD            - upstream-compatible fallback (not public example contract)
#   IDM_ADMIN_PASSWORD        - upstream-compatible fallback (not public example contract)
#   "admin"                   - compiled-in default
def resolve-opencloud-admin-password [] {
    let p1 = ($env.OPENCLOUD_ADMIN_PASSWORD? | default "" | str trim)
    if not ($p1 | is-empty) { return $p1 }
    let p2 = ($env.ADMIN_PASSWORD? | default "" | str trim)
    if not ($p2 | is-empty) { return $p2 }
    let p3 = ($env.IDM_ADMIN_PASSWORD? | default "" | str trim)
    if not ($p3 | is-empty) { return $p3 }
    "admin"
}

# Run `opencloud init` when OPENCLOUD_INIT=true. Idempotent: skips init when
# the generated config already exists so repeated container restarts on a
# persisted config volume do not trigger spurious init failures.
# Real init failures are printed as warnings; the script still exits 0.
# Only runs when the flag is explicitly "true"; unset or any other value is a
# no-op so existing deployments are unaffected.
def maybe-bootstrap-opencloud [] {
    let flag = ($env.OPENCLOUD_INIT? | default "" | str downcase | str trim)
    if $flag != "true" { return }
    if ($OPENCLOUD_CONFIG_FILE | path exists) {
        print $"[entrypoint-init] OPENCLOUD_INIT=true: config already exists at ($OPENCLOUD_CONFIG_FILE), skipping init"
        return
    }
    let pw = resolve-opencloud-admin-password
    print "[entrypoint-init] OPENCLOUD_INIT=true: running opencloud init"
    try {
        ^opencloud init --insecure true --admin-password $pw
    } catch {|err|
        print $"WARNING: [entrypoint-init] opencloud init failed, ignoring: ($err.msg)"
    }
}

def --wrapped main [...args] {
    try {
        start-sshd-if-enabled
    } catch {|err|
        print $"WARNING: [entrypoint-init] sshd start failed, continuing: ($err.msg)"
    }

    # Ensure config, state, and web-assets dirs exist.
    ^mkdir -p $CONFIG_DIR $STATE_DIR $ASSETS_DIR

    # Providers file: explicit-file > generate > template fallback.
    handle-ocmproviders

    # Ship remaining default templates when no user-provided file is mounted.
    for name in $CONFIG_FILES {
        ship-if-missing $"($TEMPLATE_DIR)/($name)" $"($CONFIG_DIR)/($name)"
    }

    # Optional bootstrap: runs opencloud init when OPENCLOUD_INIT=true.
    maybe-bootstrap-opencloud

    # Hand ownership to the non-root runtime uid:gid (1000:1000).
    ^chown -R 1000:1000 $CONFIG_DIR $STATE_DIR $ASSETS_DIR
}
