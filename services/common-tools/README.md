# common-tools

Shared runtime asset provider for DockyPody services.

## What It Provides

| Asset | Path | Description |
| --- | --- | --- |
| Nushell | `/usr/local/bin/nu` | Static musl binary, UPX-compressed |
| UPX | `/usr/local/bin/upx` | Executable compressor |
| tini-static | `/usr/bin/tini-static` | Static init system (PID 1) |
| CA bundle | `/etc/ssl/certs/ca-certificates.crt` | Internal CA + public CAs |

## Platform Variants

- `common-tools:v1.0.0-debian` - Debian Trixie Slim base
- `common-tools:v1.0.0-alpine` - Alpine 3.22 base
- `common-tools:v1.0.0-rhel` - Red Hat UBI 9 Minimal base

## Usage Pattern: COPY, Don't Install

Instead of installing packages per-service, COPY from common-tools:

```dockerfile
# Copy Nushell
COPY --chmod=755 --from=common-tools /usr/local/bin/nu /usr/local/bin/nu

# Copy tini-static init system
COPY --chmod=755 --from=common-tools /usr/bin/tini-static /usr/bin/tini

# Copy CA bundle for TLS
COPY --from=common-tools /etc/ssl/certs/ca-certificates.crt /tmp/ca-bundle.crt
```
