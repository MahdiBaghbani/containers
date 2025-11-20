# CERNBox Multi-Container Deployment Documentation

This documentation covers the CERNBox multi-container deployment architecture, configuration, and deployment procedures.

## Overview

CERNBox is deployed as a microservices architecture following the CERN production pattern. Services are split across multiple containers for better isolation, scalability, and maintainability.

## Documentation Structure

- **[Architecture](architecture.md)** - CERNBox-specific architecture and container deployment
- **[Port Assignments](ports.md)** - CERNBox port assignments (CERN production pattern)
- **[Services](services.md)** - CERNBox container deployment details
- **[Configuration](configuration.md)** - CERNBox-specific configuration and environment variables
- **[Deployment](deployment.md)** - CERNBox deployment procedures and troubleshooting

## Generic Reva Documentation

For generic Reva service documentation (service descriptions, placeholder system, initialization process), see:

- **[Reva Base Documentation](../../revad-base/docs/README.md)** - Generic Reva service documentation
- **[Reva Services](../../revad-base/docs/services.md)** - Generic service descriptions
- **[Reva Configuration](../../revad-base/docs/configuration.md)** - Configuration system and placeholder processing
- **[Reva Initialization](../../revad-base/docs/initialization.md)** - Initialization scripts and process
- **[Reva Container Modes](../../revad-base/docs/container-modes.md)** - Container mode system
- **[Reva Development Workflow](../../revad-base/docs/development-workflow.md)** - Development → production workflow

## Quick Reference

### Container Count

- **Total Containers:** 11
  - 1 Gateway container
  - 3 Auth provider containers (OIDC, Machine, OCM Shares)
  - 2 Provider containers (Share Providers, User/Group Providers)
  - 3 Dataprovider containers (Localhome, OCM, ScienceMesh)
  - 1 IdP container (Keycloak)
  - 1 Web frontend container

### Key Ports

- **Gateway:** 9142 (gRPC), 80 (HTTP)
- **Share Providers:** 9144 (gRPC)
- **User/Group Providers:** 9145 (gRPC)
- **Auth Providers:** 9158 (OIDC), 9166 (Machine), 9278 (OCM Shares)
- **Dataproviders:** 9143 (Localhome), 9146 (OCM), 9147 (ScienceMesh)

See [Port Assignments](ports.md) for complete reference.

## Architecture Highlights

- **Microservices Pattern:** Services separated into dedicated containers
- **Explicit Service Addressing:** Gateway uses explicit addresses for all external services
- **Port Isolation:** Each service runs on a unique gRPC port
- **CERN Production Pattern:** Follows CERN production deployment structure

See [Architecture](architecture.md) for detailed diagrams and explanations.

## Getting Started

1. Review [Architecture](architecture.md) to understand the system structure
2. Check [Port Assignments](ports.md) for port configuration
3. Configure environment variables (see [Configuration](configuration.md))
4. Deploy using Docker Compose (see [Deployment](deployment.md))

## Related Documentation

- [Reva Base Scripts Tests](../../../services/revad-base/tests/README.md) - Test suite documentation
