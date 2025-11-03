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

ARG BASE_BUILD_IMAGE="node:20"
ARG BASE_RUNTIME_IMAGE="nginx:1.29-alpine3.22-slim"

###############################
###  Build Web from source  ###
###############################
FROM ${BASE_BUILD_IMAGE} AS builder

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    git \
    make \
    ca-certificates \
    sed \
    gzip \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Nushell
ARG NU_REPO="https://github.com/nushell/nushell"
ARG NU_REF="0.108.0"
RUN curl -fsSL -o /tmp/nu.tar.gz ${NU_REPO}/releases/download/${NU_REF}/nu-${NU_REF}-x86_64-unknown-linux-gnu.tar.gz \
    && mkdir -p /tmp/nu \
    && tar -xzf /tmp/nu.tar.gz -C /tmp/nu --strip-components=1 \
    && mv /tmp/nu/nu /usr/local/bin/nu \
    && chmod +x /usr/local/bin/nu \
    && rm -rf /tmp/nu.tar.gz /tmp/nu \
    && nu --version

# Enable corepack for pnpm support
RUN corepack enable

# Copy host‑provided trust anchors
# COPY tls/certificates/cernbox* tls/certificate-authority/* /usr/local/share/ca-certificates/

# Update CA trust store
# RUN update-ca-certificates

WORKDIR /build

ARG WEB_REPO=https://github.com/cernbox/web
ARG WEB_BRANCH=cernbox
ARG CACHEBUST="default"

RUN git clone \
    --depth 1 \
    --branch ${WEB_BRANCH} \
    ${WEB_REPO} \
    web

WORKDIR /build/web

RUN corepack prepare pnpm@9 --activate

ENV TITLE=CERNBox
ENV SOURCE_MAP=true
ENV REQUIRE_TIMEOUT=20
ENV DOCUMENTATION_URL="https://cernbox.docs.cern.ch/web/#desktop-requirements"

RUN pnpm install
RUN make dist

# Mesh directory hostname replacement moved to runtime (see scripts/cernbox.sh)


WORKDIR /build

ARG WEB_EXTENSIONS_REPO=https://github.com/cernbox/web-extensions
ARG WEB_EXTENSIONS_BRANCH=main

RUN git clone \
    --depth 1 \
    --branch ${WEB_EXTENSIONS_BRANCH} \
    ${WEB_EXTENSIONS_REPO} \
    web-extensions

WORKDIR /build/web-extensions

# Copy the build script
COPY --chmod=755 ./scripts/build-extensions.nu /usr/local/bin/build-extensions.nu

# Build all packages with retry logic
ARG PNPM_RETRY_COUNT="10"
RUN nu /usr/local/bin/build-extensions.nu . /build/cernbox --retry-count $PNPM_RETRY_COUNT

#############################
###  Nginx runtime image  ###
#############################
FROM ${BASE_RUNTIME_IMAGE}

#COPY --chown=nginx:nginx ./tls/certificates/cernbox* /tls/
#COPY --chown=nginx:nginx ./tls/certificate-authority/* /tls/

#COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Static assets from the built web frontend
COPY --from=builder --chown=nginx:nginx /build/web/dist /var/www/web
# Static assets from the built web extensions
COPY --from=builder --chown=nginx:nginx /build/cernbox /var/www/cernbox

# Web UI runtime configuration
COPY --chown=nginx:nginx ./configs/config.json /var/www/web/config.json

# nginx config templates
COPY --chown=nginx:nginx ./configs/mime.types /etc/nginx/mime.types
COPY --chown=nginx:nginx ./configs/nginx-http.conf.template /etc/nginx/templates-available/cernbox-http.conf.template
COPY --chown=nginx:nginx ./configs/nginx-https.conf.template /etc/nginx/templates-available/cernbox-https.conf.template

# Entrypoint script to replace the hostname in the config.json file
COPY --chown=nginx:nginx ./scripts/cernbox.sh /docker-entrypoint.d/cernbox.sh
