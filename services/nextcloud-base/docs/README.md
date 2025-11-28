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
nu scripts/build.nu --service nextcloud --version v30.0.11
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

- `APACHE_RUN_USER` - Apache user (default: www-data)
- `APACHE_RUN_GROUP` - Apache group (default: www-data)
- `APACHE_DISABLE_REWRITE_IP` - Disable remoteip module (any value)

### Maintenance

- `NEXTCLOUD_UPDATE` - Force initialization even if not apache/php-fpm (set to 1)
- `NEXTCLOUD_INIT_HTACCESS` - Update htaccess after init (any value)

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
