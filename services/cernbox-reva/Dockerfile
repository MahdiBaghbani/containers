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

ARG REVA_BASE_IMAGE="reva-base:v3.3.2"

FROM ${REVA_BASE_IMAGE}

# Copy configuration files for revad into the container.
# These configurations will control revad behavior at runtime.
COPY ./configs /configs/revad


# the following is a workaround for the reva localfs storage driver, 
# which currently expects this path, taken from Giuseppe @glpatcern:
# https://github.com/sciencemesh/dev-stock/blob/b5a1bf263105faf9d2e6d967a2fa78c6b354004a/sciencemesh/scripts/testing-sciencemesh.sh#L144

RUN mkdir /revashares

RUN mkdir -p /revalocalstorage/data/marie/marie
RUN mkdir -p /revalocalstorage/data/einstein/einstein
