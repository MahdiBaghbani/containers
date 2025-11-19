# Port Assignments

Complete reference for all ports used in the CERNBox multi-container deployment.

## Port Assignment Table

| Service                      | Container Name                                  | gRPC Port | HTTP Port | Protocol    |
| ---------------------------- | ----------------------------------------------- | --------- | --------- | ----------- |
| **Gateway**                  | `cernbox-1-test-revad-gateway`                  | 9142      | 80        | HTTP        |
| **Share Providers**          | `cernbox-1-test-revad-shareproviders`           | 9144      | -         | gRPC only   |
| **User/Group Providers**     | `cernbox-1-test-revad-groupuserproviders`       | 9145      | -         | gRPC only   |
| **Auth Provider OIDC**       | `cernbox-1-test-revad-authprovider-oidc`        | 9158      | -         | gRPC only   |
| **Auth Provider Machine**    | `cernbox-1-test-revad-authprovider-machine`     | 9166      | -         | gRPC only   |
| **Auth Provider OCM Shares** | `cernbox-1-test-revad-authprovider-ocmshares`   | 9278      | -         | gRPC only   |
| **Dataprovider Localhome**   | `cernbox-1-test-revad-dataprovider-localhome`   | 9143      | 80        | HTTP + gRPC |
| **Dataprovider OCM**         | `cernbox-1-test-revad-dataprovider-ocm`         | 9146      | 80        | HTTP + gRPC |
| **Dataprovider ScienceMesh** | `cernbox-1-test-revad-dataprovider-sciencemesh` | 9147      | 80        | HTTP + gRPC |
| **IdP (Keycloak)**           | `cernbox-1-test-idp`                            | -         | 8080      | HTTPS       |
| **Web Frontend**             | `cernbox-1-test-web`                            | -         | 80        | HTTP        |

## Port Allocation Strategy

Ports are allocated following the CERN production pattern:

- **9000-9199:** Core Reva services (gateway, providers, dataproviders)
- **9200-9299:** Extended services (OCM Shares auth provider)
- **8000-8099:** External services (IdP, Web)

### Port Groups

#### Core Services (9142-9147)

- `9142` - Gateway (main entry point)
- `9143` - Localhome Dataprovider
- `9144` - Share Providers
- `9145` - User/Group Providers
- `9146` - OCM Dataprovider
- `9147` - ScienceMesh Dataprovider

#### Auth Providers (9158-9278)

- `9158` - OIDC Auth Provider (matches CERN production)
- `9166` - Machine Auth Provider (matches CERN production)
- `9278` - OCM Shares Auth Provider (matches CERN production)

#### External Services

- `8080` - Keycloak IdP
- `80` - HTTP services (Gateway, Dataproviders, Web)

## Port Conflicts Resolution

The following ports were adjusted to avoid conflicts:

- **OCM Dataprovider:** Changed from `9144` to `9146` (9144 reserved for Share Providers)
- **ScienceMesh Dataprovider:** Changed from `9145` to `9147` (9145 reserved for User/Group Providers)

## Environment Variables

Port assignments are configured via environment variables in `env`:

```bash
# Gateway
REVAD_GATEWAY_GRPC_PORT=9142

# Share Providers
REVAD_SHAREPROVIDERS_GRPC_PORT=9144

# User/Group Providers
REVAD_GROUPUSERPROVIDERS_GRPC_PORT=9145

# Auth Providers
REVAD_AUTHPROVIDER_OIDC_GRPC_PORT=9158
REVAD_AUTHPROVIDER_MACHINE_GRPC_PORT=9166
REVAD_AUTHPROVIDER_OCMSHARES_GRPC_PORT=9278

# Dataproviders
REVAD_DATAPROVIDER_LOCALHOME_GRPC_PORT=9143
REVAD_DATAPROVIDER_OCM_GRPC_PORT=9146
REVAD_DATAPROVIDER_SCIENCEMESH_GRPC_PORT=9147
```

## Network Communication

All containers communicate via Docker's internal network (`traefik-net`):

- **gRPC:** Used for inter-service communication
- **HTTP:** Used for external access (via Traefik) and dataprovider data transfer
- **Internal DNS:** Container names resolve to container IPs

## Port Verification

To verify port assignments:

```bash
# Check environment variables
grep GRPC_PORT env

# Check docker-compose services
docker-compose config | grep -A 5 "container_name:"

# Check running containers
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

## Related Documentation

- [Architecture](architecture.md) - System architecture and service relationships
- [Services](services.md) - Detailed service descriptions
- [Configuration](configuration.md) - Configuration files and environment variables
