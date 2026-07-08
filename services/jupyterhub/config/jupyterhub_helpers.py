# SPDX-License-Identifier: AGPL-3.0-or-later
# Pure helpers for jupyterhub_config.py. Importable without JupyterHub runtime.

import os
from urllib.parse import urlparse


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable {name} is unset")
    return value


def normalize_jupyter_host_bare(host: str) -> str:
    """Return bare hostname for upstream OAuth callback construction.

    The hub binds HTTPS on port 443 only. ``JUPYTER_HOST`` must name that
    public endpoint; explicit ``:443`` is accepted but stripped so OAuth and
    ``public_url`` never advertise a port.

    SUNET apply_defaults builds oauth_callback as
    ``https://`` + ``os.environ['JUPYTER_HOST']`` + ``/hub/oauth_callback``.
    Strip any ``https://`` prefix so that path is never doubled.
    """
    trimmed = host.strip().rstrip("/")
    if trimmed.startswith("http://"):
        raise ValueError(
            "JUPYTER_HOST must use https:// or a bare hostname; "
            "http:// is not allowed for this TLS-owning service"
        )
    if trimmed.startswith("https://"):
        trimmed = trimmed[len("https://") :].rstrip("/")

    if not trimmed:
        raise ValueError("JUPYTER_HOST must be a non-empty hostname")

    parsed = urlparse("https://" + trimmed)
    hostname = parsed.hostname
    port = parsed.port

    if not hostname:
        raise ValueError("JUPYTER_HOST must be a valid hostname")

    if port is not None and port != 443:
        raise ValueError(
            f"JUPYTER_HOST must not include a non-443 port (got :{port}); "
            "the hub binds HTTPS on port 443 only"
        )

    return hostname


def public_url_from_jupyter_host(host: str) -> str:
    return "https://" + normalize_jupyter_host_bare(host)


def oauth_callback_url_from_jupyter_host(host: str) -> str:
    bare = normalize_jupyter_host_bare(host)
    return f"https://{bare}/hub/oauth_callback"


def resolve_tls_paths(
    cert_name: str,
    cert_path: str,
    key_path: str,
    tls_dir: str = "/tls",
) -> tuple[str, str]:
    cert = cert_path.strip() if cert_path else ""
    key = key_path.strip() if key_path else ""

    if not cert:
        if not cert_name:
            raise RuntimeError(
                "TLS is required: DOCKYPODY_TLS_CERT_NAME is unset "
                "and JUPYTERHUB_SSL_CERT is unset"
            )
        cert = os.path.join(tls_dir, f"{cert_name}.crt")

    if not key:
        if not cert_name:
            raise RuntimeError(
                "TLS is required: DOCKYPODY_TLS_CERT_NAME is unset "
                "and JUPYTERHUB_SSL_KEY is unset"
            )
        key = os.path.join(tls_dir, f"{cert_name}.key")

    require_tls_file(cert, "JUPYTERHUB_SSL_CERT")
    require_tls_file(key, "JUPYTERHUB_SSL_KEY")

    return cert, key


def require_tls_file(path: str, label: str) -> None:
    if not path:
        raise RuntimeError(f"TLS is required: {label} is unset")
    if not os.path.isfile(path):
        raise RuntimeError(f"TLS is required: {label} not found at {path}")
