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

ARG BASE_BUILD_IMAGE="golang:1.25-trixie"
ARG BASE_RUNTIME_IMAGE="debian:trixie-slim"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

################################
###  Build Gaia from source  ###
################################
FROM ${BASE_BUILD_IMAGE} AS build

RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    git \
    ca-certificates;

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /

ARG GAIA_URL="https://github.com/cs3org/gaia"
ARG GAIA_REF="master"
ARG CACHEBUST="default"

RUN --mount=type=cache,id=gaia-git-${CACHEBUST:-${GAIA_REF}},target=/src/gaia-git-cache,sharing=shared \
    mkdir -p /src/gaia-git-cache && \
    if [ ! -d /src/gaia-git-cache/.git ]; then \
    git clone --depth 1 --recursive --shallow-submodules --branch "${GAIA_REF}" ${GAIA_URL} /src/gaia-git-cache; \
    fi && \
    cp -a /src/gaia-git-cache/. /gaia-git

WORKDIR /gaia-git
RUN --mount=type=cache,id=gaia-go-mod-cache,target=/go/pkg/mod,sharing=locked \
    go mod download
RUN --mount=type=cache,id=gaia-go-mod-cache,target=/go/pkg/mod,sharing=locked \
    go build -o /gaia .

####################################
###  Compress binary with UPX    ###
####################################
FROM ${COMMON_TOOLS_IMAGE} AS compress

RUN mkdir -p /tmp/binaries

COPY --from=build /gaia /tmp/binaries/gaia

ARG PACK_WITH_UPX="true"
RUN if [ "${PACK_WITH_UPX}" = "true" ]; then \
    strip -s /tmp/binaries/gaia || true; \
    upx -qq --best --lzma /tmp/binaries/gaia && upx -t /tmp/binaries/gaia; \
    fi

###################################
###   Production Runtime        ###
###################################
FROM ${BASE_RUNTIME_IMAGE}

COPY --from=compress --chmod=755 /tmp/binaries/gaia /usr/local/bin/gaia

ENV PATH="/usr/local/bin:${PATH}"

ENTRYPOINT [ "/usr/local/bin/gaia" ]
