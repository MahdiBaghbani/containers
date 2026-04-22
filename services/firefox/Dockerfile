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

ARG KASM_BASE_IMAGE="kasm-base:v1.0.0-debian"
ARG FIREFOX_VERSION="150.0"
ARG FIREFOX_LOCALE="en-US"

FROM ${KASM_BASE_IMAGE}

ARG FIREFOX_VERSION
ARG FIREFOX_LOCALE

USER root

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    bzip2 \
    ca-certificates \
    curl \
    xz-utils \
    p11-kit-modules

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 ./scripts/install-firefox.nu /tmp/install-firefox.nu
COPY --chmod=755 ./scripts/custom_startup.sh /dockerstartup/custom_startup.sh
COPY --chmod=755 ./scripts/firefox-autostart.nu /dockerstartup/firefox-autostart.nu
COPY ./assets/firefox.desktop /tmp/firefox.desktop

RUN --mount=type=cache,id=firefox-dl-v1-${FIREFOX_VERSION}-${FIREFOX_LOCALE},target=/var/cache/dockypody/firefox,sharing=locked \
    nu /tmp/install-firefox.nu \
      --version "$FIREFOX_VERSION" \
      --locale "$FIREFOX_LOCALE" \
      --dest "/opt" \
      --bin-link "/usr/local/bin/firefox" \
      --desktop-entry-source "/tmp/firefox.desktop" \
      --desktop-entry-dest "/usr/share/applications/firefox.desktop" \
      --download-dir "/var/cache/dockypody/firefox" && \
    rm -f /tmp/install-firefox.nu /tmp/firefox.desktop

RUN install -D -m 0755 -o 1000 -g 0 \
    /usr/share/applications/firefox.desktop \
    /home/kasm-default-profile/Desktop/firefox.desktop

ENV OCM_DEFAULT_WEB_BROWSER="firefox"
ENV OCM_FIREFOX_DARK_MODE="true"
ENV OCM_FIREFOX_SUPPRESS_FIRST_RUN="true"

USER 1000
