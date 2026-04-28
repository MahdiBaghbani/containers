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

if [ -n "${DOCKYPODY_TLS_CERT_NAME:-}" ]; then
  cert="/tls/${DOCKYPODY_TLS_CERT_NAME}.crt"
  key="/tls/${DOCKYPODY_TLS_CERT_NAME}.key"

  if [ -z "${PROXY_TRANSPORT_TLS_CERT:-}" ] && [ -f "$cert" ]; then
    export PROXY_TRANSPORT_TLS_CERT="$cert"
  fi
  if [ -z "${PROXY_TRANSPORT_TLS_KEY:-}" ] && [ -f "$key" ]; then
    export PROXY_TRANSPORT_TLS_KEY="$key"
  fi
fi

if [ "${OCM_RUN_AS_ROOT:-false}" = "true" ]; then
  exec "$@"
fi

cmd="$(basename "${1:-}")"
subcmd="${2:-}"

if [ "$cmd" = "ocis" ] && { [ "$subcmd" = "server" ] || [ "$subcmd" = "init" ]; }; then
  exec su-exec 1000:1000 "$@"
fi

exec "$@"
