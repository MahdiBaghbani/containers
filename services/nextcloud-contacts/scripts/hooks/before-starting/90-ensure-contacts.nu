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

# Ensure Contacts app is enabled on every container start (idempotent)

use /usr/bin/lib/utils.nu [run_as]

def main [] {
  let app_dir = "/var/www/html/apps/contacts"

  if not ($app_dir | path exists) {
    return
  }

  if not ("/var/www/html/config/config.php" | path exists) {
    return
  }

  let uid = (^id -u | into int)
  let user = if $uid == 0 {
    ($env.APACHE_RUN_USER? | default "www-data") | str replace --regex "^#" ""
  } else {
    ($uid | into string)
  }

  let check_result = (run_as $user "php /var/www/html/occ app:list" | complete)

  if ($check_result.stdout | str contains "- contacts:") {
    return
  }

  print "Contacts app not enabled, enabling..."
  run_as $user "php /var/www/html/occ app:enable contacts" | ignore
}

main
