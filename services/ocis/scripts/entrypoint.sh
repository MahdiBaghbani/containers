#!/bin/sh
set -eu

if ! nu /usr/local/bin/entrypoint-init.nu; then
  echo "WARNING: [entrypoint-init] failed, continuing"
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
