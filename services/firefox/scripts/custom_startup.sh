#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:1}"
exec /usr/local/bin/nu /dockerstartup/firefox-autostart.nu
