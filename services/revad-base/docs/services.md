# Reva Services Reference

Detailed description of generic Reva services and their responsibilities.

## Gateway Service

**Config File:** `gateway.toml`

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

### Gateway Responsibilities

- Central routing point for all requests
- Authentication routing via auth registry
- Storage routing via storage registry
- Application registry management
- User preferences management

## Share Providers Service

**Config File:** `shareproviders.toml`

### Share Provider Services

- **usershareprovider** - User-to-user file sharing
- **publicshareprovider** - Public link sharing
- **ocmshareprovider** - OCM cross-site sharing
- **ocmincoming** - OCM incoming share management (receives shares from remote providers)

### Share Provider Responsibilities

- Manage file and folder shares
- Generate share tokens
- Validate share access
- OCM share coordination

### Share Provider Storage Drivers

- **Memory:** Used for usershareprovider and publicshareprovider (can be upgraded to SQL)
- **JSON:** Used for ocmshareprovider and ocmincoming (shares stored in JSON file, both services use the same file)

## User/Group Providers Service

**Config File:** `groupuserproviders.toml`

### User/Group Provider Services

- **userprovider** - User management
- **groupprovider** - Group management

### User/Group Provider Responsibilities

- User authentication and authorization
- User metadata management
- Group membership management
- User/group lookups

### User/Group Provider Storage Drivers

- **JSON:** Used for both userprovider and groupprovider (can be upgraded to REST/LDAP)

## Auth Provider Services

### OIDC Auth Provider

**Config File:** `authprovider-oidc.toml`

**Purpose:** Handles OIDC/OAuth2 authentication

**Features:**

- Bearer token validation
- OIDC token exchange
- User information retrieval

### Machine Auth Provider

**Config File:** `authprovider-machine.toml`

**Purpose:** Handles machine-to-machine authentication

**Features:**

- API key validation
- Machine token generation
- Service authentication

### OCM Shares Auth Provider

**Config File:** `authprovider-ocmshares.toml`

**Purpose:** Handles authentication for OCM cross-site shares

**Features:**

- OCM share token validation
- Cross-site authentication
- Share access authorization

### Public Shares Auth Provider

**Config File:** `authprovider-publicshares.toml`

**Purpose:** Handles authentication for public link shares

**Features:**

- Public share token validation
- Share access authorization

## Dataprovider Services

### Localhome Dataprovider

**Config File:** `dataprovider-localhome.toml`

**Purpose:** Local storage provider for user files

**Storage:** Local filesystem storage

### OCM Dataprovider

**Config File:** `dataprovider-ocm.toml`

**Purpose:** OCM storage provider for cross-site file access

**Storage:** OCM protocol storage

### ScienceMesh Dataprovider

**Config File:** `dataprovider-sciencemesh.toml`

**Purpose:** ScienceMesh storage provider for received shares

**Storage:** OCM received storage

## Service Dependencies

Services communicate via gRPC:

- Gateway → Share Providers
- Gateway → User/Group Providers
- Gateway → Auth Providers
- Gateway → Dataproviders
- Auth Providers → External IdP (for OIDC)

## Related Documentation

- [Architecture](architecture.md) - Service architecture overview
- [Container Modes](container-modes.md) - Container mode system
- [Configuration](configuration.md) - Configuration details
