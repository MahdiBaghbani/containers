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

ARG NEXTCLOUD_BASE_IMAGE="nextcloud-base:v1.0.0-debian"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

################################
###  Source Preparation      ###
################################
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare

WORKDIR /

ARG NEXTCLOUD_URL="https://github.com/nextcloud/server"
ARG NEXTCLOUD_REF="v32.0.2"
ARG NEXTCLOUD_SHA=""
ARG NEXTCLOUD_PATH=""
ARG NEXTCLOUD_MODE=""
ARG CACHEBUST="default"

# Clone or copy Nextcloud source (follows revad-base pattern)
RUN --mount=type=cache,id=nextcloud-server-git-${CACHEBUST:-${NEXTCLOUD_REF}},target=/src/nextcloud-git-cache,sharing=shared \
    --mount=type=bind,source=${NEXTCLOUD_PATH:-.},target=/src/local-nextcloud,ro \
    if [ "$NEXTCLOUD_MODE" = "local" ]; then \
    mkdir -p /nextcloud-source && \
    cp -a /src/local-nextcloud/. /nextcloud-source && \
    rm -f /nextcloud-source/config/config.php && \
    rm -rf /nextcloud-source/data /nextcloud-source/data-autotest; \
    else \
    mkdir -p /src/nextcloud-git-cache && \
    if [ ! -d /src/nextcloud-git-cache/.git ]; then \
    rm -rf /src/nextcloud-git-cache/* /src/nextcloud-git-cache/.[!.]* 2>/dev/null || true; \
    git clone --depth 1 --recursive --shallow-submodules --branch "${NEXTCLOUD_REF}" ${NEXTCLOUD_URL} /src/nextcloud-git-cache; \
    fi && \
    cp -a /src/nextcloud-git-cache/. /nextcloud-source; \
    fi

# Remove unnecessary files (.git, tests, docs) to reduce image size
RUN rm -rf /nextcloud-source/.git && \
    rm -rf /nextcloud-source/tests && \
    rm -rf /nextcloud-source/.github && \
    find /nextcloud-source -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) -delete

################################
###  Final Runtime Image     ###
################################
FROM ${NEXTCLOUD_BASE_IMAGE}

COPY --from=source-prepare /nextcloud-source /usr/src/nextcloud

COPY --chmod=755 ./scripts/hooks/00-start-log-tailing.nu /docker-entrypoint-hooks.d/before-starting/

VOLUME /var/www/html

CMD ["apache2-foreground"]
