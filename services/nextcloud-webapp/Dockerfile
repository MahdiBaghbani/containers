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
# This image bakes both OCM webapp endpoints onto one Nextcloud (Contacts) base:
#   - integration_jupyterhub  (sender: share a notebook folder as a webapp share)
#   - ocmremotewebapp         (receiver: accept and present inbound webapp shares)
# One image serves both roles; the running actor/config selects sender or receiver.

# Both webapp Nextcloud apps build under the one manifest node image
# (external_images.build.tag). node:20 (npm 10) matches integration_jupyterhub's
# declared engines and lock, satisfies vite 7 (needs node >=20.19), and npm 10's
# npm ci tolerates the ocmremotewebapp upstream lock, whose optional native deps
# (@parcel/watcher, @unrs/resolver-binding) are absent as package nodes in the
# committed lockfile and are hard-rejected by npm 11's stricter npm ci.
ARG BASE_BUILD_IMAGE="node:20-trixie-slim"
ARG NEXTCLOUD_CONTACTS_IMAGE="nextcloud-contacts:ocm-contacts-app-debian"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

ARG INTEGRATION_JUPYTERHUB_URL="https://github.com/SUNET/nextcloud-integration_jupyterhub"
ARG INTEGRATION_JUPYTERHUB_REF="main"
ARG INTEGRATION_JUPYTERHUB_SHA=""
ARG INTEGRATION_JUPYTERHUB_REF_KIND=""
ARG INTEGRATION_JUPYTERHUB_PATH=""
ARG INTEGRATION_JUPYTERHUB_MODE=""

ARG OCMREMOTEWEBAPP_URL="https://github.com/SUNET/ocmremotewebapp"
ARG OCMREMOTEWEBAPP_REF="main"
ARG OCMREMOTEWEBAPP_SHA=""
ARG OCMREMOTEWEBAPP_REF_KIND=""
ARG OCMREMOTEWEBAPP_PATH=""
ARG OCMREMOTEWEBAPP_MODE=""

ARG CACHEBUST="default"

#################################
###   Source Prepare (JH)     ###
#################################
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare-jh

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

# Ship only the Nextcloud app subdir; the sibling hub/ python package stays out of this image.
RUN if [ ! -d /integration-jupyterhub-raw/integration_jupyterhub ]; then \
      echo "Error: integration_jupyterhub app subdir missing at /integration-jupyterhub-raw/integration_jupyterhub" >&2; \
      exit 1; \
    fi && \
    mkdir -p /jh-source && \
    cp -a /integration-jupyterhub-raw/integration_jupyterhub/. /jh-source/ && \
    rm -rf /integration-jupyterhub-raw

RUN rm -rf /jh-source/.git && \
    rm -rf /jh-source/.github && \
    rm -rf /jh-source/tests && \
    find /jh-source -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) ! -name "package.json" ! -name "package-lock.json" -delete

#################################
###   Source Prepare (RW)     ###
#################################
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare-rw

WORKDIR /

ARG OCMREMOTEWEBAPP_URL
ARG OCMREMOTEWEBAPP_REF
ARG OCMREMOTEWEBAPP_SHA
ARG OCMREMOTEWEBAPP_REF_KIND
ARG OCMREMOTEWEBAPP_PATH
ARG OCMREMOTEWEBAPP_MODE
ARG CACHEBUST

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

# Clone or copy ocmremotewebapp source via shared helper (local bind mount or git cache).
RUN --mount=type=cache,id=ocmremotewebapp-git-${CACHEBUST:-${OCMREMOTEWEBAPP_REF}},target=/src/ocmremotewebapp-git-cache,sharing=shared \
    --mount=type=bind,source=${OCMREMOTEWEBAPP_PATH:-.},target=/src/local-ocmremotewebapp,ro \
    nu /tmp/clone-source.nu \
    --mode "${OCMREMOTEWEBAPP_MODE:-git}" \
    --url "${OCMREMOTEWEBAPP_URL}" \
    --ref "${OCMREMOTEWEBAPP_REF}" \
    --ref-kind "${OCMREMOTEWEBAPP_REF_KIND}" \
    --local-dir /src/local-ocmremotewebapp \
    --cache-dir /src/ocmremotewebapp-git-cache \
    --dest /ocmremotewebapp-raw

# ocmremotewebapp is a standalone Nextcloud app repo: the repo root is the app.
RUN if [ ! -f /ocmremotewebapp-raw/appinfo/info.xml ]; then \
      echo "Error: ocmremotewebapp appinfo/info.xml missing at /ocmremotewebapp-raw/appinfo/info.xml" >&2; \
      exit 1; \
    fi && \
    mkdir -p /rw-source && \
    cp -a /ocmremotewebapp-raw/. /rw-source/ && \
    rm -rf /ocmremotewebapp-raw

RUN rm -rf /rw-source/.git && \
    rm -rf /rw-source/.github && \
    rm -rf /rw-source/tests && \
    find /rw-source -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) ! -name "package.json" ! -name "package-lock.json" -delete

###################
###   UI (JH)   ###
###################
FROM ${BASE_BUILD_IMAGE} AS ui-build-jh

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

COPY --from=source-prepare-jh /jh-source /build

RUN --mount=type=cache,id=integration-jupyterhub-npm-cache,target=/root/.npm,sharing=locked \
    npm ci && \
    npm run build && \
    mkdir -p /build/css

###################
###   UI (RW)   ###
###################
FROM ${BASE_BUILD_IMAGE} AS ui-build-rw

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

COPY --from=source-prepare-rw /rw-source /build

RUN --mount=type=cache,id=ocmremotewebapp-npm-cache,target=/root/.npm,sharing=locked \
    npm ci && \
    npm run build && \
    mkdir -p /build/css

#############################
###   Composer Deps (JH)  ###
#############################
FROM ${NEXTCLOUD_CONTACTS_IMAGE} AS composer-deps-jh

WORKDIR /app

COPY --from=source-prepare-jh /jh-source /app

RUN --mount=type=cache,id=integration-jupyterhub-composer-cache,target=/root/.composer/cache,sharing=locked \
    composer dump-autoload --optimize --no-interaction

#############################
###   Composer Deps (RW)  ###
#############################
FROM ${NEXTCLOUD_CONTACTS_IMAGE} AS composer-deps-rw

WORKDIR /app

COPY --from=source-prepare-rw /rw-source /app

RUN --mount=type=cache,id=ocmremotewebapp-composer-cache,target=/root/.composer/cache,sharing=locked \
    composer dump-autoload --optimize --no-interaction

############################
###   App Assemble (JH)  ###
############################
FROM ${COMMON_TOOLS_IMAGE} AS app-assemble-jh

WORKDIR /app

COPY --from=source-prepare-jh /jh-source /app
COPY --from=ui-build-jh /build/js /app/js
COPY --from=ui-build-jh /build/css /app/css
COPY --from=composer-deps-jh /app/vendor /app/vendor

RUN rm -rf /app/node_modules && \
    rm -rf /app/src && \
    rm -rf /app/vendor-bin && \
    rm -f /app/package.json /app/package-lock.json && \
    rm -f /app/webpack.config.js /app/babel.config.js /app/stylelint.config.js && \
    rm -f /app/Makefile && \
    rm -f /app/*.config.* /app/*.cjs /app/*.mjs

############################
###   App Assemble (RW)  ###
############################
FROM ${COMMON_TOOLS_IMAGE} AS app-assemble-rw

WORKDIR /app

COPY --from=source-prepare-rw /rw-source /app
COPY --from=ui-build-rw /build/js /app/js
COPY --from=ui-build-rw /build/css /app/css
COPY --from=composer-deps-rw /app/vendor /app/vendor

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

COPY --from=app-assemble-jh /app /usr/src/apps/integration_jupyterhub
COPY --from=app-assemble-rw /app /usr/src/apps/ocmremotewebapp

COPY --chmod=755 ./scripts/hooks/post-installation/ \
    /docker-entrypoint-hooks.d/post-installation/
COPY --chmod=755 ./scripts/hooks/before-starting/ \
    /docker-entrypoint-hooks.d/before-starting/

VOLUME /var/www/html

CMD ["apache2-foreground"]
