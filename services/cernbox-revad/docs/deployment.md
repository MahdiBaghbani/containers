# Deployment Guide

Step-by-step guide for deploying the CERNBox multi-container setup.

## Prerequisites

- Docker and Docker Compose installed
- Traefik network created: `traefik-net`
- Access to container images
- Environment variables configured

## Quick Start

1. **Configure Environment:**

   ```bash
   cd examples/cernbox
   cp env.example env  # If needed
   # Edit env file with your configuration
   ```

2. **Start Services:**

   ```bash
   docker-compose up -d
   ```

3. **Verify Deployment:**

   ```bash
   docker-compose ps
   docker-compose logs gateway
   ```

## Deployment Steps

### 1. Environment Configuration

Edit `env` file with your configuration:

```bash
# Required: Domain configuration
DOMAIN=your-domain.example.com
REVAD_DOMAIN=your-revad-domain

# Required: Container mode (for gateway)
REVAD_CONTAINER_MODE=gateway

# Required: Gateway configuration
REVAD_GATEWAY_HOST=cernbox-1-test-revad-gateway
REVAD_GATEWAY_GRPC_PORT=9142

# Optional: Adjust ports if needed
# See ports.md for complete port reference
```

### 2. Network Setup

Ensure Traefik network exists:

```bash
docker network create traefik-net
```

### 3. Volume Preparation

Volumes are created automatically, but you can pre-create them:

```bash
mkdir -p volumes/config/reva-{gateway,shareproviders,groupuserproviders,authprovider-oidc,authprovider-machine,authprovider-ocmshares,dataprovider-localhome,dataprovider-ocm,dataprovider-sciencemesh}
mkdir -p volumes/data/reva/jsons
```

### 4. Start Services

Start all services:

```bash
docker-compose up -d
```

Start specific services:

```bash
docker-compose up -d gateway shareproviders groupuserproviders
```

### 5. Verify Services

Check service status:

```bash
# List all containers
docker-compose ps

# Check logs
docker-compose logs gateway
docker-compose logs shareproviders
docker-compose logs groupuserproviders

# Check specific service
docker-compose logs -f gateway
```

## Service Dependencies

Services start in this order:

1. **IdP** - Identity Provider (no dependencies)
2. **Gateway** - Depends on IdP, Share Providers, User/Group Providers
3. **Share Providers** - Depends on Gateway
4. **User/Group Providers** - Depends on Gateway
5. **Auth Providers** - Depends on Gateway
6. **Dataproviders** - Depends on Gateway
7. **Web** - Depends on Gateway, IdP, Dataproviders

Docker Compose handles dependencies automatically via `depends_on`.

## Health Checks

### Check Gateway

```bash
# Check if gateway is responding
curl http://localhost:80/healthz

# Check gateway logs
docker-compose logs gateway | grep -i error
```

### Check Providers

```bash
# Check share providers
docker-compose logs shareproviders

# Check user/group providers
docker-compose logs groupuserproviders

# Check auth providers
docker-compose logs authprovider-oidc
```

### Check Ports

```bash
# Verify ports are listening
docker-compose exec gateway netstat -tlnp | grep 9142
docker-compose exec shareproviders netstat -tlnp | grep 9144
docker-compose exec groupuserproviders netstat -tlnp | grep 9145
```

## Troubleshooting

### Common Issues

#### Port Conflicts

**Symptom:** Container fails to start with "port already in use"

**Solution:**
- Check for port conflicts: `netstat -tlnp | grep <port>`
- Adjust ports in `env` file
- See [Port Assignments](ports.md) for port reference

#### Configuration Errors

**Symptom:** Service fails with configuration errors

**Solution:**
- Check environment variables: `docker-compose config`
- Verify placeholder processing: `docker-compose exec gateway cat /etc/revad/cernbox-gateway.toml`
- Check initialization logs: `docker-compose logs gateway | grep -i init`

#### Service Not Found

**Symptom:** Gateway cannot connect to provider services

**Solution:**
- Verify service names match in `docker-compose.yaml`
- Check network connectivity: `docker-compose exec gateway ping shareproviders`
- Verify ports match environment variables

#### Authentication Failures

**Symptom:** Login fails or authentication errors

**Solution:**
- Check IdP is running: `docker-compose ps idp`
- Verify OIDC provider configuration
- Check IdP URL in environment variables
- Review auth provider logs: `docker-compose logs authprovider-oidc`

### Debug Commands

```bash
# View all environment variables
docker-compose config

# Execute command in container
docker-compose exec gateway /bin/sh

# View configuration file
docker-compose exec gateway cat /etc/revad/cernbox-gateway.toml

# Check service connectivity
docker-compose exec gateway ping shareproviders

# View network configuration
docker network inspect traefik-net
```

## Scaling

Services can be scaled independently:

```bash
# Scale dataproviders (if needed)
docker-compose up -d --scale dataprovider-localhome=2

# Scale auth providers (if needed)
docker-compose up -d --scale authprovider-oidc=2
```

**Note:** Gateway and provider services are typically single-instance.

## Updates

### Update Configuration

1. Edit configuration files or environment variables
2. Restart affected services:

   ```bash
   docker-compose restart gateway
   ```

### Update Images

1. Pull new images:

   ```bash
   docker-compose pull
   ```

2. Recreate containers:

   ```bash
   docker-compose up -d --force-recreate
   ```

## Backup and Restore

### Backup Configuration

```bash
# Backup all configurations
tar -czf cernbox-config-backup.tar.gz volumes/config/

# Backup data
tar -czf cernbox-data-backup.tar.gz volumes/data/
```

### Restore Configuration

```bash
# Restore configurations
tar -xzf cernbox-config-backup.tar.gz

# Restart services
docker-compose restart
```

## Related Documentation

- [Architecture](architecture.md) - System architecture
- [Port Assignments](ports.md) - Port reference
- [Configuration](configuration.md) - Configuration details
- [Services](services.md) - Service descriptions

