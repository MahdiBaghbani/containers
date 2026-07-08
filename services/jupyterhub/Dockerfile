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
#   POST /services/ocm/open -> GET /hub/ocm-login -> 302 .../lab
# The nextcloud-ocm-jupyterhub package (authenticator + ocm/refresh-token
# managed services) lives in the hub/ subdir of the same upstream repo as the
# integration_jupyterhub Nextcloud app; it is cloned and pinned via
# versions.nuon (repoint to a fork to own the source). Base tag pinned to the
# SUNET upstream default.

ARG BASE_HUB_IMAGE="quay.io/jupyterhub/k8s-hub:4.2.0"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

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

###################
###   Runtime   ###
###################
FROM ${BASE_HUB_IMAGE}

USER root

# Install the authenticator + OCM services package. simplespawner backs the
# baked config's spawner_class = "simple" (Layer 3 notebook image deferred).
COPY --from=source-prepare /hub-source /tmp/hub
RUN pip install --no-cache-dir /tmp/hub jupyterhub-simplespawner && rm -rf /tmp/hub

# Baked reference config. Operators/compose can override by mounting their own.
COPY config/jupyterhub_config.py /srv/jupyterhub/jupyterhub_config.py

USER 1000

CMD ["jupyterhub", "--config", "/srv/jupyterhub/jupyterhub_config.py"]
