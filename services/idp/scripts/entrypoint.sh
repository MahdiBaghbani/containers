#!/bin/bash
set -euo pipefail

if [ -f /usr/bin/entrypoint-init.nu ]; then
    if command -v nu >/dev/null 2>&1; then
        nu /usr/bin/entrypoint-init.nu "$@" || {
            echo "WARNING: entrypoint-init.nu failed, continuing anyway" >&2
        }
    else
        echo "WARNING: nu not found; skipping /usr/bin/entrypoint-init.nu" >&2
    fi
else
    echo "WARNING: /usr/bin/entrypoint-init.nu not found; skipping init" >&2
fi

exec /opt/keycloak/bin/kc.sh "$@"
