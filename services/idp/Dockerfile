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

ARG KEYCLOAK_BASE_IMAGE="quay.io/keycloak/keycloak:26.4.2"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-rhel"

ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

################################
###  Common Tools stage      ###
################################
FROM ${COMMON_TOOLS_IMAGE} AS common-tools

################################
###  Builder stage          ###
################################
FROM ${KEYCLOAK_BASE_IMAGE} AS builder

# Copy the realm configuration file
COPY ./configs/keycloak.json /tmp/keycloak.json

# Import the realm non-interactive
RUN /opt/keycloak/bin/kc.sh import --file /tmp/keycloak.json --override true

# Pre-compile Keycloak for optimized startup
RUN /opt/keycloak/bin/kc.sh build

################################
###  Runtime image          ###
################################
FROM ${KEYCLOAK_BASE_IMAGE}

ARG TLS_ENABLED
ARG TLS_MODE
ARG TLS_CERT_NAME
ARG TLS_CA_NAME
ARG COMMON_TOOLS_IMAGE

COPY --from=builder /opt/keycloak /opt/keycloak

# Switch to root to copy CA bundle
USER root

RUN mkdir -p /etc/pki/ca-trust/extracted/pem /tmp
COPY --from=common-tools /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /tmp/ca-bundle.pem
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
        mkdir -p /etc/pki/ca-trust/extracted/pem && \
        cp /tmp/ca-bundle.pem /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem && \
        echo "CA bundle copied from common-tools"; \
    else \
        echo "Cert-only mode: Skipping internal CA bundle (using public CA from base image)"; \
    fi && \
    rm -f /tmp/ca-bundle.pem

COPY --chmod=755 --from=common-tools /usr/local/bin/nu /usr/local/bin/nu

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
        rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
        rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi

# Switch back to Keycloak user (UID 1000) for security
USER 1000

# Default command: already contains realm, optimized startup
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--verbose"]
