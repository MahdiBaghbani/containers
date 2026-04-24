#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# DockyPody: container build scripts and images
# Copyright (C) 2025 Mahdi Baghbani <mahdi-baghbani@azadehafzar.io>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Run initialization via Nushell script
# This performs all container setup tasks before starting the main process
# Don't use set -e here; the Nushell orchestrator decides which paths are fatal.
# Warnings are handled inside the orchestrator and must exit 0.
if [ -f /usr/bin/entrypoint-init.nu ]; then
  if command -v nu >/dev/null 2>&1; then
    nu /usr/bin/entrypoint-init.nu "$@" || {
      status=$?
      echo "Error: Initialization script failed with exit code ${status}; refusing to run CMD." >&2
      exit "$status"
    }
  else
    echo "Error: nu not found; cannot run /usr/bin/entrypoint-init.nu." >&2
    exit 1
  fi
else
  echo "Error: /usr/bin/entrypoint-init.nu not found; refusing to run CMD." >&2
  exit 1
fi

# Exec the CMD arguments directly
# Nushell has limited ability to parse complex command-line arguments,
# so we use exec to pass them through to the actual command unchanged
exec "$@"
