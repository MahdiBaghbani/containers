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
