# syntax=docker/dockerfile:1.7

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
#
# JupyterHub runtime that terminates the OCM webapp-share launch:
#   POST /services/ocm/open -> hub authenticator handoff -> 302 .../lab
# The nextcloud-ocm-jupyterhub package (authenticator + ocm/refresh-token
# managed services) lives in the hub/ subdir of the same upstream repo as the
# integration_jupyterhub Nextcloud app; it is cloned and pinned via
# versions.nuon (repoint to a fork to own the source). Base tag is wired via
# platforms.nuon + versions.nuon (external_images.runtime).
#
# Base is the all-in-one `quay.io/jupyterhub/jupyterhub` image, which bundles
# JupyterHub + Node + configurable-http-proxy in one container. That matches our
# deployment shape (single container per role, in-hub TLS on :443, local
# SimpleSpawner). The Zero-to-K8s `k8s-hub` image is deliberately NOT used: it
# expects an external proxy pod and omits the proxy binary, so JupyterHub's
# default local ConfigurableHTTPProxy cannot start there.

ARG BASE_HUB_IMAGE="quay.io/jupyterhub/jupyterhub:5.3.0"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

ARG INTEGRATION_JUPYTERHUB_URL="https://github.com/SUNET/nextcloud-integration_jupyterhub"
ARG INTEGRATION_JUPYTERHUB_REF="main"
ARG INTEGRATION_JUPYTERHUB_SHA=""
ARG INTEGRATION_JUPYTERHUB_REF_KIND=""
ARG INTEGRATION_JUPYTERHUB_PATH=""
ARG INTEGRATION_JUPYTERHUB_MODE=""
ARG CACHEBUST="default"

##########################
###   Source Prepare   ###
##########################
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare

WORKDIR /

ARG INTEGRATION_JUPYTERHUB_URL
ARG INTEGRATION_JUPYTERHUB_REF
ARG INTEGRATION_JUPYTERHUB_SHA
ARG INTEGRATION_JUPYTERHUB_REF_KIND
ARG INTEGRATION_JUPYTERHUB_PATH
ARG INTEGRATION_JUPYTERHUB_MODE
ARG CACHEBUST

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

# Clone or copy integration_jupyterhub source via shared helper (local bind mount or git cache).
RUN --mount=type=cache,id=integration-jupyterhub-git-${CACHEBUST:-${INTEGRATION_JUPYTERHUB_REF}},target=/src/integration-jupyterhub-git-cache,sharing=shared \
    --mount=type=bind,source=${INTEGRATION_JUPYTERHUB_PATH:-.},target=/src/local-integration-jupyterhub,ro \
    nu /tmp/clone-source.nu \
    --mode "${INTEGRATION_JUPYTERHUB_MODE:-git}" \
    --url "${INTEGRATION_JUPYTERHUB_URL}" \
    --ref "${INTEGRATION_JUPYTERHUB_REF}" \
    --ref-kind "${INTEGRATION_JUPYTERHUB_REF_KIND}" \
    --local-dir /src/local-integration-jupyterhub \
    --cache-dir /src/integration-jupyterhub-git-cache \
    --dest /integration-jupyterhub-raw

# Ship only the hub/ python package; the sibling Nextcloud app subdir is baked
# into the nextcloud-webapp image instead.
RUN if [ ! -d /integration-jupyterhub-raw/hub ]; then \
      echo "Error: hub/ package missing at /integration-jupyterhub-raw/hub" >&2; \
      exit 1; \
    fi && \
    mkdir -p /hub-source && \
    cp -a /integration-jupyterhub-raw/hub/. /hub-source/ && \
    rm -rf /integration-jupyterhub-raw

# Drop the upstream container recipe; our Dockerfile + config own the build.
RUN rm -rf /hub-source/.git /hub-source/.github && \
    rm -f /hub-source/Dockerfile /hub-source/.gitignore

###############################
###       Common Tools      ###
###############################
FROM ${COMMON_TOOLS_IMAGE} AS common-tools

###################
###   Runtime   ###
###################
FROM ${BASE_HUB_IMAGE}

ARG TLS_ENABLED
ARG TLS_MODE
ARG TLS_CERT_NAME
ARG TLS_CA_NAME
ARG COMMON_TOOLS_IMAGE

USER root

# Fail the build early if the base ever stops bundling the local proxy. This is
# the exact defect that broke the k8s-hub base: JupyterHub's default proxy tries
# to exec `configurable-http-proxy` locally, so it must exist in the image.
RUN configurable-http-proxy --version

# The all-in-one jupyterhub base runs as root and ships no UID 1000 user (unlike
# k8s-hub, which pre-provisioned jovyan=1000). Create the unprivileged runtime
# user and hand it the hub state dir (WORKDIR /srv/jupyterhub holds the sqlite DB
# and cookie secret) so the hub runs as UID 1000 under the NET_BIND_SERVICE :443
# contract asserted below.
RUN useradd --uid 1000 --user-group --create-home --home-dir /home/jovyan --shell /bin/bash jovyan \
    && chown -R 1000:1000 /srv/jupyterhub
ENV HOME=/home/jovyan

# Install the authenticator + OCM services package plus a single-user server.
# spawner_class = "simple" (SimpleLocalProcessSpawner) execs `jupyterhub-singleuser`,
# which needs jupyter_server + a frontend; jupyterlab provides both and backs the
# baked config's Spawner.default_url = "/lab". The all-in-one jupyterhub base ships
# only the hub, so without this the OCM launch handoff spawns a named server that
# dies with ModuleNotFoundError: jupyter_server and /services/ocm/open returns 502.
COPY --from=source-prepare /hub-source /tmp/hub
RUN pip install --no-cache-dir /tmp/hub jupyterhub-simplespawner "jupyterlab>=4.2,<5" \
    && rm -rf /tmp/hub

# Fail the build early if the single-user server stack is ever missing again:
# SimpleSpawner execs `jupyterhub-singleuser`, which imports jupyter_server and the
# jupyterlab frontend to serve Spawner.default_url = "/lab".
RUN python3 -c "import jupyter_server, jupyterlab, jupyterhub.singleuser"

# ocm-sync pulls the OCM webapp share into the spawned Lab's home over WebDAV
# (see scripts/ocm-sync). It is the standalone-Docker counterpart of SUNET
# jupyter-custom's ocm-sync, which their k8s singleuser image ships but is not
# published as source. py_compile guards syntax; requests is the WebDAV client.
COPY --chmod=755 scripts/ocm-sync /usr/local/bin/ocm-sync
RUN python3 -c "import requests" && python3 -m py_compile /usr/local/bin/ocm-sync

# Baked reference config. Operators/compose can override by mounting their own.
COPY config/jupyterhub_helpers.py /srv/jupyterhub/jupyterhub_helpers.py
COPY config/jupyterhub_config.py /srv/jupyterhub/jupyterhub_config.py

# System-wide single-user config: runs ocm-sync at Lab startup for OCM shares.
# Read only by spawned jupyter_server processes, never by the hub itself.
COPY config/jupyter_server_config.py /usr/local/etc/jupyter/jupyter_server_config.py
RUN python3 -m py_compile /usr/local/etc/jupyter/jupyter_server_config.py

RUN mkdir -p /etc/ssl/certs /tmp /tls
COPY --from=common-tools /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
      mkdir -p /etc/ssl/certs && \
      cp /tmp/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt && \
      echo "CA bundle copied from common-tools"; \
    else \
      echo "Cert-only mode: Skipping internal CA bundle (using public CA from base image)"; \
    fi && \
    rm -f /tmp/ca-bundle.crt

# The all-in-one jupyterhub base ships without the standard OpenSSL cafile
# symlink (/usr/lib/ssl/cert.pem is absent), so OpenSSL's default trust
# resolution never reads the ca-certificates.crt bundle above and instead lazily
# resolves only the base image's pre-hashed capath symlinks. The DockyPody
# workspace CA lives in the bundle file but has no hashed symlink (the bundle is
# copied, not installed via update-ca-certificates), so it is invisible to
# Python/OpenSSL by default. That silently broke peer TLS for the hub's Python
# OCM service: verifying an inbound /services/ocm/shares signature fetches the
# sender's JWKS over https and failed with CERTIFICATE_VERIFY_FAILED. Point the
# OpenSSL-based stacks (Python urllib/PyJWKClient, curl) and Node
# (configurable-http-proxy) at the populated bundle explicitly so the workspace
# CA is trusted regardless of the base image's default cert layout.
# REQUESTS_CA_BUNDLE is added because python-requests (used by ocm-sync) ships
# its own certifi bundle and ignores SSL_CERT_FILE; without it, ocm-sync's TLS
# to the sender's WebDAV fails to verify the workspace CA.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

COPY --chmod=755 --from=common-tools /usr/local/bin/nu /usr/local/bin/nu
COPY --chmod=755 --from=common-tools /usr/bin/tini-static /usr/bin/tini

COPY ./tls /tmp/tls-source/
COPY --chmod=755 ./scripts/tls/copy-tls.nu /tmp/copy-tls.nu

RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" = "ca-only" ]; then \
      echo "CA-only mode: CA bundle copied via COPY --from=common-tools, copy-tls.nu skipped" && \
      rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    elif [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "ca-only" ]; then \
      if [ ! -f /tmp/copy-tls.nu ]; then \
        echo "Error: copy-tls.nu not found. This should not happen for non-ca-only modes." && exit 1; \
      fi && \
      nu /tmp/copy-tls.nu \
        --enabled "'$TLS_ENABLED'" \
        --mode "'$TLS_MODE'" \
        --ca-name "'$TLS_CA_NAME'" \
        --cert-name "'$TLS_CERT_NAME'" \
        --source-certs /tmp/tls-source/certificates/ \
        --dest /tls/ \
        --runtime-owner "'1000:1000'" && \
      rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
      rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi

COPY --chmod=755 ./scripts/entrypoint.sh /usr/bin/entrypoint.sh
COPY --chmod=755 ./scripts/entrypoint-init.nu /usr/bin/entrypoint-init.nu
COPY --chmod=755 ./scripts/lib/tls.nu /usr/bin/lib/tls.nu
COPY --chmod=755 ./scripts/lib/oauth.nu /usr/bin/lib/oauth.nu

ENV DOCKYPODY_TLS_CERT_NAME="${TLS_CERT_NAME}"

# This image runs as UID 1000. Runtime stacks that want HTTPS on :443 must
# grant NET_BIND_SERVICE (for example via compose `cap_add`).
EXPOSE 443

USER 1000

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/bin/entrypoint.sh"]
CMD ["jupyterhub", "--config", "/srv/jupyterhub/jupyterhub_config.py"]
