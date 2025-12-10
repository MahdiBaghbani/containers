# Nextcloud Base Service

Base Docker image for Open Cloud Mesh Nextcloud services with integrated Nushell entrypoint system.

## Overview

`nextcloud-base` provides a foundation image for Nextcloud deployments with:

- **PHP 8.2 Apache runtime** with all required extensions
- **Nushell-based entrypoint** for initialization and lifecycle management
- **TLS certificate integration** for secure inter-service communication
- **Hook system** for custom initialization logic
- **CI volume mount support** for copy-on-write source deployment
- **OCM-specific customization** for Open Cloud Mesh requirements

## Documentation Index

- **[initialization.md](./initialization.md)** - Container initialization flow, source preparation, install/upgrade logic
- **[entrypoint.md](./entrypoint.md)** - Entrypoint system architecture, hook execution, CI patterns

## Key Concepts

### Base Image Only

`nextcloud-base` is a **base image** and should not be deployed directly. It provides:

- PHP runtime with extensions
- Apache web server configuration
- Initialization framework
- TLS integration

Deploy child images instead:

- `nextcloud` - Nextcloud server with source code
- `nextcloud-contacts` - Nextcloud with Contacts app

### Multi-Version Support

Services built on `nextcloud-base` support multiple Nextcloud versions via `versions.nuon`:

```nuon
{
  "default": "v30.0.11",
  "versions": [
    {"name": "master", "latest": false},
    {"name": "v30.0.11", "latest": true}
  ]
}
```

### TLS Integration

`nextcloud-base` automatically integrates TLS certificates:

- **Mode**: `ca-and-cert` (CA bundle + service certificate)
- **Cert Name**: `nextcloud`
- **SANs**: nextcloud1-4.docker
- **Auto-copied** during build via DockyPody TLS system

### Hook System

Supports Nextcloud's official hook system:

- `pre-installation` - Before fresh install
- `post-installation` - After fresh install
- `pre-upgrade` - Before upgrade
- `post-upgrade` - After upgrade
- `before-starting` - Before Apache starts

Place `.sh` scripts in `/docker-entrypoint-hooks.d/{hook-name}/`

## Quick Start

### Building

```bash
# Generate TLS certificates
make tls all

# Build all services
make build

# Build specific version
nu scripts/dockypody.nu build --service nextcloud --version v30.0.11
```

### Running

```bash
# Basic run
docker run -d -p 80:80 nextcloud:v30.0.11-debian

# With environment variables
docker run -d \
  -p 80:80 \
  -e NEXTCLOUD_ADMIN_USER=admin \
  -e NEXTCLOUD_ADMIN_PASSWORD=secret \
  -e MYSQL_HOST=db \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD=dbsecret \
  nextcloud:v30.0.11-debian

# With hooks
docker run -d \
  -p 80:80 \
  -v ./hooks/post-installation:/docker-entrypoint-hooks.d/post-installation:ro \
  nextcloud:v30.0.11-debian
```

## Environment Variables

### Installation

- `NEXTCLOUD_ADMIN_USER` - Admin username (required for auto-install)
- `NEXTCLOUD_ADMIN_PASSWORD` - Admin password (required for auto-install)
- `NEXTCLOUD_DATA_DIR` - Data directory (default: /var/www/html/data)
- `NEXTCLOUD_TRUSTED_DOMAINS` - Space-separated list of trusted domains

### Database

**SQLite:**

- `SQLITE_DATABASE` - Database name

**MySQL:**

- `MYSQL_HOST` - MySQL host
- `MYSQL_DATABASE` - Database name
- `MYSQL_USER` - Database user
- `MYSQL_PASSWORD` - Database password

**PostgreSQL:**

- `POSTGRES_HOST` - PostgreSQL host
- `POSTGRES_DB` - Database name
- `POSTGRES_USER` - Database user
- `POSTGRES_PASSWORD` - Database password

### Redis

- `REDIS_HOST` - Redis host (or Unix socket path)
- `REDIS_HOST_PORT` - Redis port (default: 6379)
- `REDIS_HOST_PASSWORD` - Redis password
- `REDIS_HOST_USER` - Redis username (optional)

### Apache

- `APACHE_SERVER_NAME` - Apache ServerName (overrides default)
- `APACHE_DISABLE_REWRITE_IP` - Disable remoteip module (any value)
- `NEXTCLOUD_HTTPS_MODE` - HTTPS mode control (see HTTPS Modes section below)
- `NEXTCLOUD_APACHE_LOGLEVEL` - Apache log level (default: warn)

### Maintenance

- `NEXTCLOUD_UPDATE` - Force initialization even if not apache/php-fpm (set to 1)
- `NEXTCLOUD_INIT_HTACCESS` - Update htaccess after init (any value)

## HTTPS Modes

`nextcloud-base` supports explicit HTTPS configuration via the `NEXTCLOUD_HTTPS_MODE` environment variable:

### Modes

- **`off`** (default): HTTP-only mode. Only port 80 is enabled. Use this when behind a reverse proxy (like Traefik) that handles HTTPS termination.
- **`https-only`**: HTTPS-only mode. Port 80 redirects to HTTPS, port 443 serves HTTPS. Requires TLS certificates at `/tls/server.crt` and `/tls/server.key`.
- **`http-and-https`**: Both HTTP and HTTPS enabled. Port 80 serves HTTP, port 443 serves HTTPS without forced redirect. Requires TLS certificates.

### Usage

```bash
# HTTP-only (default, for reverse proxy)
docker run -d -p 80:80 \
  -e NEXTCLOUD_HTTPS_MODE=off \
  nextcloud:v30.0.11-debian

# HTTPS-only (direct HTTPS access)
docker run -d -p 80:80 -p 443:443 \
  -e NEXTCLOUD_HTTPS_MODE=https-only \
  nextcloud:v30.0.11-debian

# Both HTTP and HTTPS
docker run -d -p 80:80 -p 443:443 \
  -e NEXTCLOUD_HTTPS_MODE=http-and-https \
  nextcloud:v30.0.11-debian
```

### TLS Requirements

For HTTPS modes (`https-only` or `http-and-https`), TLS certificates must be available at:

- `/tls/nextcloud.crt` - Server certificate
- `/tls/nextcloud.key` - Server private key

These certificates are **baked into the image at build time** when TLS is enabled in the service manifest and certificates are generated (`make tls all`). The certificate files are named after the service's `cert_name` from the service manifest (`nextcloud-base.nuon`). The build system's TLS helper (`copy-tls.nu`) copies certificates into `/tls/` during the Docker build process, ensuring they are available at runtime without requiring volume mounts.

### Configuration Source

**Canonical source**: `nextcloud-base` is the canonical source for generic Nextcloud PHP configuration files. All official Nextcloud configs from `.repos/docker/32/apache/config/` are baked into the image at build time in `services/nextcloud-base/config/`.

The OCM test suite uses `https-only` mode for WAYF (Where Are You From) tests.

## Architecture

### Components

```text
nextcloud-base
├── PHP 8.2 Apache Runtime
│   ├── Extensions: APCu, imagick, memcached, redis, gd, intl, ...
│   └── Apache Modules: rewrite, headers, remoteip, ssl, security2
├── Nushell Entrypoint System
│   ├── entrypoint.sh (bash wrapper)
│   ├── entrypoint-init.nu (orchestrator)
│   └── lib/ (modular functions)
├── TLS Integration
│   ├── CA bundle from common-tools
│   └── Service certificate (nextcloud)
└── Hook System
    └── /docker-entrypoint-hooks.d/
```

### Build Dependencies

- `common-tools` - Provides Nushell, CA bundle, utilities
- `php:8.3-apache-trixie` - Base PHP runtime

## See Also

- [initialization.md](./initialization.md) - Initialization flow details
- [entrypoint.md](./entrypoint.md) - Entrypoint architecture
- [../../docs/guides/multi-version-builds.md](../../docs/guides/multi-version-builds.md) - Version management
- [../../docs/concepts/tls-management.md](../../docs/concepts/tls-management.md) - TLS system
