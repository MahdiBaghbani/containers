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

ARG BASE_BUILD_IMAGE="node:24-trixie-slim"
ARG NEXTCLOUD_CONTACTS_IMAGE="nextcloud-contacts:ocm-contacts-app-debian"
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

# Ship only the Nextcloud app subdir; the sibling hub/ python package stays out of the image.
RUN if [ ! -d /integration-jupyterhub-raw/integration_jupyterhub ]; then \
      echo "Error: integration_jupyterhub app subdir missing at /integration-jupyterhub-raw/integration_jupyterhub" >&2; \
      exit 1; \
    fi && \
    mkdir -p /integration-jupyterhub-source && \
    cp -a /integration-jupyterhub-raw/integration_jupyterhub/. /integration-jupyterhub-source/ && \
    rm -rf /integration-jupyterhub-raw

RUN rm -rf /integration-jupyterhub-source/.git && \
    rm -rf /integration-jupyterhub-source/.github && \
    rm -rf /integration-jupyterhub-source/tests && \
    find /integration-jupyterhub-source -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) ! -name "package.json" ! -name "package-lock.json" -delete

##################
###   UI Build   ###
##################
FROM ${BASE_BUILD_IMAGE} AS ui-build

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    make;

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY --from=source-prepare /integration-jupyterhub-source /build

RUN --mount=type=cache,id=integration-jupyterhub-npm-cache,target=/root/.npm,sharing=locked \
    npm ci && \
    npm run build && \
    mkdir -p /build/css

#########################
###   Composer Deps   ###
#########################
# Use the contacts-based Nextcloud image for composer (PHP + composer already installed).
FROM ${NEXTCLOUD_CONTACTS_IMAGE} AS composer-deps

WORKDIR /app

COPY --from=source-prepare /integration-jupyterhub-source /app

RUN --mount=type=cache,id=integration-jupyterhub-composer-cache,target=/root/.composer/cache,sharing=locked \
    composer dump-autoload --optimize --no-interaction

########################
###   App Assemble   ###
########################
FROM ${COMMON_TOOLS_IMAGE} AS app-assemble

WORKDIR /app

COPY --from=source-prepare /integration-jupyterhub-source /app
COPY --from=ui-build /build/js /app/js
COPY --from=ui-build /build/css /app/css
COPY --from=composer-deps /app/vendor /app/vendor

RUN rm -rf /app/node_modules && \
    rm -rf /app/src && \
    rm -rf /app/vendor-bin && \
    rm -f /app/package.json /app/package-lock.json && \
    rm -f /app/webpack.config.js /app/babel.config.js /app/stylelint.config.js && \
    rm -f /app/Makefile && \
    rm -f /app/*.config.* /app/*.cjs /app/*.mjs

###################
###   Runtime   ###
###################
FROM ${NEXTCLOUD_CONTACTS_IMAGE}

COPY --from=app-assemble /app /usr/src/apps/integration_jupyterhub

COPY --chmod=755 ./scripts/hooks/post-installation/ \
    /docker-entrypoint-hooks.d/post-installation/
COPY --chmod=755 ./scripts/hooks/before-starting/ \
    /docker-entrypoint-hooks.d/before-starting/

VOLUME /var/www/html

CMD ["apache2-foreground"]
