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

ARG BASE_HUB_IMAGE="quay.io/jupyterhub/k8s-hub:4.2.0"
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

# Install the authenticator + OCM services package. simplespawner backs the
# baked config's spawner_class = "simple" (Layer 3 notebook image deferred).
COPY --from=source-prepare /hub-source /tmp/hub
RUN pip install --no-cache-dir /tmp/hub jupyterhub-simplespawner && rm -rf /tmp/hub

# Baked reference config. Operators/compose can override by mounting their own.
COPY config/jupyterhub_helpers.py /srv/jupyterhub/jupyterhub_helpers.py
COPY config/jupyterhub_config.py /srv/jupyterhub/jupyterhub_config.py

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

ENV DOCKYPODY_TLS_CERT_NAME="${TLS_CERT_NAME}"

# This image runs as UID 1000. Runtime stacks that want HTTPS on :443 must
# grant NET_BIND_SERVICE (for example via compose `cap_add`).
EXPOSE 443

USER 1000

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/bin/entrypoint.sh"]
CMD ["jupyterhub", "--config", "/srv/jupyterhub/jupyterhub_config.py"]
