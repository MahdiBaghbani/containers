#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images

# OpenCloud entrypoint init: ship default configs and fix ownership before hand-off.
# sshd module is staged flat into the image at /usr/bin/lib/sshd.nu during Docker build.

use /usr/bin/lib/sshd.nu [start-sshd-if-enabled]

const TEMPLATE_DIR = "/opt/dockypody/templates/opencloud"
const CONFIG_DIR   = "/etc/opencloud"
const STATE_DIR    = "/var/lib/opencloud"
const ASSETS_DIR   = "/var/lib/opencloud/web/assets/apps"

const CONFIG_FILES = ["ocmproviders.json" "web-ui-config.json"]

# Copy $src to $dst only when $dst does not already exist.
def ship-if-missing [src: string, dst: string] {
    if not ($dst | path exists) {
        print $"[entrypoint-init] shipping default ($dst)"
        ^cp $src $dst
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

    # Ship default templates when no user-provided file is mounted.
    for name in $CONFIG_FILES {
        ship-if-missing $"($TEMPLATE_DIR)/($name)" $"($CONFIG_DIR)/($name)"
    }

    # Hand ownership to the non-root runtime uid:gid (1000:1000).
    ^chown -R 1000:1000 $CONFIG_DIR $STATE_DIR $ASSETS_DIR
}
