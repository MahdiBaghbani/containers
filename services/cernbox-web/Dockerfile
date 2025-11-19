# syntax=docker/dockerfile:1.7

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

ARG BASE_BUILD_IMAGE="node:20-trixie-slim"
ARG BASE_RUNTIME_IMAGE="nginx:1.29-alpine3.22-slim"
ARG COMMON_TOOLS_BUILDER_IMAGE="common-tools:v1.0.0-debian"
ARG COMMON_TOOLS_RUNTIME_IMAGE="common-tools:v1.0.0-alpine"

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

###############################
###       Common Tools      ###
###############################
FROM ${COMMON_TOOLS_BUILDER_IMAGE} AS common-tools-builder

###############################
###  Build Web from source  ###
###############################
FROM ${BASE_BUILD_IMAGE} AS builder

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    git \
    make \
    ca-certificates \
    sed \
    gzip \
    curl;

COPY --chmod=755 --from=common-tools-builder /usr/local/bin/nu /usr/local/bin/nu
RUN nu --version || (echo "Nushell verification failed" && exit 1)

# Enable corepack for pnpm support
RUN corepack enable

WORKDIR /build

ARG WEB_URL=https://github.com/cernbox/web
ARG WEB_REF=cernbox
ARG CACHEBUST="default"

RUN --mount=type=cache,id=cernbox-web-web-git-${CACHEBUST:-${WEB_REF}},target=/src/web-git-cache,sharing=shared \
    mkdir -p /src/web-git-cache && \
    if [ ! -d /src/web-git-cache/.git ]; then \
    git clone --depth 1 --branch "${WEB_REF}" ${WEB_URL} /src/web-git-cache; \
    fi && \
    cp -a /src/web-git-cache/. /build/web

WORKDIR /build/web

RUN corepack prepare pnpm@9 --activate

# Configure pnpm for better network reliability and caching
# This is needed for places that have bad internet connection.
RUN pnpm config set store-dir /root/.local/share/pnpm/store && \
    pnpm config set network-timeout 300000 && \
    pnpm config set fetch-retries 5 && \
    pnpm config set fetch-retry-mintimeout 10000 && \
    pnpm config set fetch-retry-maxtimeout 60000

# Got this from the cernbox/web-release repository.
# https://github.com/cernbox/web-release/blob/af019b67c31424c096a1a4398ae0d9874b6c304f/.github/workflows/build.yml#L28-L36
ENV TITLE=CERNBox
ENV SOURCE_MAP=true
ENV REQUIRE_TIMEOUT=20
ENV DOCUMENTATION_URL="https://cernbox.docs.cern.ch/web/#desktop-requirements"

# Install dependencies with BuildKit cache mount.
# This is needed for persistence across builds.
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    --mount=type=cache,id=pnpm-cache,target=/root/.cache/pnpm \
    pnpm install
RUN make dist

WORKDIR /build

ARG WEB_EXTENSIONS_URL=https://github.com/cernbox/web-extensions
ARG WEB_EXTENSIONS_REF=main

RUN --mount=type=cache,id=cernbox-web-web-extensions-git-${CACHEBUST:-${WEB_EXTENSIONS_REF}},target=/src/web-extensions-git-cache,sharing=shared \
    mkdir -p /src/web-extensions-git-cache && \
    if [ ! -d /src/web-extensions-git-cache/.git ]; then \
    git clone --depth 1 --branch "${WEB_EXTENSIONS_REF}" ${WEB_EXTENSIONS_URL} /src/web-extensions-git-cache; \
    fi && \
    cp -a /src/web-extensions-git-cache/. /build/web-extensions

WORKDIR /build/web-extensions


COPY --chmod=755 ./scripts/build-extensions.nu /usr/local/bin/build-extensions.nu

# Build all packages with retry logic and BuildKit cache mount
ARG PNPM_RETRY_COUNT="10"
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    --mount=type=cache,id=pnpm-cache,target=/root/.cache/pnpm \
    nu /usr/local/bin/build-extensions.nu . /build/cernbox --retry-count $PNPM_RETRY_COUNT

###############################
###   Common Tools Runtime  ###
###############################
FROM ${COMMON_TOOLS_RUNTIME_IMAGE} AS common-tools-runtime

#############################
###  Nginx runtime image  ###
#############################
FROM ${BASE_RUNTIME_IMAGE}

ARG COMMON_TOOLS_RUNTIME_IMAGE

ARG TLS_ENABLED
ARG TLS_MODE
ARG TLS_CERT_NAME
ARG TLS_CA_NAME

RUN mkdir -p /etc/ssl/certs /tmp
COPY --from=common-tools-runtime /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
    mkdir -p /etc/ssl/certs && \
    cp /tmp/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt && \
    echo "CA bundle copied from common-tools"; \
    else \
    echo "Cert-only mode: Skipping internal CA bundle (using public CA from base image)"; \
    fi && \
    rm -f /tmp/ca-bundle.crt

COPY --chmod=755 --from=common-tools-runtime /usr/local/bin/nu /usr/local/bin/nu

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
    --dest /tls/ && \
    if [ -d /tls ]; then chown -R nginx:nginx /tls/; fi && \
    rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
    rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi

# Static assets from the built web frontend (source location in image)
RUN mkdir -p /assets/cernbox-web
COPY --from=builder --chown=nginx:nginx /build/web/dist /assets/cernbox-web/web
# Static assets from the built web-extensions
COPY --from=builder --chown=nginx:nginx /build/cernbox /assets/cernbox-web/cernbox

# Web frontend runtime configuration (source location in image)
RUN mkdir -p /configs/cernbox-web
COPY --chown=nginx:nginx ./configs/config.json /configs/cernbox-web/config.json

# Nginx config templates
COPY --chown=nginx:nginx ./configs/mime.types /etc/nginx/mime.types
COPY --chown=nginx:nginx ./configs/nginx-http.conf.template /etc/nginx/templates-available/cernbox-http.conf.template
COPY --chown=nginx:nginx ./configs/nginx-https.conf.template /etc/nginx/templates-available/cernbox-https.conf.template

# Entrypoint scripts to replace lots of placeholders in frontend
# Wrapper shell script (for nginx entrypoint compatibility) and nushell implementation
COPY --chmod=755 --chown=nginx:nginx ./scripts/cernbox.sh /docker-entrypoint.d/cernbox.sh
COPY --chmod=755 --chown=nginx:nginx ./scripts/cernbox.nu /docker-entrypoint.d/cernbox.nu
