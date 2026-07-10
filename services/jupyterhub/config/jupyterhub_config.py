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

# JupyterHub builds managed-service subprocess environments from a whitelist
# (Spawner.env_keep) plus injected JUPYTERHUB_* vars; the container's custom env
# is NOT inherited (this is why apply_services_defaults already forwards the OCM
# allowlists per-service). Both managed services make outbound HTTPS calls that
# must trust the workspace CA: `ocm` fetches the sender's JWKS (PyJWKClient) to
# verify OCM signatures, and `refresh-token` refreshes OAuth tokens against
# Nextcloud. Forward the image's TLS trust env into each service's environment
# so peer verification uses the workspace CA instead of failing with
# CERTIFICATE_VERIFY_FAILED. The image ENV is the single source of truth for the
# bundle path; NODE_EXTRA_CA_CERTS is intentionally excluded (the Python
# services do not use Node; the configurable-http-proxy inherits it directly
# from the container env).
_ca_trust_env = {
    _key: os.environ[_key]
    for _key in ("SSL_CERT_FILE", "SSL_CERT_DIR")
    if os.environ.get(_key)
}
if _ca_trust_env:
    for _service in getattr(c.JupyterHub, "services", []) or []:  # noqa: F821
        _service.setdefault("environment", {}).update(_ca_trust_env)

# MVP spawner: SimpleLocalProcessSpawner execs jupyterhub-singleuser as the hub
# user and lands the OCM user in JupyterLab (/lab); the image bundles jupyterlab
# so the single-user server can start. Layer 3 (per-user isolation via
# DockerSpawner + a dedicated singleuser image, WebDAV sync) is deferred; swap to
# DockerSpawner + a singleuser image when that lands.
c.JupyterHub.spawner_class = "simple"  # noqa: F821
c.Spawner.default_url = "/lab"  # noqa: F821
c.Spawner.args = ["--allow-root"]  # noqa: F821

# SimpleLocalProcessSpawner builds the single-user env from Spawner.env_keep
# (plus injected JUPYTERHUB_* and Spawner.environment); the container ENV is not
# inherited. ocm-sync runs at Lab startup and fetches the shared folder from the
# sender over HTTPS, so it must trust the workspace CA. Forward the image's CA
# trust vars into the single-user environment; without this, requests falls back
# to certifi and fails with CERTIFICATE_VERIFY_FAILED.
from jupyterhub.spawner import SimpleLocalProcessSpawner as _SimpleSpawner  # noqa: E402

# env_keep has a dynamic, spawner-class-specific default: the base Spawner
# default omits PATH, but SimpleLocalProcessSpawner (spawner_class="simple")
# adds PATH/PYTHONPATH/etc, which the exec of jupyterhub-singleuser needs.
# Derive the base from the concrete spawner class so we never drop PATH, then
# append the CA trust vars. Preserve any list a prior config already set.
_existing_env_keep = c.Spawner.env_keep  # noqa: F821
_base_env_keep = (
    list(_existing_env_keep)
    if isinstance(_existing_env_keep, (list, tuple))
    else list(_SimpleSpawner().env_keep)
)
c.Spawner.env_keep = _base_env_keep + [  # noqa: F821
    _key
    for _key in ("SSL_CERT_FILE", "SSL_CERT_DIR", "REQUESTS_CA_BUNDLE")
    if os.environ.get(_key) and _key not in _base_env_keep
]

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
