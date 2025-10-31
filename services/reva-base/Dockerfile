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

################################
###  Build Reva from source  ###
################################
FROM ${BASE_BUILD_IMAGE} AS build

ENV CGO_ENABLED=1

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    git \
    bash \
    make \
    build-essential \
    libsqlite3-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /

ARG REVA_REPO="https://github.com/cs3org/reva"
ARG REVA_BRANCH="v3.3.2"
ARG CACHEBUST="default"

RUN git clone \
    --depth 1 \
    --recursive \
    --shallow-submodules \
    --branch ${REVA_BRANCH} \
    ${REVA_REPO} \
    /reva-git

WORKDIR /reva-git
RUN go mod download
RUN make reva revad

###############################
###  Build UPX from source  ###
###############################
FROM ${BASE_RUNTIME_IMAGE} AS upx-build

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    build-essential \
    cmake \
    git \
    ca-certificates \
    zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/upx

ARG UPX_REPO="https://github.com/upx/upx"
ARG UPX_VERSION="v5.0.2"

RUN git clone --branch "${UPX_VERSION}" --depth 1 \
    --recurse-submodules --shallow-submodules \
    ${UPX_REPO} .

RUN git submodule update --init --recursive --depth 1

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
RUN cmake --build build -j"$(nproc)"

####################################
###  Compress binaries with UPX  ###
####################################
FROM ${BASE_RUNTIME_IMAGE} AS compress

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    binutils \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=upx-build /src/upx/build/upx /usr/local/bin/upx
RUN chmod +x /usr/local/bin/upx && upx --version

RUN mkdir -p /tmp/binaries

COPY --from=build /reva-git/cmd/reva/reva /tmp/binaries/reva
COPY --from=build /reva-git/cmd/revad/revad /tmp/binaries/revad

ARG NU_REPO="https://github.com/nushell/nushell"
ARG NU_REF="0.108.0"
RUN curl -fsSL -o /tmp/nu.tar.gz ${NU_REPO}/releases/download/${NU_REF}/nu-${NU_REF}-x86_64-unknown-linux-gnu.tar.gz \
    && mkdir -p /tmp/nu \
    && tar -xzf /tmp/nu.tar.gz -C /tmp/nu --strip-components=1 \
    && mv /tmp/nu/nu /tmp/binaries/nu \
    && rm -rf /tmp/nu.tar.gz /tmp/nu

ARG PACK_WITH_UPX="true"
RUN if [ "${PACK_WITH_UPX}" = "true" ]; then \
    strip -s /tmp/binaries/* || true; \
    upx -qq --best --lzma /tmp/binaries/* && upx -t /tmp/binaries/*; \
    fi

###################################
###        Runtime image        ###
###################################
FROM ${BASE_RUNTIME_IMAGE}

RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install \
    --no-install-recommends \
    --assume-yes \
    bash \
    curl \
    tzdata \
    iproute2 \
    ca-certificates; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV TZ=Etc/UTC

COPY ./tls/certificates/* /tls/
COPY ./tls/certificate-authority/* /tls/

RUN ln -sf /tls/*.crt /usr/local/share/ca-certificates; \
    update-ca-certificates || true


RUN mkdir -p /reva-git/cmd
COPY --chmod=755 --from=compress /tmp/binaries/nu /usr/local/bin/nu
COPY --chmod=755 --from=compress /tmp/binaries/reva /reva-git/cmd/reva
COPY --chmod=755 --from=compress /tmp/binaries/revad /reva-git/cmd/revad
RUN nu --version

ENV PATH="${PATH}:/reva-git/cmd"

COPY ./scripts/* /usr/bin/

ENTRYPOINT ["nu", "/usr/bin/entrypoint.nu"]

CMD ["tail", "-F", "/var/log/revad.log"]
