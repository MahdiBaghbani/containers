<!--
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
-->
# TLS Certificate Management

## Overview

The DockyPody build system implements selective TLS certificate copying to minimize image size and security surface. Services copy only their own service certificates, while CA certificates are centralized in `common-tools` and shared via trust store bundles.

The system supports three TLS modes:

- **`ca-only`**: Service only needs CA certificate (e.g., `common-tools` for trust store)
- **`ca-and-cert`** (default): Service needs both CA and service certificate
- **`cert-only`**: Service uses public CAs, only needs service certificate

## Certificate Structure

```text
tls/
├── certificate-authority/        # Shared CA (repo root)
│   ├── ca.json                   # CA metadata
│   ├── {ca-name}.crt             # CA certificate
│   └── {ca-name}.key             # CA private key
└── services/
    └── {service}/tls/
        ├── certificate-authority/  # Service-local CA copy
        │   ├── {ca-name}.crt
        │   └── {ca-name}.key
        └── certificates/           # Service certificates
            ├── {cert-name}.crt
            └── {cert-name}.key
```

## Service Configuration

Services declare TLS requirements in their `.nuon` config. The `mode` field is **REQUIRED** when `enabled: true`:

```nuon
{
  "name": "revad-base",
  "tls": {
    "enabled": true,
    "mode": "ca-and-cert",  // REQUIRED when enabled=true
    "cert_name": "reva",    // Required for ca-and-cert and cert-only modes
    "instances": 1,
    "domain_suffix": "docker",
    "sans": [
      "DNS:revad1.docker",
      "DNS:revad2.docker"
    ]
  }
}
```

### TLS Modes

**`ca-only`**: Service only needs CA certificate

- No service certificate required
- CA bundle copied from `common-tools` dependency via `COPY --from`
- `cert_name` optional (warning if provided)
- Example: `common-tools` service (provides CA bundle to other services)

**`ca-and-cert`**: Service needs both CA and service certificate (default)

- CA bundle from `common-tools` dependency
- Service-specific certificate
- `cert_name` required
- Example: `revad-base`, `idp`, `cernbox-web`

**`cert-only`**: Service only needs service certificate (public CA scenarios)

- No internal CA bundle needed (uses public CA from base image)
- Only service-specific certificate
- `cert_name` required
- Example: Services connecting to external APIs with Let's Encrypt certificates

### Configuration Restrictions

#### CRITICAL RESTRICTIONS

- **TLS config in `platforms.nuon` is FORBIDDEN** - validation error if present
- **TLS config in version overrides (`versions.nuon`) is FORBIDDEN** - validation error if present
- **TLS must be configured in base service config only**
- **Services with TLS enabled MUST have `common-tools` dependency** (validation error if missing, except for `common-tools` itself)

#### Common-Tools Pattern

The `common-tools` service typically uses `mode: "ca-only"` because it provides the CA bundle to other services via `COPY --from` and doesn't need a service-specific certificate. This is a documented pattern, not a hardcoded validation rule.

## Build-Time TLS Processing

During build, the system:

1. **CA Sync & Validation** (automatic)
   - Compares service CA with shared CA (hash comparison)
   - Validates certificate issuer against CA subject (OpenSSL)
   - Auto-syncs shared CA to service directory if mismatched
   - For `common-tools`: CA automatically synced and processed into platform-specific trust store bundle
   - Prints certificate expiration info (non-blocking warnings)

2. **Build Arg Injection**
   - `TLS_ENABLED` - "true" or "false"
   - `TLS_MODE` - TLS mode: "ca-only", "ca-and-cert", or "cert-only" (system-managed, env var override rejected)
   - `TLS_CERT_NAME` - Service certificate name (e.g., "reva")
   - `TLS_CA_NAME` - CA name from metadata (e.g., "dockypody")

**Note:** `TLS_MODE` is system-managed from config. Environment variable `TLS_MODE` is ignored with a warning if set.

1. **Selective Copying**
   - Helper script `copy-tls.nu` copied to service context (if TLS enabled and mode is not `ca-only`)
   - During Docker build:
     - Services copy CA bundle from `common-tools` dependency using `COPY --from` (conditionally used based on mode)
     - For `ca-only` mode: Only CA bundle copied, `copy-tls.nu` is NOT called
     - For `ca-and-cert` and `cert-only` modes: Services copy only their own service certificate via `copy-tls.nu`
     - For `cert-only` mode: CA bundle is copied but not used (uses public CA from base image)
     - All other certificates excluded (smaller, more secure images)
   - Source TLS directories removed after selective copy

## Dockerfile Pattern

Multi-stage builds require ARG re-declaration after each `FROM`:

```dockerfile
ARG BASE_BUILD_IMAGE="golang:1.25-trixie"
ARG BASE_RUNTIME_IMAGE="debian:trixie-slim"
ARG COMMON_TOOLS_RUNTIME_IMAGE="common-tools:v1.0.0-debian"

# TLS build args (declared at top level)
ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"  # Default fallback - build system always provides explicit value or errors
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

FROM ${BASE_BUILD_IMAGE} AS build
# ... build stage ...

FROM ${BASE_RUNTIME_IMAGE}

# Re-declare TLS build args for runtime stage
ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"  # Default fallback - build system always provides explicit value or errors
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""
ARG COMMON_TOOLS_RUNTIME_IMAGE  # Build arg name is flexible - can be COMMON_TOOLS_IMAGE, COMMON_TOOLS_RUNTIME_IMAGE, etc.

# Copy CA bundle from common-tools (always copy, conditionally use)
# NOTE: Stage name is flexible - services can use any name (e.g., "compress", "common-tools", "common-tools-runtime")
# For cert-only mode, we still COPY but don't use it (minimal waste, simpler than buildkit conditional)
COPY --from=common-tools-runtime /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "cert-only" ]; then \
        mkdir -p /etc/ssl/certs && \
        cp /tmp/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt && \
        echo "CA bundle copied from common-tools"; \
    else \
        echo "Cert-only mode: Skipping internal CA bundle (using public CA from base image)"; \
    fi && \
    rm -f /tmp/ca-bundle.crt

# Copy nushell from common-tools (required for copy-tls.nu)
# NOTE: Nushell must be available for copy-tls.nu to work
# HARD REQUIREMENT: common-tools dependency is validated before build
# NOTE: Stage name matches the FROM stage name used for common-tools
COPY --chmod=755 --from=common-tools-runtime /usr/local/bin/nu /usr/local/bin/nu

# Copy TLS directories and helper script
# NOTE: Build system automatically copies canonical copy-tls.nu to service context via prepare-tls-context
# NOTE: For ca-only mode, copy-tls.nu is NOT copied (optimization)
# Dockerfile COPY cannot be conditional - if files don't exist, COPY fails
# Solution: Use RUN step with shell to copy conditionally (loses some layer caching, but necessary)
RUN mkdir -p /tmp/tls-source /tmp && \
    if [ -d ./tls ]; then cp -r ./tls/* /tmp/tls-source/ 2>/dev/null || true; fi && \
    if [ -f ./scripts/tls/copy-tls.nu ]; then cp ./scripts/tls/copy-tls.nu /tmp/copy-tls.nu; fi

# Selective TLS certificate copying
# NOTE: ca-only mode does NOT call copy-tls.nu (CA bundle handled by COPY --from above)
# NOTE: COPY commands above may fail if files don't exist (ca-only mode), handle in RUN
RUN if [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" = "ca-only" ]; then \
        echo "CA-only mode: CA bundle copied via COPY --from=common-tools, copy-tls.nu skipped" && \
        rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    elif [ "$TLS_ENABLED" = "true" ] && [ "$TLS_MODE" != "ca-only" ]; then \
        if [ ! -f /tmp/copy-tls.nu ]; then \
            echo "Error: copy-tls.nu not found. This should not happen for non-ca-only modes." && exit 1; \
        fi && \
        nu /tmp/copy-tls.nu \
        --enabled "$TLS_ENABLED" \
        --mode "$TLS_MODE" \
        --ca-name "$TLS_CA_NAME" \
        --cert-name "$TLS_CERT_NAME" \
        --source-certs /tmp/tls-source/certificates/ \
        --dest /tls/ && \
        rm -rf /tmp/tls-source /tmp/copy-tls.nu; \
    else \
        rm -rf /tmp/tls-source /tmp/copy-tls.nu || true; \
    fi
```

## Helper Scripts

**`scripts/tls/copy-tls.nu`** - Nushell (primary implementation)

- Used by services with `ca-and-cert` or `cert-only` modes
- **NOT called** for `ca-only` mode (CA bundle handled by Dockerfile COPY only)
- Requires nushell to be available in the image (provided via `common-tools` dependency)
- Copies only service-specific certificates (CA bundle handled separately via `common-tools`)
- Automatically copied to service context by build system (canonical version from `scripts/tls/copy-tls.nu`)
- Parameters:
  - `--enabled`: "true" or "false"
  - `--mode`: TLS mode - "ca-and-cert" or "cert-only" (required, provided by build system)
  - `--ca-name`: CA certificate name (required for multi-CA readiness)
  - `--cert-name`: Service certificate name (required for ca-and-cert and cert-only modes)
  - `--source-certs`: Source directory for service certificates
  - `--dest`: Destination directory

## Certificate Generation

```bash
# Generate shared CA
nu scripts/tls/generate-ca.nu

# Generate all service certificates
nu scripts/tls/generate-all-certs.nu

# Generate specific service certificate
nu scripts/tls/generate-cert.nu --service revad-base
```

## CA Mismatch Resolution

When service CA differs from shared CA (for `ca-and-cert` and `ca-only` modes):

```text
WARNING: CA Mismatch for service 'revad-base':
   - Shared CA: org.opencloudmesh.certificate.authority (hash: 9cd30e0cd...)
   - Service CA: org.opencloudmesh.certificate.authority (hash: f2c1183b5...)
   - Validating certificate issuer...
   OK: Certificate 'reva.crt' issuer matches: shared CA
   -> Copying shared CA to service directory
   -> Service certificates belong to shared CA
```

Build system automatically resolves by copying correct CA based on certificate issuer validation.

**Note:** For `cert-only` mode, CA validation and sync are skipped entirely (service uses public CA).

## CA Propagation to Common-Tools

The build system automatically handles CA propagation to `common-tools`:

1. **Automatic CA Sync**:
   - When building `common-tools` with TLS enabled, `sync-and-validate-ca` automatically copies the shared CA from `tls/certificate-authority/` to `services/common-tools/tls/certificate-authority/`
   - No manual file copying required
   - Uses `TLS_CA_NAME` build arg to copy specific CA file (multi-CA readiness)

2. **Automatic Trust Store Generation**:
   - Dockerfile `COPY ./tls/certificate-authority/` includes the synced CA files
   - Platform-appropriate trust store update command runs automatically:
     - Debian/Alpine: `update-ca-certificates` -> `/etc/ssl/certs/ca-certificates.crt`
     - RHEL: `update-ca-trust extract` -> `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`
   - CA bundle generated at platform-specific path
   - Uses `TLS_CA_NAME` to copy specific CA file: `${TLS_CA_NAME}.crt`

3. **Service Consumption**:
   - Dependent services copy CA bundle from `common-tools` using `COPY --from=common-tools-runtime`
   - No need to copy individual CA certificate files
   - Services only copy their own service certificates via `copy-tls.nu` (for `ca-and-cert` and `cert-only` modes)
   - For `ca-only` mode, only CA bundle is copied (no service certificate)

## Error Handling

### Missing or Invalid CA Metadata

- If `tls/certificate-authority/ca.json` is missing or invalid, build aborts with detailed error message
- Error message: "CA metadata file not found: tls/certificate-authority/ca.json. Please run scripts/tls/generate-ca.nu first"
- CA generation is a prerequisite - build system does not attempt recovery

## Benefits

- **Smaller Images** - Only service-specific certificate files included (CA bundle shared via common-tools)
- **Better Security** - Services only have access to their own certificates
- **Automatic Sync** - CA automatically synced to services and common-tools during build
- **Build Validation** - Certificate expiration and issuer checked at build time
- **Centralized CA Management** - CA bundle generated once in common-tools, shared across all services
- **Flexible Modes** - Support for CA-only, CA-and-cert, and cert-only scenarios
- **Multi-CA Ready** - Infrastructure supports multiple CAs (currently single CA, but ready for expansion)

## See Also

- [Service Configuration](service-configuration.md) - How TLS is configured in service configs
- [Build System](build-system.md) - How TLS build args are injected
- [Dependency Management](dependency-management.md) - How common-tools dependency provides CA bundle
