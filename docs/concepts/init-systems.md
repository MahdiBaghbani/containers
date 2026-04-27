# Init Systems in DockyPody Containers

## The PID 1 Problem

In Linux, the process with PID 1 has special responsibilities:

1. **Signal handling**: The kernel does not apply default signal handlers to PID 1. If the process does not explicitly handle SIGTERM, the signal is silently dropped.
2. **Zombie reaping**: When a child process exits before its parent, it becomes a "zombie." The parent must call `waitpid()` to reap it. If the parent is PID 1 and does not reap, zombies accumulate.

Most applications are not designed to be PID 1 citizens. They do not register signal handlers or reap children.

## Docker's Solution: tini

Docker ships tini as `docker-init` and provides the `--init` flag:

```bash
docker run --init my-image
```

In Docker Compose:

```yaml
services:
  app:
    image: my-image
    init: true
```

## Kubernetes: No Built-in Init

Kubernetes does NOT have an `init: true` equivalent. For Kubernetes deployments, tini MUST be embedded in the container image.

## DockyPody Standard

All non-distroless DockyPody containers embed tini-static copied from a stage
based on the common-tools image:

```dockerfile
COPY --chmod=755 --from=common-tools /usr/bin/tini-static /usr/bin/tini
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/bin/entrypoint.sh"]
```

The exact stage name does not matter as long as it is built from
`COMMON_TOOLS_IMAGE` (common aliases: `common-tools`, `common-tools-runtime`,
`compress`).

### Why tini-static?

- Fully statically linked (zero dependencies)
- Works on Debian, Alpine, RHEL, and even scratch/distroless
- Only ~20-59 KiB
- Same flags as dynamic tini (`-g`, `--`, etc.)

### Why Not dumb-init?

dumb-init was an early alternative but is larger and not Docker-standard. DockyPody standardizes on tini.

## Graceful Shutdown

With tini as PID 1:

1. `docker stop` sends SIGTERM to tini
2. tini forwards SIGTERM to the main process (via `entrypoint.sh` -> `exec "$@"`)
3. The main process has a grace period to shut down
4. If the process does not exit, tini sends SIGKILL

Without tini:

1. `docker stop` sends SIGTERM to the application (PID 1)
2. If the application does not handle SIGTERM, the signal is dropped
3. Docker waits, then force-kills with SIGKILL
4. The application has no chance for graceful shutdown

## References

- Docker documentation on `--init`
- Kubernetes issue #84210 (no built-in init)
- tini GitHub repository: [krallin/tini](https://github.com/krallin/tini)
