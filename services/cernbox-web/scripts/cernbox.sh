#!/usr/bin/env sh

# Required environment variables
if [ -z "${CERNBOX_WEB_HOSTNAME}" ]; then
  echo "Error: CERNBOX_WEB_HOSTNAME is required" >&2
  exit 1
fi

# Shared environment contract: Derive REVA_* vars from REVA_TLS_ENABLED
# REVA_TLS_ENABLED comes from the backend (cernbox-reva), web follows backend
REVA_TLS_ENABLED="${REVA_TLS_ENABLED:-${TLS_ENABLED:-true}}"

if [ "${REVA_TLS_ENABLED}" = "false" ]; then
  REVA_PROTOCOL="${REVA_PROTOCOL:-http}"
  REVA_PORT="${REVA_PORT:-80}"
else
  REVA_PROTOCOL="${REVA_PROTOCOL:-https}"
  REVA_PORT="${REVA_PORT:-443}"
fi

# REVA_HOST can be overridden, defaults to CERNBOX_WEB_HOSTNAME
# Usually, should be different from CERNBOX_WEB_HOSTNAME.
REVA_HOST="${REVA_HOST:-${CERNBOX_WEB_HOSTNAME}}"

# Ensure all REVA_* vars are set after derivation
if [ -z "${REVA_PROTOCOL}" ] || [ -z "${REVA_PORT}" ] || [ -z "${REVA_HOST}" ]; then
  echo "Error: Failed to derive REVA_PROTOCOL, REVA_PORT, or REVA_HOST" >&2
  echo "  REVA_PROTOCOL=${REVA_PROTOCOL}" >&2
  echo "  REVA_PORT=${REVA_PORT}" >&2
  echo "  REVA_HOST=${REVA_HOST}" >&2
  exit 1
fi

# Export for nginx envsubst processing
export REVA_PROTOCOL
export REVA_PORT
export REVA_HOST
export CERNBOX="${CERNBOX_WEB_HOSTNAME}"
export IDP_URL="${IDP_URL:-https://${IDP_DOMAIN:-idp.docker}}"
export TLS_CRT="${TLS_CRT:-/tls/server.crt}"
export TLS_KEY="${TLS_KEY:-/tls/server.key}"

# Frontend TLS: allow independent control from backend
WEB_TLS_ENABLED="${WEB_TLS_ENABLED:-${REVA_TLS_ENABLED}}"

# Copy appropriate template based on FRONTEND TLS mode
TEMPLATES_DIR="/etc/nginx/templates-available"
NGINX_TEMPLATE_DIR="/etc/nginx/templates"
NGINX_CONF="/etc/nginx/conf.d/cernbox.conf"

if [ "${WEB_TLS_ENABLED}" = "false" ]; then
  # HTTP mode: Use HTTP template
  cp "${TEMPLATES_DIR}/cernbox-http.conf.template" "${NGINX_TEMPLATE_DIR}/cernbox.conf.template"
else
  # HTTPS mode: Use HTTPS template
  cp "${TEMPLATES_DIR}/cernbox-https.conf.template" "${NGINX_TEMPLATE_DIR}/cernbox.conf.template"
fi

# Process template with envsubst
# @MahdiBaghbani: nginx will automatically process files in /etc/nginx/templates/*.template
# But we do it manually here to have control over the process.
envsubst < "${NGINX_TEMPLATE_DIR}/cernbox.conf.template" > "$NGINX_CONF"

# Update config.json
file_path="/var/www/web/config.json"
web_original="your.nginx.org"
web_replacement="${CERNBOX_WEB_HOSTNAME}"
idp_original="your-idp.org:your-idp-port"
idp_replacement="${CERNBOX_IDP_HOSTNAME:-idp.docker}:${CERNBOX_IDP_PORT:-443}"

sed -i "s#${web_original}#${web_replacement}#g" "${file_path}"
sed -i "s#${idp_original}#${idp_replacement}#g" "${file_path}"

# Runtime replacement for mesh directory endpoint in built JS
MESHDIR_ORIGINAL="sciencemesh.cesnet.cz/iop"
MESHDIR_REPLACEMENT="${MESHDIR_DOMAIN:-meshdir.docker}"
find /var/www/web -name "web-app-science*.mjs" -type f -exec sed -i "s|${MESHDIR_ORIGINAL}|${MESHDIR_REPLACEMENT}|g" {} \; || true
