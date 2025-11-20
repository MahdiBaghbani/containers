# Reva Service Architecture

This document describes the generic Reva service architecture and multi-container deployment patterns.

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
