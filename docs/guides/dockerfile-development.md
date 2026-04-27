# Dockerfile Development Rules

Local folder sources, multi-stage builds, and the buildx workflow impose a few
hard requirements on every service Dockerfile. Treat these rules the same way
we treat the Nushell guidelines: breaking them has immediate build impacts.

Operator reality:

- this repo is bandwidth-limited
- Dockerfiles must use aggressive caching (BuildKit cache mounts, shared cache
  ids) to avoid repeated downloads

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

   - Run `apt-get clean && rm -rf /var/lib/apt/lists/*` in a separate `RUN`
     without package-manager cache mounts after Debian/Ubuntu installs.
   - Ensures smaller layers and aligns with security guidance.

6. **Use multi-stage builds with explicit COPY scopes.**

   - Builder -> compression -> runtime is the expected pattern.
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

     The pattern `"'$VAR'"` means: outer double quotes for shell expansion, inner single quotes passed as literal to nushell. When `$TLS_ENABLED` is `true`, shell expands to `'true'` and nushell receives the string value with literal quotes.

   - **Why**: Nushell is strongly typed. If a script parameter is `--enabled: string`, it must receive a string, not a boolean. Shell variables expand to unquoted values that nushell interprets as their native types.

   - **Normalization**: Well-designed nushell scripts (like `copy-tls.nu`) normalize quoted values internally - stripping surrounding quotes and handling case variations. This means `'true'`, `'TRUE'`, and `"true"` all work correctly.

   - **Pattern**: Always use `"'$SHELL_VAR'"` when passing shell variables to nushell scripts that expect string parameters.

## ARG and ENV Ordering (scoping and cache)

Dockerfile ordering is not just style. It affects:

- Docker scoping (what values are visible in which stage)
- Cache reuse (what changes invalidate expensive layers)

### ARG scoping rules (Docker semantics)

- **ARG in FROM**: Any `ARG` referenced by a `FROM ${...}` must be declared
  before the first `FROM`.
- **ARG in stage instructions**: If a stage uses an arg in `RUN`, `ENV`, `COPY`,
  cache mount ids, and so on, re-declare it after that stage's `FROM` so it is
  in scope.
- **Defaults**: Declare defaults once in the global `ARG` block. In stages,
  prefer `ARG NAME` (no default) to avoid drift.

### Recommended block order (file and stage)

```dockerfile
# syntax=docker/dockerfile:1.7

# SPDX header...

# Global args (used by FROM)
ARG COMMON_TOOLS_IMAGE="common-tools:v1.0.0-debian"
ARG BASE_RUNTIME_IMAGE="debian:trixie-slim"

# Global pins (versions, refs)
ARG FOO_VERSION="1.2.3"

# Global feature args (TLS when applicable)
ARG TLS_ENABLED="false"
ARG TLS_MODE="disabled"
ARG TLS_CERT_NAME=""
ARG TLS_CA_NAME=""

FROM ${COMMON_TOOLS_IMAGE} AS common-tools

FROM ${BASE_RUNTIME_IMAGE}

# Stage args (re-declare for this stage's scope)
ARG FOO_VERSION
ARG TLS_ENABLED
ARG TLS_MODE
ARG TLS_CERT_NAME
ARG TLS_CA_NAME

USER root

# Build-affecting env (only if a following RUN needs it)
# ENV NODE_EXTRA_CA_CERTS="/etc/ssl/certs/ca-certificates.crt"

# RUN/COPY/WORKDIR...

# Runtime defaults (late in the final runtime stage)
# ENV OCM_DEFAULT_WEB_BROWSER="firefox"
```

### ENV placement rules (cache and correctness)

- **Build-only env**: If a value is only needed for one build step, prefer
  setting it inside that `RUN` (for example: `export CYPRESS_CACHE_FOLDER=...`)
  instead of baking it into `ENV`.
- **Runtime defaults**: Prefer placing runtime-only `ENV` late in the final
  runtime stage so tweaks do not invalidate earlier heavy install layers.
- **ARG before ENV**: If an `ENV` value uses a build arg (for example
  `ENV TZ=$TZ`), declare `ARG TZ` earlier in the same stage.

### Common footguns

- `ENV X=${SOME_ARG}` is a snapshot of `SOME_ARG` at that point in the file. It
  will not update if `SOME_ARG` is re-declared later.
- Avoid using the same name for both `ARG` and `ENV` unless you intentionally
  want `ENV` to shadow later substitutions.

## Desktop app autostart and window maximize

Desktop-app images (Kasm-derived) often launch a GUI application via a Nushell
autostart script (for example `firefox-autostart.nu` or `cypress-autostart.nu`).

### Standard pattern

- Keep runtime behavior configurable via env vars (default-on for UX tweaks).
- Call `/dockerstartup/ocm-desktop-env.nu` after `desktop_ready` to apply session
  defaults (for example `OCM_DEFAULT_WEB_BROWSER`).
- If the app should open maximized by default, use the shared helper:
  `/dockerstartup/ocm-window-actions.nu --maximize`.
  - It is a best-effort fallback using `wmctrl` against the active window.
  - It is safe to call repeatedly; it is a no-op if the helper is missing.

### Recommended env knobs

- Firefox:
  - `OCM_FIREFOX_MAXIMIZE` (default true)
- Cypress:
  - `OCM_CYPRESS_MAXIMIZE` (default true, keeps `--start-maximized` and also
    calls the shared maximize helper)

## Common Mistakes to Avoid

- **Copying from `${FOO_PATH}` without a mount**: breaks every local-source build. Always mount then copy from the mounted path.
- **Implicit ARG usage**: referencing `FOO_REF` without declaring `ARG FOO_REF`
  means the value is empty or unset at build time, which makes cache ids,
  clones, and conditionals brittle.
- **Installing git inside runtime stages**: keep tooling in the build stage; runtime images should contain only the shipped binaries.
- **Not using `set -euo pipefail` equivalents**: when writing long `RUN` scripts, prefer `bash -eu -o pipefail -c '...'` to surface failures early.
- **Leaving cache mounts on unrelated layers**: only the Git clone step should mount the Git cache; other commands should stay deterministic.
- **Mixing `cp` semantics**: use `cp -a /src/. /dest` to preserve permissions; `cp -r ${PATH}*` drops dotfiles.
- **Passing shell variables to nushell without proper quoting**: nushell is strongly typed. When calling nushell scripts from shell, use `"'$VAR'"` pattern to ensure string parameters receive strings, not booleans or numbers. See "Critical Requirements" below.

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
- Pre-installed tools: `git`, `make`, `curl`, `bash`, `binutils`, `nu` (Nushell), `upx`, `tini`, `ca-certificates`
- Platform variants: `debian`, `alpine`, `rhel`

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

When installing packages via apt, apk, or dnf, use shared cache IDs so multiple
services can reuse the same package-manager cache across builds.

### Standard Cache IDs

| Platform                            | Cache ID                        | Target               |
| ----------------------------------- | ------------------------------- | -------------------- |
| Debian/Ubuntu                       | `common-tools-debian-apt-cache` | `/var/cache/apt`     |
| Debian/Ubuntu                       | `common-tools-debian-apt-lists` | `/var/lib/apt/lists` |
| Alpine                              | `common-tools-alpine-apk-cache` | `/var/cache/apk`     |
| RHEL/UBI                            | `common-tools-rhel-dnf-cache`   | `/var/cache/dnf`     |
| Ubuntu Noble (Kasm upstream images) | `kasm-base-apt-cache`           | `/var/cache/apt`     |
| Ubuntu Noble (Kasm upstream images) | `kasm-base-apt-lists`           | `/var/lib/apt/lists` |

### Cache Mount Pattern

```dockerfile
RUN --mount=type=cache,id=common-tools-debian-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=common-tools-debian-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean; \
    apt-get update; \
    apt-get install --no-install-recommends --assume-yes <packages>

RUN apt-get clean && rm -rf /var/lib/apt/lists/*
```

### Cache ID Rule

**Do not create per-leaf package-manager cache IDs.** Use one shared pool per
base family:

- Debian-family stages: `common-tools-debian-apt-*`
- Ubuntu Noble Kasm family stages: `kasm-base-apt-*` (only when the runtime base
  is Ubuntu Noble; do not use for Debian-based `kasm-base`)

If you introduce a second Debian/Ubuntu family that needs isolation (for example
an Ubuntu Noble base distinct from the default Debian pool), add a dedicated
shared pool here. Do not invent per-leaf cache IDs.

## Direct Download Cache Mounts (curl/wget)

Any pinned artifact fetched by curl/wget during the build (Node tarballs,
Firefox tarballs, KasmVNC packages, and similar) must be cached explicitly.

Rules:

- Download into a cache-mounted directory and reuse the cached file when present.
- Cache identity must not mix versions or architectures. Include a pin and arch
  in the cache mount id, or encode them in the cached filename or subdirectory.
- Default to `sharing=locked` unless the cache is proven safe for concurrent
  writers.
- Do not download into `/tmp` unless `/tmp` is the cache mount target for that
  `RUN`. Many images delete `/tmp` in later cleanup steps.
- If the artifact must be baked into the image at a final runtime path, do not
  mount the cache at that final path. Mount a download cache directory and copy
  the cached artifact into the final path so it is stored in the image layer.
- Prefer explicit pins (version args) over `CACHEBUST` for artifact caches.
  `CACHEBUST` is computed from git sources by default and does not necessarily
  change when an unrelated pinned tarball changes.

Pattern (curl to a cached file, install from it):

```dockerfile
ARG FOO_VERSION="1.2.3"
ARG TARGETARCH

RUN --mount=type=cache,id=service-foo-dl-${FOO_VERSION}-${TARGETARCH},target=/var/cache/service-foo,sharing=locked \
    set -eu; \
    file="/var/cache/service-foo/foo-${FOO_VERSION}-${TARGETARCH}.tar.gz"; \
    if [ ! -s "$file" ]; then \
      curl -fsSL --retry 3 --retry-delay 2 -o "$file" "https://example.com/foo-${FOO_VERSION}-${TARGETARCH}.tar.gz"; \
    fi; \
    tar -xzf "$file" -C /usr/local
```

## Language and Tool Caches

Use BuildKit cache mounts for language package managers and toolchains that do
network work during builds. Keep ids deterministic and service-scoped unless a
shared pool is explicitly documented (like apt/apk/dnf above).

| Ecosystem | Typical cache id pattern | Target | Sharing |
| --- | --- | --- | --- |
| Go modules | `<service>-go-mod-cache` | `/go/pkg/mod` | `locked` |
| Go build cache | `<service>-go-build-cache` | `/root/.cache/go-build` | `locked` |
| npm | `<service>-npm-cache` | `/root/.npm` | `locked` |
| pnpm store | `<service>-pnpm-store` | `/root/.local/share/pnpm/store` | `locked` |
| pnpm cache | `<service>-pnpm-cache` | `/root/.cache/pnpm` | `locked` |
| Composer | `<service>-composer-cache` | `/root/.composer/cache` | `locked` |
| PECL downloads | `<service>-pecl-downloads` | `/tmp/pear/download` | `locked` |

## Process Management and Init Systems

All non-distroless containers MUST use tini as the init system.

### Why tini

PID 1 has special kernel responsibilities:

- Signal handling: no default SIGTERM handler, signals are silently dropped
- Zombie reaping: must call waitpid() on orphaned children

Most applications are not designed to be PID 1 citizens.

### Standard ENTRYPOINT Pattern

```dockerfile
# Copy tini from common-tools (installed once, copied to all services)
COPY --chmod=755 --from=common-tools /usr/bin/tini-static /usr/bin/tini

# JSON-form ENTRYPOINT (exec form, not shell form)
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/bin/entrypoint.sh"]
```

### entrypoint.sh Wrapper

```bash
#!/bin/bash
set -euo pipefail

if [ -f /usr/bin/entrypoint-init.nu ]; then
    if command -v nu >/dev/null 2>&1; then
        nu /usr/bin/entrypoint-init.nu "$@" || {
            status=$?
            echo "ERROR: entrypoint-init.nu failed with exit code ${status}; refusing to run CMD" >&2
            exit "$status"
        }
    else
        echo "ERROR: nu not found; cannot run /usr/bin/entrypoint-init.nu" >&2
        exit 1
    fi
else
    echo "ERROR: /usr/bin/entrypoint-init.nu not found; refusing to run CMD" >&2
    exit 1
fi

exec "$@"
```

Rules:

- Always use JSON form for ENTRYPOINT
- Never use shell form (`ENTRYPOINT /usr/bin/tini ...`)
- The wrapper MUST end with `exec "$@"` to replace the shell process
- Nushell init scripts should NOT use `exec` (let the shell wrapper do it)
- The wrapper MUST treat missing `nu`, missing `entrypoint-init.nu`, and
  nonzero init exits as fatal. Warnings belong inside the Nushell orchestrator
  and must exit 0.

### Exceptions

- Distroless/scratch images: exempt (no shell to run tini)
- Services that already have a complex entrypoint chain (e.g., nginx): chain to the existing entrypoint from your wrapper

## Package List Alphabetical Ordering

Package lists in `apt-get install`, `apk add`, and `microdnf install` MUST be alphabetically sorted.

```dockerfile
# Correct
RUN apt-get install \
    --no-install-recommends \
    --assume-yes \
    bash \
    binutils \
    ca-certificates \
    curl \
    git \
    make;

# Incorrect
RUN apt-get install \
    --no-install-recommends \
    --assume-yes \
    curl \
    ca-certificates \
    git \
    make \
    bash \
    binutils;
```

Rationale: prevents duplicate packages, makes diffs cleaner, simplifies code reviews.

## SSH Build Arguments and Dockerfile Patterns

When a service enables SSH (`ssh.enabled=true`), the build system injects these arguments:

| Argument | Default | Description |
| -------- | ------- | ----------- |
| `SSH_ENABLED` | `"false"` | Whether SSH is enabled |
| `SSH_MODE` | `"disabled"` | `"client"`, `"server"`, or `"client-and-server"` |
| `SSH_DEFAULT_USER` | `"root"` | Default SSH user |
| `SSH_PORT` | `"22"` | SSH daemon port |
| `SSH_LISTEN` | `"0.0.0.0"` | SSH daemon listen address (server mode) |

### Client Mode Pattern (Kasm workspaces)

```dockerfile
ARG SSH_ENABLED="false"
ARG SSH_MODE="disabled"
ARG SSH_DEFAULT_USER="root"
ARG SSH_PORT="22"
ARG SSH_LISTEN="0.0.0.0"

# ... later in Dockerfile ...

RUN apt-get install \
    --no-install-recommends \
    --assume-yes \
    openssh-client;

COPY --chmod=755 ./scripts/startup/ocm-ssh-client-env.nu /dockerstartup/ocm-ssh-client-env.nu

ENV OCM_SSH_ENABLED="${SSH_ENABLED}" \
    OCM_SSH_MODE="${SSH_MODE}" \
    OCM_SSH_DEFAULT_USER="${SSH_DEFAULT_USER}" \
    OCM_SSH_PORT="${SSH_PORT}" \
    OCM_SSH_LISTEN="${SSH_LISTEN}"
```

### Server Mode Pattern (target services)

```dockerfile
ARG SSH_ENABLED="false"
ARG SSH_MODE="disabled"
ARG SSH_DEFAULT_USER="root"
ARG SSH_PORT="22"
ARG SSH_LISTEN="0.0.0.0"

# ... later in Dockerfile ...

RUN apt-get install \
    --no-install-recommends \
    --assume-yes \
    openssh-server;

# The build system stages the shared sshd module into the build context as:
#   scripts/lib/sshd.nu
# so the service can copy it alongside its other entrypoint libs.
COPY --chmod=755 ./scripts/lib/sshd.nu /usr/bin/lib/sshd.nu

# Install staged SSH material in a coherent way. For server-capable images, gate
# on modes that include server behavior.
COPY ./ssh /tmp/ssh-build-context/
RUN if [ "$SSH_ENABLED" = "true" ] && { [ "$SSH_MODE" = "server" ] || [ "$SSH_MODE" = "client-and-server" ]; }; then \
      mkdir -p /opt/dockypody/ssh && \
      for pub in /tmp/ssh-build-context/*.pub; do \
        if [ -f "$pub" ]; then \
          cp "$pub" /opt/dockypody/ssh/ && \
          echo "SSH public key installed"; \
        fi; \
      done; \
      if [ -f /tmp/ssh-build-context/ssh.json ]; then \
        cp /tmp/ssh-build-context/ssh.json /opt/dockypody/ssh/ssh.json && \
        chmod 0644 /opt/dockypody/ssh/ssh.json; \
      else \
        echo "Warning: ssh.json not found in build context; ssh key_name defaults apply" >&2; \
      fi; \
      if [ "$SSH_MODE" = "client-and-server" ]; then \
        for src in /tmp/ssh-build-context/*; do \
          if [ ! -f "$src" ]; then continue; fi; \
          base="$(basename "$src")"; \
          case "$base" in \
            *.pub|ssh.json|known_hosts) \
              ;; \
            *) \
              cp "$src" "/opt/dockypody/ssh/$base" && \
              chmod 0640 "/opt/dockypody/ssh/$base"; \
              ;; \
          esac; \
        done; \
      fi; \
    else \
      echo "SSH disabled or not in server/client-and-server mode, skipping SSH install"; \
    fi && \
    rm -rf /tmp/ssh-build-context || true

ENV OCM_SSH_ENABLED="${SSH_ENABLED}" \
    OCM_SSH_MODE="${SSH_MODE}" \
    OCM_SSH_DEFAULT_USER="${SSH_DEFAULT_USER}" \
    OCM_SSH_PORT="${SSH_PORT}" \
    OCM_SSH_LISTEN="${SSH_LISTEN}"
```

### SSH Context Staging

The build system stages SSH material from `ssh/` into the build context
automatically. Dockerfiles should consume the staged `./ssh/` directory (for
example by copying it into a temporary path like `/tmp/ssh-build-context/`) and
then copy only the needed files into their final locations. Do not hardcode
paths to repo-root SSH material or assume it is always present.

- `ssh/<key_name>` -> staged to build context only for client modes
- `ssh/<key_name>.pub` -> staged to build context
- `ssh/ssh.json` -> staged if present
- `ssh/known_hosts` -> staged if present

## Verification Checklist

- [ ] ARGs declared in the Dockerfile match the service config build args.
- [ ] Local-source branch uses a bind mount and copies from `/tmp/local-*`.
- [ ] Git branch uses the cache mount with `CACHEBUST`.
- [ ] Package manager caches cleaned.
- [ ] Multi-stage boundaries enforced (no stray build tools in runtime image).
- [ ] `COPY` instructions reference files produced in previous stages, not host paths.
- [ ] Optional TLS helper scripts (`./scripts/tls/copy-tls.nu`) only copied when TLS is enabled.
- [ ] If `tls.enabled=true`, the service declares a direct `common-tools`
      dependency for the platform being built (transitive deps do not satisfy TLS
      validation).
- [ ] tini is copied from common-tools, not installed per-service.
- [ ] Package lists are alphabetically sorted.
- [ ] ENTRYPOINT uses JSON form with tini as PID 1.
- [ ] SSH args (`SSH_ENABLED`, `SSH_MODE`, etc.) declared when service has `ssh.enabled=true`.
- [ ] SSH packages (`openssh-client` or `openssh-server`) installed per-service, not in common-tools.

## References

- `docs/source-build-args.md` - generated build args and naming conventions
- `docs/guides/service-setup.md` - step-by-step Dockerfile scaffolding
- `docs/concepts/build-system.md` - cache busting, arg priority, and CI restrictions
- `docs/guides/nushell-development.md` - accompanying rules for Nushell scripts used by the build system
