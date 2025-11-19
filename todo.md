# TODO

## Docker Health Checks

### High Priority

- [ ] Add HEALTHCHECK instruction to `services/revad-base/Dockerfile`
- [ ] Add HEALTHCHECK instruction to `services/cernbox-web/Dockerfile`
- [ ] Add HEALTHCHECK instruction to `services/cernbox-revad/Dockerfile`

## Keycloak Configuration

### Future Tasks

- [ ] Make Keycloak redirect URIs configurable via script instead of hardcoded in `services/idp/configs/keycloak.json`
  - Currently `cernbox-oidc` client has hardcoded redirect URIs (`https://cernbox1.docker/*`, `https://cernbox2.docker/*`)
  - Need to support dynamic redirect URI configuration based on environment variables or deployment configuration
  - Consider templating the keycloak.json file or using Keycloak Admin API at runtime
