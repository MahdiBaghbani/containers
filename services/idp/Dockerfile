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

# Bring in the built /opt/keycloak directory from builder stage
COPY --from=builder /opt/keycloak /opt/keycloak

# Copy TLS certificates from the host and trust them.
COPY ./tls/certificates/ /tls/
COPY ./tls/certificate-authority/ /tls/

# Link certificates to the system trust store
RUN mkdir -p /usr/local/share/ca-certificates && \
    ln -sf /tls/*.crt /usr/local/share/ca-certificates/ 2>/dev/null || true && \
    update-ca-certificates || true

# Default command: already contains realm, optimized startup
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--verbose"]
