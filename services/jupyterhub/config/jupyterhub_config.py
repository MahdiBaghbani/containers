# SPDX-License-Identifier: AGPL-3.0-or-later
# Baked reference config for the OCM webapp-share JupyterHub image.
# Derived from the SUNET reference at hub/example/jupyterhub_config.py in
# nextcloud-integration_jupyterhub. Values come from the environment so the OCM
# Test Suite compose (or any operator) can wire the paired Nextcloud and hub
# hosts without editing the image.
#
# Required environment (read at hub startup), see the hub/ package README:
#     NEXTCLOUD_HOST, JUPYTERHUB_API_KEY, JUPYTERHUB_OCM_API_KEY,
#     JUPYTER_HOST, JUPYTERHUB_CRYPT_KEY,
#     OCM_TRUSTED_BACK_CHANNEL_DOMAINS, OCM_TRUSTED_ISSUER_DOMAINS
# NEXTCLOUD_CLIENT_ID / NEXTCLOUD_CLIENT_SECRET are read directly from the env
# when set; otherwise they are resolved from the OAuth handoff file named by
# NEXTCLOUD_OAUTH_ENV_FILE (written by the sender Nextcloud). entrypoint-init.nu
# waits for that file before this config runs.
# TLS defaults come from DOCKYPODY_TLS_CERT_NAME -> /tls/<name>.{crt,key};
# JUPYTERHUB_SSL_CERT / JUPYTERHUB_SSL_KEY are optional explicit overrides.

import os
import sys

# Traitlets/JupyterHub config execution does not add this file's directory to
# sys.path; helpers live alongside this config in /srv/jupyterhub at runtime.
_config_dir = os.path.dirname(os.path.abspath(__file__))
if _config_dir not in sys.path:
    sys.path.insert(0, _config_dir)

from jupyterhub_helpers import (  # noqa: E402
    normalize_jupyter_host_bare,
    oauth_callback_url_from_jupyter_host,
    public_url_from_jupyter_host,
    require_env,
    resolve_oauth_client,
    resolve_tls_paths,
)

for _name in [
    "NEXTCLOUD_HOST",
    "JUPYTERHUB_API_KEY",
    "JUPYTERHUB_OCM_API_KEY",
    "JUPYTERHUB_CRYPT_KEY",
    "OCM_TRUSTED_BACK_CHANNEL_DOMAINS",
    "OCM_TRUSTED_ISSUER_DOMAINS",
]:
    require_env(_name)

# SUNET apply_defaults reads NEXTCLOUD_CLIENT_ID/SECRET from os.environ. Resolve
# them from the env or the sender's OAuth handoff file and re-export so the
# authenticator wiring below sees concrete values.
_client_id, _client_secret = resolve_oauth_client(
    os.environ.get("NEXTCLOUD_CLIENT_ID", ""),
    os.environ.get("NEXTCLOUD_CLIENT_SECRET", ""),
    os.environ.get("NEXTCLOUD_OAUTH_ENV_FILE", ""),
)
os.environ["NEXTCLOUD_CLIENT_ID"] = _client_id
os.environ["NEXTCLOUD_CLIENT_SECRET"] = _client_secret

# SUNET apply_defaults reads JUPYTER_HOST from os.environ when building the
# OAuth callback URL. Normalize to bare hostname (HTTPS/443 only) first so
# https:// + JUPYTER_HOST never becomes https://https://...
_jupyter_host_bare = normalize_jupyter_host_bare(require_env("JUPYTER_HOST"))
os.environ["JUPYTER_HOST"] = _jupyter_host_bare

from nextcloud_ocm_jupyterhub.config import apply_defaults  # noqa: E402

apply_defaults(c)  # noqa: F821 - c is injected by JupyterHub

# MVP spawner: SimpleSpawner terminates the launch at /lab without a notebook
# image. Layer 3 (real notebook render + WebDAV sync) is deferred; swap to
# DockerSpawner + a singleuser image when that lands.
c.JupyterHub.spawner_class = "simple"  # noqa: F821
c.Spawner.default_url = "/lab"  # noqa: F821
c.Spawner.args = ["--allow-root"]  # noqa: F821

c.Authenticator.auto_login = True  # noqa: F821
c.JupyterHub.allow_named_servers = True  # noqa: F821

_ssl_cert, _ssl_key = resolve_tls_paths(
    os.environ.get("DOCKYPODY_TLS_CERT_NAME", "").strip(),
    os.environ.get("JUPYTERHUB_SSL_CERT", ""),
    os.environ.get("JUPYTERHUB_SSL_KEY", ""),
)

c.JupyterHub.bind_url = "https://:443"  # noqa: F821
c.JupyterHub.ssl_cert = _ssl_cert  # noqa: F821
c.JupyterHub.ssl_key = _ssl_key  # noqa: F821

c.NextcloudOAuthenticator.oauth_callback_url = oauth_callback_url_from_jupyter_host(  # noqa: F821
    _jupyter_host_bare
)
c.JupyterHub.public_url = public_url_from_jupyter_host(_jupyter_host_bare)  # noqa: F821

# The hub is iframed / cross-site during the OCM handoff; SameSite=None cookies
# survive the cross-site OAuth callback redirect.
c.JupyterHub.tornado_settings = {  # noqa: F821
    "headers": {"Content-Security-Policy": "frame-ancestors *;"},
    "cookie_options": {"samesite": "None", "secure": True},
}

c.CryptKeeper.keys = [require_env("JUPYTERHUB_CRYPT_KEY")]  # noqa: F821
