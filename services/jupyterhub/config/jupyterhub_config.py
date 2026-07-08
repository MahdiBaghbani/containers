# SPDX-License-Identifier: AGPL-3.0-or-later
# Baked reference config for the OCM webapp-share JupyterHub image.
# Derived from the SUNET reference at hub/example/jupyterhub_config.py in
# nextcloud-integration_jupyterhub. Values come from the environment so the OCM
# Test Suite compose (or any operator) can wire the paired Nextcloud and hub
# hosts without editing the image.
#
# Required environment (read at hub startup), see the hub/ package README:
#     NEXTCLOUD_HOST, NEXTCLOUD_CLIENT_ID, NEXTCLOUD_CLIENT_SECRET,
#     JUPYTER_HOST, JUPYTERHUB_CRYPT_KEY,
#     OCM_TRUSTED_BACK_CHANNEL_DOMAINS, OCM_TRUSTED_ISSUER_DOMAINS

import os

from nextcloud_ocm_jupyterhub.config import apply_defaults

apply_defaults(c)  # noqa: F821 - c is injected by JupyterHub

# MVP spawner: SimpleSpawner terminates the launch at /lab without a notebook
# image. Layer 3 (real notebook render + WebDAV sync) is deferred; swap to
# DockerSpawner + a singleuser image when that lands.
c.JupyterHub.spawner_class = "simple"  # noqa: F821
c.Spawner.default_url = "/lab"  # noqa: F821
c.Spawner.args = ["--allow-root"]  # noqa: F821

c.Authenticator.auto_login = True  # noqa: F821
c.JupyterHub.bind_url = "http://:8000"  # noqa: F821
c.JupyterHub.allow_named_servers = True  # noqa: F821
c.JupyterHub.public_url = "https://" + os.environ["JUPYTER_HOST"]  # noqa: F821

# The hub is iframed / cross-site during the OCM handoff; SameSite=None cookies
# survive the cross-site OAuth callback redirect.
c.JupyterHub.tornado_settings = {  # noqa: F821
    "headers": {"Content-Security-Policy": "frame-ancestors *;"},
    "cookie_options": {"samesite": "None", "secure": True},
}

c.CryptKeeper.keys = [os.environ["JUPYTERHUB_CRYPT_KEY"]]  # noqa: F821
