#!/usr/bin/env nu

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

# Log tailing utilities for Nextcloud containers
# Starts background tail processes for Apache and Nextcloud logs

# Start log tailing processes in background
# Tails Apache access, Apache error, and Nextcloud application logs
export def start_log_tailing [] {
  let apache_access_log = "/var/log/apache2/access.log"
  let apache_error_log = "/var/log/apache2/error.log"
  let nextcloud_log = "/var/www/html/data/nextcloud.log"

  # Safeguard: Ensure log directories exist
  let apache_log_dir = "/var/log/apache2"
  let nextcloud_data_dir = "/var/www/html/data"

  if not ($apache_log_dir | path exists) {
    print $"Warning: Apache log directory ($apache_log_dir) does not exist, creating it..."
    ^mkdir -p $apache_log_dir
  }

  if not ($nextcloud_data_dir | path exists) {
    print $"Warning: Nextcloud data directory ($nextcloud_data_dir) does not exist, creating it..."
    ^mkdir -p $nextcloud_data_dir
  }

  # Safeguard: Ensure log files exist (backup safety)
  for log_file in [$apache_access_log, $apache_error_log, $nextcloud_log] {
    if not ($log_file | path exists) {
      print $"Warning: Log file ($log_file) does not exist, creating it..."
      ^touch $log_file
      # Set full permissions to match setup_log_files (www-data:root with g=u)
      ^chown www-data:root $log_file
      ^chmod g=u $log_file
    }
  }

  print "Starting log tailing processes..."

  # Start tail processes in background (using -F for retry on missing files)
  # Output is redirected to /proc/1/fd/1 (container stdout) so logs appear in docker logs
  # stderr is redirected to /dev/null to prevent blocking the parent process
  # Processes will reparent to PID 1 when Nushell exits
  ^sh -c $"tail -F ($apache_access_log) > /proc/1/fd/1 2>/dev/null &" | ignore
  ^sh -c $"tail -F ($apache_error_log) > /proc/1/fd/1 2>/dev/null &" | ignore
  ^sh -c $"tail -F ($nextcloud_log) > /proc/1/fd/1 2>/dev/null &" | ignore

  # Wait a moment for processes to start
  sleep 0.5sec

  # Verify processes started (verify but don't fail)
  mut all_started = true
  for log_file in [$apache_access_log, $apache_error_log, $nextcloud_log] {
    # Escape regex metacharacters in log file path for pgrep (only . needs escaping)
    let escaped_path = ($log_file | str replace -a '.' '\.')
    let tail_pids = (^pgrep -f $"^tail -F ($escaped_path)" | complete)
    if ($tail_pids.exit_code == 0) and (($tail_pids.stdout | lines | length) > 0) {
      print $"  [OK] Tail process started for ($log_file)"
    } else {
      print $"  [WARN] Tail process may not have started for ($log_file)"
      $all_started = false
    }
  }

  if $all_started {
    print "Log tailing processes started successfully"
  } else {
    print "Warning: Some log tailing processes may not have started (non-critical)"
  }
}
