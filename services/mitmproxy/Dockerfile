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

ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"
ARG MITMPROXY_UPSTREAM_IMAGE="mitmproxy/mitmproxy:12.2.2"

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

FROM ${COMMON_TOOLS_IMAGE} AS common-tools

FROM ${MITMPROXY_UPSTREAM_IMAGE}

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""
ARG COMMON_TOOLS_IMAGE

ENV DOCKYPODY_CA_DIR_MOUNT="/certificate-authority" \
    DOCKYPODY_CA_DIR_DEFAULT="/opt/dockypody/certificate-authority-default"

USER root

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --assume-yes \
      nginx ca-certificates; \
    rm -f /etc/nginx/sites-enabled/default

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/ssl/certs /tmp
COPY --from=common-tools /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
      mkdir -p /etc/ssl/certs && \
      cp /tmp/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt && \
      echo "CA bundle copied from common-tools"; \
    else \
      echo "Internal CA bundle disabled (TLS disabled or cert-only mode)"; \
    fi && \
    rm -f /tmp/ca-bundle.crt

COPY --chmod=755 --from=common-tools /usr/local/bin/nu /usr/local/bin/nu

RUN mkdir -p /etc/nginx/templates-available
COPY ./nginx/mitmweb.conf.template /etc/nginx/templates-available/mitmweb.conf.template

COPY ./tls /tmp/tls-source/
COPY --chmod=755 ./scripts/tls/copy-tls.nu /tmp/copy-tls.nu

RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
      if [ -z "$TLS_CA_NAME" ]; then \
        echo "Error: TLS_CA_NAME must be provided when TLS_ENABLED=true and TLS_MODE!=cert-only" && exit 1; \
      fi && \
      mkdir -p "$DOCKYPODY_CA_DIR_DEFAULT" && \
      cp "/tmp/tls-source/certificate-authority/${TLS_CA_NAME}.crt" "$DOCKYPODY_CA_DIR_DEFAULT/${TLS_CA_NAME}.crt" 2>/dev/null || \
        (echo "Error: CA cert ${TLS_CA_NAME}.crt not found in build context" && exit 1) && \
      cp "/tmp/tls-source/certificate-authority/${TLS_CA_NAME}.key" "$DOCKYPODY_CA_DIR_DEFAULT/${TLS_CA_NAME}.key" 2>/dev/null || \
        (echo "Error: CA key ${TLS_CA_NAME}.key not found in build context" && exit 1) && \
      echo "Default DockyPody CA keypair installed"; \
    else \
      echo "TLS disabled or cert-only mode: skipping default CA keypair install"; \
    fi && \
    true

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
      rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
      rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi

COPY --chmod=755 ./scripts/mitm-entrypoint.nu /usr/local/bin/mitm-entrypoint.nu

ENTRYPOINT ["/usr/local/bin/nu", "/usr/local/bin/mitm-entrypoint.nu"]
