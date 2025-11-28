# Nextcloud Docker Compose Example

This example demonstrates how to run Nextcloud containers built by DockyPody in a development/test environment using Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- Traefik network `traefik-net` exists (create with: `docker network create --subnet=172.16.85.0/24 traefik-net`)
- Nextcloud images built (e.g., `nextcloud:v32.0.2-debian`)

## Quick Start

1. **Configure environment variables:**

   ```bash
   cp env .env
   # Edit .env with your settings
   ```

2. **Create volume directories:**

   ```bash
   mkdir -p volumes/data/{nextcloud,mariadb,redis}
   ```

3. **Start services:**

   ```bash
   docker compose up -d
   ```

4. **Access Nextcloud:**

   - URL: `https://1.nextcloud.cloud.test.azadehafzar.io` (or your configured domain)
   - Admin credentials: Set in `.env` file (`NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD`)

## Configuration

### Image Version

Edit `IMAGE_NEXTCLOUD` in `.env` to use a different Nextcloud version:

```bash
IMAGE_NEXTCLOUD=v32.0.2-debian
IMAGE_NEXTCLOUD=latest-debian
IMAGE_NEXTCLOUD=master-debian
```

### Database

The example uses MariaDB by default. To use PostgreSQL instead:

1. Replace `nextcloud-1-test-db` service in `docker-compose.yaml` with PostgreSQL
2. Update environment variables to use `POSTGRES_*` instead of `MYSQL_*`
3. Update `MYSQL_HOST` to `POSTGRES_HOST` in Nextcloud service

### Redis

Redis is optional but recommended for caching. To disable:

1. Remove `nextcloud-1-test-redis` service
2. Remove `REDIS_HOST` environment variable from Nextcloud service
3. Remove Redis dependency from Nextcloud service

## Services

- **nextcloud-1-test-db**: MariaDB database server
- **nextcloud-1-test-redis**: Redis cache server
- **nextcloud-1-test**: Nextcloud application server

## Volumes

Data is persisted in `volumes/data/`:

- `volumes/data/nextcloud/`: Nextcloud application data and files
- `volumes/data/mariadb/`: MariaDB database files
- `volumes/data/redis/`: Redis persistence data

## Network

All services connect to the external `traefik-net` network for Traefik routing.

## Troubleshooting

### Database Connection Issues

If Nextcloud can't connect to the database:

1. Check database container is running: `docker ps | grep nextcloud-1-test-db`
2. Verify database credentials in `.env` match MariaDB service
3. Check Nextcloud logs: `docker logs nextcloud-1-test`

### Traefik Routing Issues

If Traefik can't route to Nextcloud:

1. Verify `traefik-net` network exists: `docker network ls | grep traefik-net`
2. Check Traefik labels are correct in `docker-compose.yaml`
3. Verify domain matches `NEXTCLOUD_DOMAIN` in `.env`

### First-Time Setup

On first run, Nextcloud will automatically install if:

- `NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD` are set
- Database credentials are correct
- Database is accessible

Otherwise, access the web interface to complete manual installation.
