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

# Build system constants

export const TAG_LATEST = "latest"
export const TAG_LOCAL = "local"

export const ARCH_MAPPINGS = {
    "x86_64": "linux/amd64",
    "amd64": "linux/amd64",
    "aarch64": "linux/arm64",
    "arm64": "linux/arm64",
    "armv7l": "linux/arm/v7",
    "armhf": "linux/arm/v7",
    "armv6l": "linux/arm/v6"
}

export const GITHUB_REGISTRY = "ghcr.io"
export const REGISTRY_USER_OAUTH = "oauth2"

export const CERT_VALIDITY_DAYS = 36500
export const CERT_COUNTRY = "CH"
export const CERT_STATE = "Geneva"
export const CERT_LOCALITY = "Geneva"
export const CERT_ORGANIZATION = "Open Cloud Mesh"
export const CERT_GLOBAL_SANS = [
    "DNS:localhost",
    "IP:127.0.0.1",
    "IP:::1"
]

export const TLS_DIR_CA = "tls/certificate-authority"
export const TLS_DIR_CERTS = "tls/certificates"
export const CA_METADATA_FILE = "tls/certificate-authority/ca.json"

export const PROGRESS_AUTO = "auto"
export const PROGRESS_PLAIN = "plain"
export const PROGRESS_TTY = "tty"

export const LABEL_IMAGE_SOURCE = "org.opencontainers.image.source"
export const LABEL_IMAGE_REVISION = "org.opencontainers.image.revision"
export const LABEL_SERVICE = "org.opencloudmesh.service"

# System-owned label namespace (reserved for build system, not user-overridable)
export const LABEL_SYSTEM_PREFIX = "org.opencloudmesh.system."
export const LABEL_SERVICE_DEF_HASH = "org.opencloudmesh.system.service-def-hash"

export const DEFAULT_BUILD_ARGS = {
    "COMMIT_SHA": "local",
    "VERSION": "local"
}

export const ERR_CA_NOT_FOUND = "CA metadata file not found. Please run scripts/tls/generate-ca.nu first"
export const ERR_SERVICE_NOT_FOUND = "Service not found. Run 'make list-services' to see available services"
export const ERR_MANIFEST_NOT_FOUND = "Version manifest not found. All services must have version manifests."
export const ERR_REPO_ROOT = "This script must be run from the repository root"

export const PATTERN_SERVICE_CONFIG = "services/*.nuon"
export const PATTERN_SERVICE_MANIFEST = "services/*/versions.nuon"
export const EXCLUDE_SERVICE_FILES = ["versions.nuon"]

export const DEFAULT_TLS_INSTANCES = 1
export const HASH_DISPLAY_LENGTH = 8

export const GHA_CACHE_SCOPE = "ocm-containers"
export const GHA_CACHE_MODE = "max"
