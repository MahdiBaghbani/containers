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

ARG BASE_BUILD_IMAGE="golang:1.25-trixie"
ARG BASE_RUNTIME_IMAGE="debian:trixie-slim"
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

################################
###  Common Tools (nu)       ###
################################
FROM ${COMMON_TOOLS_IMAGE} AS common-tools-builder

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
  ca-certificates \
  git;

RUN apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 --from=common-tools-builder /usr/local/bin/nu /usr/local/bin/nu
RUN nu --version || (echo "Nushell verification failed" && exit 1)

WORKDIR /

ARG GAIA_URL="https://github.com/cs3org/gaia"
ARG GAIA_REF="master"
ARG GAIA_SHA=""
ARG GAIA_REF_KIND=""
ARG GAIA_PATH=""
ARG GAIA_MODE=""
ARG GO_BUILD_GOPROXY=""
ARG CACHEBUST="default"

COPY --chmod=755 ./scripts/lib/clone-source.nu /tmp/clone-source.nu

# Clone or copy gaia source via shared helper (local bind mount or git cache).
RUN --mount=type=cache,id=gaia-git-${CACHEBUST:-${GAIA_REF}},target=/src/gaia-git-cache,sharing=shared \
  --mount=type=bind,source=${GAIA_PATH:-.},target=/tmp/local-gaia,ro \
  nu /tmp/clone-source.nu \
  --mode "${GAIA_MODE:-git}" \
  --url "${GAIA_URL}" \
  --ref "${GAIA_REF}" \
  --ref-kind "${GAIA_REF_KIND}" \
  --local-dir /tmp/local-gaia \
  --cache-dir /src/gaia-git-cache \
  --dest /gaia-git

WORKDIR /gaia-git
RUN --mount=type=cache,id=gaia-go-mod-cache,target=/go/pkg/mod,sharing=locked \
  if [ -n "$GO_BUILD_GOPROXY" ]; then \
  GOPROXY="$GO_BUILD_GOPROXY" go mod download; \
  else \
  go mod download; \
  fi
RUN --mount=type=cache,id=gaia-go-mod-cache,target=/go/pkg/mod,sharing=locked \
  --mount=type=cache,id=gaia-go-build-cache,target=/root/.cache/go-build,sharing=locked \
  if [ -n "$GO_BUILD_GOPROXY" ]; then \
  GOPROXY="$GO_BUILD_GOPROXY" go build -o /gaia .; \
  else \
  go build -o /gaia .; \
  fi

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
COPY --chmod=755 --from=compress /usr/bin/tini-static /usr/bin/tini

COPY --chmod=755 ./scripts/entrypoint.sh /usr/bin/entrypoint.sh
COPY --chmod=755 ./scripts/entrypoint-init.nu /usr/bin/entrypoint-init.nu

ENV PATH="/usr/local/bin:${PATH}"

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/bin/entrypoint.sh"]
CMD ["/usr/local/bin/gaia"]
