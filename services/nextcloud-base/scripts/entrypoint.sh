#!/usr/bin/env sh
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
# Don't use set -e here - we want to continue even if initialization has warnings
# Pass command arguments so initialization can check if we're running apache/php-fpm
nu /usr/bin/entrypoint-init.nu "$@" || {
  echo "Warning: Initialization script exited with error, but continuing to run CMD..."
}

# Exec the CMD arguments directly
# Nushell has limited ability to parse complex command-line arguments,
# so we use exec to pass them through to the actual command unchanged
exec "$@"
