# Dockerfile Development Rules

Local folder sources, multi-stage builds, and the buildx workflow impose a few hard requirements on every service Dockerfile. Treat these rules the same way we treat the Nushell guidelines: breaking them has immediate build impacts.

## Critical Requirements

1. **Declare every build arg with a default.**

   - Sources: `{NAME}_URL`, `{NAME}_REF`, `{NAME}_SHA`, `{NAME}_PATH`, `{NAME}_MODE`
   - Dependencies / external images: custom build args defined in the service config
   - TLS: `TLS_ENABLED`, `TLS_MODE`, etc., when applicable  
     Declaring defaults keeps `docker build` usable outside the build system and guarantees deterministic values when args are omitted.

2. **Always bind-mount local sources before copying.**

   - Use `--mount=type=bind,source=${FOO_PATH:-.},target=/tmp/local-foo,ro` on the same `RUN` line that copies the Git checkout.
   - Copy from the mounted directory: `cp -a /tmp/local-foo/. /foo-git`.
   - Without the bind mount, Docker cannot see `.build-sources/foo`, which recreates the bug we just fixed (`cp: cannot stat '.build-sources/foo'`).  
     See `docs/source-build-args.md` for the generated `_PATH`/`_MODE` args.

3. **Wrap Git clones in conditional logic.**

   ```dockerfile
   ARG FOO_PATH=""
   ARG FOO_MODE=""
   ARG FOO_URL=""
   ARG FOO_REF=""

   RUN --mount=type=bind,source=${FOO_PATH:-.},target=/tmp/local-foo,ro \
       --mount=type=cache,id=foo-git-${CACHEBUST:-${FOO_REF}},target=/src/foo-git-cache,sharing=shared \
       if [ "$FOO_MODE" = "local" ]; then \
         mkdir -p /foo-git && \
         cp -a /tmp/local-foo/. /foo-git; \
       else \
         mkdir -p /src/foo-git-cache && \
         if [ ! -d /src/foo-git-cache/.git ]; then \
           git clone --depth 1 --recursive --shallow-submodules --branch "${FOO_REF}" ${FOO_URL} /src/foo-git-cache; \
         fi && \
         cp -a /src/foo-git-cache/. /foo-git; \
       fi
   ```

   Local mode is CI-disabled, but developers rely on it for iterative builds. Missing the conditional forces everyone back to Git sources.

4. **Keep cache mounts deterministic.**

   - Include `CACHEBUST` in cache IDs: `id=foo-git-${CACHEBUST:-${FOO_REF}}`.
   - Share caches across builds when the same ref is used, but guarantee busting when the build system rotates the cache key.

5. **Clean package manager state.**

   - `apt-get clean && rm -rf /var/lib/apt/lists/*` after Debian/Ubuntu installs.
   - Ensures smaller layers and aligns with security guidance.

6. **Use multi-stage builds with explicit COPY scopes.**

   - Builder → compression → runtime is the expected pattern.
   - Never leak build secrets into runtime layers; copy only the final artifacts.

7. **Quote shell variables when calling nushell scripts.**

   When calling nushell scripts from shell (e.g., in RUN commands), shell variables must be properly quoted to ensure nushell receives strings, not booleans or numbers.

   - **WRONG**:

     ```dockerfile
     nu /tmp/copy-tls.nu \
     --enabled "$TLS_ENABLED" \
     --mode "$TLS_MODE"
     ```

     When `$TLS_ENABLED` expands to `true`, nushell receives the boolean `true` instead of the string `"true"`, causing "expected string" parse errors.

   - **CORRECT**:

     ```dockerfile
     nu /tmp/copy-tls.nu \
     --enabled "'$TLS_ENABLED'" \
     --mode "'$TLS_MODE'"
     ```

     The pattern `"'$VAR'"` means: outer double quotes for shell expansion, inner single quotes passed as literal to nushell. When `$TLS_ENABLED` is `true`, shell expands to `'true'` and nushell receives the string `"true"`.

   - **Why**: Nushell is strongly typed. If a script parameter is `--enabled: string`, it must receive a string, not a boolean. Shell variables expand to unquoted values that nushell interprets as their native types.

   - **Pattern**: Always use `"'$SHELL_VAR'"` when passing shell variables to nushell scripts that expect string parameters.

## Common Mistakes to Avoid

- **Copying from `${FOO_PATH}` without a mount**: breaks every local-source build. Always mount then copy from the mounted path.
- **Implicit ARG usage**: referencing `FOO_REF` without `ARG FOO_REF` declares it globally and makes the Dockerfile unusable in isolation.
- **Installing git inside runtime stages**: keep tooling in the build stage; runtime images should contain only the shipped binaries.
- **Not using `set -euo pipefail` equivalents**: when writing long `RUN` scripts, prefer `bash -eu -o pipefail -c '...'` to surface failures early.
- **Leaving cache mounts on unrelated layers**: only the Git clone step should mount the Git cache; other commands should stay deterministic.
- **Mixing `cp` semantics**: use `cp -a /src/. /dest` to preserve permissions; `cp -r ${PATH}*` drops dotfiles.
- **Passing shell variables to nushell without proper quoting**: nushell is strongly typed. When calling nushell scripts from shell, use `"'$VAR'"` pattern to ensure string parameters receive strings, not booleans or numbers. See "Calling Nushell Scripts" below.

## Volume Mount Protection Patterns

When baking data into images that users might mount over at runtime, use an alternate location that survives the mount.

### Problem

Baked data at `/usr/src/nextcloud/apps/myapp` is lost when CI users mount their own source to `/usr/src/nextcloud`.

### Solution

Bake to an independent location and merge at runtime:

1. **Bake to alternate location**: `/usr/src/apps/{app-name}` instead of `/usr/src/nextcloud/apps/`
2. **Runtime merge**: Entrypoint copies from alternate location to final destination
3. **Override detection**: Skip merge if app already exists at destination (allows user override)

### Pattern for Baked Apps

```dockerfile
# In child image (e.g., nextcloud-contacts)
# Bake app to /usr/src/apps/ (independent of /usr/src/nextcloud)
COPY --from=app-assemble /app /usr/src/apps/contacts
```

At runtime, the base image merges `/usr/src/apps/*` into `/usr/src/nextcloud/apps/` before syncing to `/var/www/html`.

**Why `apps/` instead of `custom_apps/`:** Nextcloud checks `apps/` first and `occ app:enable` downloads from the app store if it doesn't find the app in `apps/`. Merging to `apps/` ensures our baked apps are found before Nextcloud tries the app store.

### General Pattern

```text
1. Bake data to: /usr/src/{category}/{item}
2. Runtime merge to: /usr/src/{main-source}/{category}/{item}
3. Final sync to: /var/www/html/{category}/{item}
```

This three-level approach allows:

- CI users to mount `/usr/src/{main-source}` without losing baked data
- Users to override specific items by mounting to `/usr/src/{category}/{item}`
- Full control via direct runtime mounts to `/var/www/html/...`

## Build Stage Naming Standards

Use consistent naming for build stage image arguments across services.

### Standard Names

| Build Arg            | Purpose                  | Example               |
| -------------------- | ------------------------ | --------------------- |
| `BASE_BUILD_IMAGE`   | Build-time tooling image | `node:24-trixie-slim` |
| `BASE_RUNTIME_IMAGE` | Runtime base image       | `debian:trixie-slim`  |
| `{SERVICE}_IMAGE`    | Dependency service image | `NEXTCLOUD_IMAGE`     |

### Build Stage Configuration

In `platforms.nuon`, define external images:

```nuon
{
  "defaults": {
    "external_images": {
      "build": {
        "name": "node",
        "build_arg": "BASE_BUILD_IMAGE"
      }
    }
  }
}
```

In `versions.nuon`, define tags:

```nuon
{
  "defaults": {
    "external_images": {
      "build": {
        "tag": "24-trixie-slim"
      }
    }
  }
}
```

### Multi-Stage Example

```dockerfile
# Build stage images
ARG BASE_BUILD_IMAGE="node:24-trixie-slim"

# Runtime image (dependency)
ARG NEXTCLOUD_IMAGE="nextcloud:v32.0.2-debian"

# Stage 1: Build
FROM ${BASE_BUILD_IMAGE} AS builder
# ... build steps ...

# Stage 2: Runtime
FROM ${NEXTCLOUD_IMAGE}
COPY --from=builder /dist /app
```

## Using common-tools as Base Image

The `common-tools` image is a base utility image that provides Debian (or Alpine/RHEL) with common build tools pre-installed. Use it as a base image instead of hardcoding `debian:trixie-slim` when you need a Debian base with common tools.

### What common-tools Provides

The `common-tools` image includes:

- Base OS: Debian Trixie Slim (configurable via `BASE_RUNTIME_IMAGE`)
- Pre-installed tools: `git`, `make`, `curl`, `bash`, `binutils`, `nu` (Nushell), `upx`, `ca-certificates`

### When to Use common-tools

Use `common-tools` as a base image for any stage that needs:

- Debian base OS
- Common build tools (git, make, curl, etc.)
- Version management through the build system

**Do not use** `common-tools` when:

- You need a specialized base image (e.g., `node:24-trixie-slim` for Node.js builds)
- Runtime stages that inherit from service-specific bases (e.g., `php:8.3-apache-trixie`)

### common-tools Pattern

```dockerfile
# Declare ARG at top of Dockerfile
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"

# Use as base image for stages needing Debian + common tools
FROM ${COMMON_TOOLS_IMAGE} AS source-prepare
# git, ca-certificates, etc. already available - no apt install needed

FROM ${COMMON_TOOLS_IMAGE} AS app-assemble
# Minimal stage, but consistent with source-prepare
```

### common-tools Configuration

Add dependency in `platforms.nuon`:

```nuon
{
  "defaults": {
    "dependencies": {
      "common-tools": {
        "service": "common-tools",
        "build_arg": "COMMON_TOOLS_IMAGE"
      }
    }
  }
}
```

### Benefits

- **Version management**: Base image version controlled via build system (`versions.nuon`)
- **No redundant installs**: Tools already available, no `apt-get install git ca-certificates` needed
- **Consistency**: Same pattern across all services
- **Cache efficiency**: Shared base image reduces redundant downloads

### common-tools Rule

**Never hardcode `FROM debian:*` when `common-tools` provides what you need.** Always use `FROM ${COMMON_TOOLS_IMAGE}` for stages needing Debian base + common tools.

- Wrong: `FROM debian:trixie-slim AS source-prepare` followed by `apt-get install git ca-certificates`
- Correct: `FROM ${COMMON_TOOLS_IMAGE} AS source-prepare` (tools already available)

## Shared Package Cache IDs

When installing packages via apt, apk, or dnf, use the standard cache IDs defined by `common-tools`. This ensures cache sharing across services for faster multi-service builds.

### Standard Cache IDs

| Platform      | Cache ID                        | Target               |
| ------------- | ------------------------------- | -------------------- |
| Debian/Ubuntu | `common-tools-debian-apt-cache` | `/var/cache/apt`     |
| Debian/Ubuntu | `common-tools-debian-apt-lists` | `/var/lib/apt/lists` |
| Alpine        | `common-tools-alpine-apk-cache` | `/var/cache/apk`     |
| RHEL/UBI      | `common-tools-rhel-dnf-cache`   | `/var/cache/dnf`     |

### Cache Mount Pattern

```dockerfile
RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install --no-install-recommends --assume-yes <packages>;
```

### Cache ID Rule

**Never create service-specific cache IDs for package managers.** Always use `common-tools-{platform}-{package-manager}-cache`.

- Wrong: `id=myservice-apt-cache`
- Correct: `id=common-tools-debian-apt-cache`

## Verification Checklist

- [ ] ARGs declared in the Dockerfile match the service config build args.
- [ ] Local-source branch uses a bind mount and copies from `/tmp/local-*`.
- [ ] Git branch uses the cache mount with `CACHEBUST`.
- [ ] Package manager caches cleaned.
- [ ] Multi-stage boundaries enforced (no stray build tools in runtime image).
- [ ] `COPY` instructions reference files produced in previous stages, not host paths.
- [ ] Optional TLS helper scripts (`./scripts/tls/copy-tls.nu`) only copied when TLS is enabled.

## References

- `docs/source-build-args.md` – generated build args and naming conventions
- `docs/guides/service-setup.md` – step-by-step Dockerfile scaffolding
- `docs/concepts/build-system.md` – cache busting, arg priority, and CI restrictions
- `docs/guides/nushell-development.md` – accompanying rules for Nushell scripts used by the build system
