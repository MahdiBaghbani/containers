# TODO

## Docker Health Checks

### Done (development images)

- [x] Add `HEALTHCHECK` to `services/revad-base/Dockerfile.development` via
  `/usr/bin/healthcheck.nu` (Nushell lane owns the script)
- [x] Add `HEALTHCHECK` to `services/idp/Dockerfile` (Keycloak
  `http://127.0.0.1:9000/health/ready`)
- [x] Add `HEALTHCHECK` to `services/cernbox-web/Dockerfile` (curl HTTPS root)
- [x] Drop redundant compose healthchecks in CERNBox examples and
  `ocm-test-suite` cernbox sender cookbook; use `service_healthy` where images
  expose baked checks
- [x] Add Nextcloud app healthcheck in `examples/nextcloud` (parity with
  `nextcloud-contacts`)

### Remaining

- [ ] Rebuild and smoke-test images after `healthcheck.nu` lands in revad-base
- [ ] Consider baked health for other DockyPody services as needed (production
  / distroless paths intentionally omit `HEALTHCHECK`)

## Keycloak Configuration

### Future Tasks

- [ ] Make Keycloak redirect URIs configurable via script instead of hardcoded in `services/idp/configs/keycloak.json`
  - Currently `cernbox-oidc` client has hardcoded redirect URIs (`https://cernbox1.docker/*`, `https://cernbox2.docker/*`)
  - Need to support dynamic redirect URI configuration based on environment variables or deployment configuration
  - Consider templating the keycloak.json file or using Keycloak Admin API at runtime
