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

# Enable Contacts app after fresh Nextcloud installation

use /usr/bin/lib/utils.nu [run_as]

def main [] {
  print "Enabling Contacts app..."

  let app_dir = "/var/www/html/apps/contacts"

  if not ($app_dir | path exists) {
    print "Warning: Contacts app directory not found, skipping enablement"
    return
  }

  let uid = (^id -u | into int)
  let user = if $uid == 0 {
    ($env.APACHE_RUN_USER? | default "www-data") | str replace --regex "^#" ""
  } else {
    ($uid | into string)
  }

  let result = (run_as $user "php /var/www/html/occ app:enable contacts" | complete)

  if $result.exit_code == 0 {
    print "Contacts app enabled successfully"
  } else {
    if ($result.stdout | str contains "already enabled") or ($result.stderr | str contains "already enabled") {
      print "Contacts app is already enabled"
    } else {
      print $"Warning: occ app:enable returned exit code ($result.exit_code)"
      print $result.stdout
      print $result.stderr
    }
  }
}
