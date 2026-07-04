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

### Config Band Note

The `master` band overlay replaces whole `gateway.toml` (for example
`enable_code_flow = true`); the `v3.10.1` core-only band keeps core defaults.
Band resolution runs during the development image build only. See
[Configuration](configuration.md#config-band-resolver) and
[Architecture](architecture.md#build-tuple-and-config-bands) for field-level
differences.

## Share Providers Service

**Config File:** `shareproviders.toml`

### Config Band Note

The `master` band replaces whole `shareproviders.toml` (`webapp_endpoint` vs
core `webapp_template`); `v3.10.1` keeps the core file. This is a band
overlay difference, not a global field rename. See
[Configuration](configuration.md#example-master-vs-v3101).

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

### OCM Share Code Auth Provider

**Config File:** `authprovider-ocmsharecode.toml`

**Purpose:** Validates share-exchange codes for `/ocm/token` style handoffs.

**Features:**

- Share code validation
- Exchange-token handoff support
- OCM code-flow integration

### OCM Exchanged Token Auth Provider

**Config File:** `authprovider-ocmexchangedtoken.toml`

**Purpose:** Validates exchanged JWTs for DAV and follow-up OCM access.

**Features:**

- Exchanged token validation
- Follow-up DAV authorization
- Code-flow token continuation

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

- Gateway -> Share Providers
- Gateway -> User/Group Providers
- Gateway -> Auth Providers
- Gateway -> Dataproviders
- Auth Providers -> External IdP (for OIDC)

## Related Documentation

- [Architecture](architecture.md) - Service architecture and version tuple
- [Container Modes](container-modes.md) - Container mode system
- [Configuration](configuration.md) - Band resolver and configuration details
