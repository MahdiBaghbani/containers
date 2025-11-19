# CERNBox Architecture

This document describes the architecture of the CERNBox multi-container deployment.

## Architecture Overview

CERNBox follows a microservices architecture pattern, with services split across multiple containers for isolation, scalability, and maintainability. The architecture follows the CERN production deployment pattern.

## System Architecture Diagram

```mermaid
graph TB
    subgraph "External"
        User[User Browser]
        Traefik[Traefik Reverse Proxy]
    end

    subgraph "Frontend"
        Web[CERNBox Web<br/>Port 80]
    end

    subgraph "Gateway Layer"
        Gateway[Gateway Container<br/>Port 9142 gRPC<br/>Port 80 HTTP]
        AuthReg[Auth Registry]
        AppReg[App Registry]
        StorageReg[Storage Registry]
        Preferences[Preferences]
    end

    subgraph "Auth Providers"
        OIDC[OIDC Auth Provider<br/>Port 9158]
        Machine[Machine Auth Provider<br/>Port 9166]
        OCMShare[OCM Shares Auth Provider<br/>Port 9278]
        IdP[Keycloak IdP<br/>Port 8080]
    end

    subgraph "Data Providers"
        Localhome[Localhome Dataprovider<br/>Port 9143]
        OCM[OCM Dataprovider<br/>Port 9146]
        ScienceMesh[ScienceMesh Dataprovider<br/>Port 9147]
    end

    subgraph "User/Share Providers"
        ShareProv[Share Providers<br/>Port 9144]
        UserProv[User/Group Providers<br/>Port 9145]
    end

    User --> Traefik
    Traefik --> Web
    Web --> Gateway
    Gateway --> AuthReg
    Gateway --> AppReg
    Gateway --> StorageReg
    Gateway --> Preferences
    Gateway --> OIDC
    Gateway --> Machine
    Gateway --> OCMShare
    Gateway --> ShareProv
    Gateway --> UserProv
    Gateway --> Localhome
    Gateway --> OCM
    Gateway --> ScienceMesh
    OIDC --> IdP
```

## Container Architecture

```mermaid
graph LR
    subgraph "Gateway Container"
        G1[gateway]
        G2[authregistry]
        G3[appregistry]
        G4[storageregistry]
        G5[preferences]
        G6[ocminvitemanager]
        G7[ocmproviderauthorizer]
        G8[spacesregistry]
    end

    subgraph "Share Providers Container"
        S1[usershareprovider]
        S2[publicshareprovider]
        S3[ocmshareprovider]
    end

    subgraph "User/Group Providers Container"
        U1[userprovider]
        U2[groupprovider]
    end

    subgraph "Auth Provider Containers"
        A1[OIDC Provider]
        A2[Machine Provider]
        A3[OCM Shares Provider]
    end

    subgraph "Dataprovider Containers"
        D1[Localhome]
        D2[OCM]
        D3[ScienceMesh]
    end

    G1 --> S1
    G1 --> S2
    G1 --> S3
    G1 --> U1
    G1 --> U2
    G1 --> A1
    G1 --> A2
    G1 --> A3
    G1 --> D1
    G1 --> D2
    G1 --> D3
```

## Service Communication Flow

### Authentication Flow

```mermaid
sequenceDiagram
    participant User
    participant Web
    participant Gateway
    participant AuthReg
    participant OIDC
    participant IdP

    User->>Web: Login Request
    Web->>Gateway: Authenticate
    Gateway->>AuthReg: Get Auth Provider
    AuthReg->>Gateway: OIDC Provider Address
    Gateway->>OIDC: Authenticate Token
    OIDC->>IdP: Validate Token
    IdP->>OIDC: Token Valid
    OIDC->>Gateway: User Info
    Gateway->>Web: Authentication Success
    Web->>User: Redirect to Dashboard
```

### Data Access Flow

```mermaid
sequenceDiagram
    participant User
    participant Web
    participant Gateway
    participant StorageReg
    participant Dataprovider
    participant UserProv

    User->>Web: Request File
    Web->>Gateway: Get File (with token)
    Gateway->>UserProv: Validate User
    UserProv->>Gateway: User Valid
    Gateway->>StorageReg: Get Storage Provider
    StorageReg->>Gateway: Dataprovider Address
    Gateway->>Dataprovider: Get File
    Dataprovider->>Gateway: File Data
    Gateway->>Web: File Response
    Web->>User: Display File
```

## Container Responsibilities

### Gateway Container

- **Services:** gateway, authregistry, appregistry, storageregistry, preferences, ocminvitemanager, ocmproviderauthorizer, spacesregistry
- **Port:** 9142 (gRPC), 80 (HTTP)
- **Role:** Central routing and coordination point
- **Config:** `cernbox-gateway.toml`

### Share Providers Container

- **Services:** usershareprovider, publicshareprovider, ocmshareprovider
- **Port:** 9144 (gRPC)
- **Role:** Manages file and folder sharing
- **Config:** `cernbox-shareproviders.toml`

### User/Group Providers Container

- **Services:** userprovider, groupprovider
- **Port:** 9145 (gRPC)
- **Role:** User and group management
- **Config:** `cernbox-groupuserproviders.toml`

### Auth Provider Containers

- **OIDC Provider:** Port 9158 - OIDC/OAuth2 authentication
- **Machine Provider:** Port 9166 - Machine-to-machine authentication
- **OCM Shares Provider:** Port 9278 - OCM share authentication

### Dataprovider Containers

- **Localhome:** Port 9143 - Local storage provider
- **OCM:** Port 9146 - OCM storage provider
- **ScienceMesh:** Port 9147 - ScienceMesh storage provider

## Service Addressing

The gateway uses explicit addresses for all external services:

- **Template Variables:** Used for same-container services (e.g., `{{ grpc.services.authregistry.address }}`)
- **Placeholders:** Used for external container services (e.g., `{{placeholder:shareproviders.address}}`)

See [Configuration](configuration.md) for details on service addressing.

## Benefits of This Architecture

1. **Isolation:** Service failures don't affect other services
2. **Scalability:** Services can be scaled independently
3. **Maintainability:** Clear separation of concerns
4. **Debugging:** Easier to identify issues in specific services
5. **CERN Compatibility:** Matches CERN production deployment pattern

## Related Documentation

- [Port Assignments](ports.md) - Complete port reference
- [Services](services.md) - Detailed service descriptions
- [Configuration](configuration.md) - Configuration details
