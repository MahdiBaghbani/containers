# Reva Service Architecture

This document describes the generic Reva service architecture and multi-container deployment patterns.

## Build Tuple and Config Bands

DockyPody images for CERNBox-style stacks are built from a version-aligned
tuple:

- **reva** (`revad` source ref, for example `master` or `v3.10.1`)
- **reva-plugins** (CERNBox plugin tree; pinned per release band)
- **revad-base** (generic Reva configs, init scripts, and image layers)

`revad-base` publishes `master` and `v3.10.1` image versions. Downstream
services such as `cernbox-revad` depend on matching `revad-base` platform
tags (for example `v3.10.1-production`) and matching source refs.

During the development image build (`Dockerfile.development`), config shape
is selected by the `REVA_CONFIG_BAND` build arg via `resolve_configs`,
writing resolved templates to `/configs/revad`. Production image builds do
not invoke `resolve_configs` and ship no config templates; production
containers read pre-processed configs from `/etc/revad` volumes populated by
development containers. See [Development Workflow](development-workflow.md).
Neither image type re-runs band resolution at runtime.

| Band      | Overlay dir              | Typical use                          |
|-----------|--------------------------|--------------------------------------|
| `master`  | `configs-overlays/master`| Latest Reva line; overlay replaces   |
|           |                          | core files (e.g. `webapp_endpoint`)  |
| `v3.10.1` | none (core-only)         | Released line; core `configs/` only  |

The legacy `v3.3.3` version line is no longer published. Use `v3.10.1` for
the stable release band or `master` for the development line.

## Architecture Overview

Reva services can be deployed in a microservices architecture pattern, with services split across multiple containers for isolation, scalability, and maintainability.

## Service Architecture

### Gateway Services

The gateway container runs multiple services:

- **gateway** - Main gateway service, routes requests to appropriate providers
- **authregistry** - Maps authentication types to auth providers
- **appregistry** - Manages application registry (MIME types, apps)
- **storageregistry** - Maps storage paths to dataproviders
- **preferences** - User preferences storage
- **ocminvitemanager** - OCM invitation management
- **ocmproviderauthorizer** - OCM provider authorization
- **spacesregistry** - Spaces registry service

### Storage Providers (Dataproviders)

Storage providers handle file storage:

- **localhome** - Local filesystem storage provider
- **ocm** - OCM protocol storage provider
- **sciencemesh** - ScienceMesh storage provider (OCM received storage)

### Authentication Providers

Authentication providers handle different authentication methods:

- **oidc** - OIDC/OAuth2 authentication
- **machine** - Machine-to-machine authentication
- **ocmshares** - OCM cross-site share authentication
- **publicshares** - Public link share authentication

### Share Providers

Share providers manage file and folder sharing:

- **usershareprovider** - User-to-user file sharing
- **publicshareprovider** - Public link sharing
- **ocmshareprovider** - OCM cross-site sharing
- **ocmincoming** - OCM incoming share management (receives shares from remote providers)

### User/Group Providers

User and group providers handle identity management:

- **userprovider** - User management
- **groupprovider** - Group management

## Service Communication

### Communication Patterns

- **gRPC**: Used for all inter-service communication
- **HTTP**: Used for external access and data transfer
- **Internal DNS**: Container names resolve automatically via Docker networking

### Service Addressing

The gateway uses explicit addresses for all external services:

- **Template Variables**: Used for same-container services (e.g., `{{ grpc.services.authregistry.address }}`)
- **Placeholders**: Used for external container services (e.g., `{{placeholder:shareproviders.address}}`)

See [Configuration](configuration.md) for details on service addressing.

## Multi-Container Pattern

### Benefits

1. **Isolation**: Service failures don't affect other services
2. **Scalability**: Services can be scaled independently
3. **Maintainability**: Clear separation of concerns
4. **Debugging**: Easier to identify issues in specific services

### Container Organization

Each container runs in a specific mode (see [Container Modes](container-modes.md)):

- One container per service type (gateway, dataprovider, authprovider, etc.)
- Each container uses mode-specific configuration
- Containers communicate via gRPC using explicit addresses

## Related Documentation

- [Container Modes](container-modes.md) - Container mode system
- [Services](services.md) - Detailed service descriptions
- [Configuration](configuration.md) - Configuration and service addressing
