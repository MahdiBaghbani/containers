# SPDX-License-Identifier: AGPL-3.0-or-later
# System-wide single-user (jupyter_server) config, read by every server that
# SimpleLocalProcessSpawner execs. The hub itself reads jupyterhub_config.py,
# not this file, so these settings only affect spawned Lab servers.

import os

c = get_config()  # noqa: F821 -- injected by jupyter_server

# Allow the receiver EFSS to embed / cross-origin the launched Lab, matching
# the upstream SUNET singleuser config.
c.ServerApp.allow_origin = "*"
c.ServerApp.tornado_settings = {
    "headers": {"Content-Security-Policy": "frame-ancestors *;"},
}

# OCM share servers pull the shared folder over WebDAV before Lab serves, so
# the file browser shows the shared notebook. Regular (non-OCM) spawns skip it.
if os.environ.get("OCM_WEBDAV_URI"):
    os.system("/usr/local/bin/ocm-sync")
