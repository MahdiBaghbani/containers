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

## Common Mistakes to Avoid

- **Copying from `${FOO_PATH}` without a mount**: breaks every local-source build. Always mount then copy from the mounted path.
- **Implicit ARG usage**: referencing `FOO_REF` without `ARG FOO_REF` declares it globally and makes the Dockerfile unusable in isolation.
- **Installing git inside runtime stages**: keep tooling in the build stage; runtime images should contain only the shipped binaries.
- **Not using `set -euo pipefail` equivalents**: when writing long `RUN` scripts, prefer `bash -eu -o pipefail -c '...'` to surface failures early.
- **Leaving cache mounts on unrelated layers**: only the Git clone step should mount the Git cache; other commands should stay deterministic.
- **Mixing `cp` semantics**: use `cp -a /src/. /dest` to preserve permissions; `cp -r ${PATH}*` drops dotfiles.

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
