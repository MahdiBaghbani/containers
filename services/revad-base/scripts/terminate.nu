#!/usr/bin/env nu

# SPDX-License-Identifier: AGPL-3.0-or-later
# Open Cloud Mesh Containers: container build scripts and images
# Copyright (C) 2025 Open Cloud Mesh Contributors
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

# Terminate running Reva daemon process
# Finds all revad processes and terminates the last one (most recent)
# Uses SIGKILL (-9) to force immediate termination
def terminate_revad [] {
  let pids = ( ^pgrep -f "revad" | complete | get stdout | lines )
  if ($pids | is-empty) {
    print "No running revad process found."
    return
  }
  let pid = ($pids | last)
  print $"Terminating revad process with PID ($pid)..."
  ^kill -9 $pid | ignore
  print $"Successfully terminated revad process with PID ($pid)."
}

# Main function - entry point for terminate script
def main [] { terminate_revad }
