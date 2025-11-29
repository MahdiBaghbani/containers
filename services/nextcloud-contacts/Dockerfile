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

ARG BASE_BUILD_IMAGE="node:24-trixie-slim"
ARG NEXTCLOUD_IMAGE="nextcloud:v32.0.2-debian"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

ARG CONTACTS_URL="https://github.com/nextcloud/contacts"
ARG CONTACTS_REF="v8.1.0"
ARG CONTACTS_SHA=""
ARG CONTACTS_PATH=""
ARG CONTACTS_MODE=""
ARG CACHEBUST="default"

##########################
###   Source Prepare   ###
##########################
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare

WORKDIR /

ARG CONTACTS_URL
ARG CONTACTS_REF
ARG CONTACTS_SHA
ARG CONTACTS_PATH
ARG CONTACTS_MODE
ARG CACHEBUST

# Clone or copy contacts source (follows revad-base pattern)
RUN --mount=type=cache,id=contacts-git-${CACHEBUST:-${CONTACTS_REF}},target=/src/contacts-git-cache,sharing=shared \
    --mount=type=bind,source=${CONTACTS_PATH:-.},target=/src/local-contacts,ro \
    if [ "$CONTACTS_MODE" = "local" ]; then \
    mkdir -p /contacts-source && \
    cp -a /src/local-contacts/. /contacts-source; \
    else \
    mkdir -p /src/contacts-git-cache && \
    if [ ! -d /src/contacts-git-cache/.git ]; then \
    rm -rf /src/contacts-git-cache/* /src/contacts-git-cache/.[!.]* 2>/dev/null || true; \
    git clone --depth 1 --recursive --shallow-submodules --branch "${CONTACTS_REF}" ${CONTACTS_URL} /src/contacts-git-cache; \
    fi && \
    cp -a /src/contacts-git-cache/. /contacts-source; \
    fi

RUN rm -rf /contacts-source/.git && \
    rm -rf /contacts-source/.github && \
    rm -rf /contacts-source/tests && \
    find /contacts-source -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) ! -name "package.json" ! -name "package-lock.json" -delete

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

COPY --from=source-prepare /contacts-source /build

RUN --mount=type=cache,id=contacts-npm-cache,target=/root/.npm,sharing=locked \
    npm ci && \
    npm run build

#########################
###   Composer Deps   ###
#########################
# Use Nextcloud image for composer (already has PHP + composer installed)
FROM ${NEXTCLOUD_IMAGE} AS composer-deps

WORKDIR /app

COPY --from=source-prepare /contacts-source /app

# Generate autoloader (app has no runtime composer packages, just PSR-4 autoloading)
RUN composer dump-autoload --optimize --no-interaction

########################
###   App Assemble   ###
########################
FROM ${COMMON_TOOLS_IMAGE} AS app-assemble

WORKDIR /app

COPY --from=source-prepare /contacts-source /app
COPY --from=ui-build /build/js /app/js
COPY --from=ui-build /build/css /app/css
COPY --from=composer-deps /app/vendor /app/vendor

RUN rm -rf /app/node_modules && \
    rm -rf /app/src && \
    rm -rf /app/vendor-bin && \
    rm -f /app/package.json /app/package-lock.json && \
    rm -f /app/vite.config.js /app/tsconfig.json && \
    rm -f /app/*.config.* /app/*.cjs /app/*.mjs

###################
###   Runtime   ###
###################
FROM ${NEXTCLOUD_IMAGE}

COPY --from=app-assemble /app /usr/src/apps/contacts

COPY --chmod=755 ./scripts/hooks/post-installation/ \
    /docker-entrypoint-hooks.d/post-installation/
COPY --chmod=755 ./scripts/hooks/before-starting/ \
    /docker-entrypoint-hooks.d/before-starting/

VOLUME /var/www/html

CMD ["apache2-foreground"]
