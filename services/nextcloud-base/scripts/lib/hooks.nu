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

# Nextcloud hook execution system

use ./utils.nu [run_as directory_empty]

# Execute all scripts in /docker-entrypoint-hooks.d/{hook_name}/
# Supports hooks: pre-installation, post-installation, pre-upgrade, post-upgrade, before-starting
# Supports both .sh (shell) and .nu (nushell) scripts
export def run_path [hook_name: string, user: string] {
  let hook_folder = $"/docker-entrypoint-hooks.d/($hook_name)"

  print $"=> Searching for hook scripts \(*.sh, *.nu\) to run, located in the folder \"($hook_folder)\""

  # Check if hook folder exists and is not empty
  if not ($hook_folder | path exists) {
    print $"==> Skipped: the \"($hook_name)\" folder does not exist"
    return
  }

  if (directory_empty $hook_folder) {
    print $"==> Skipped: the \"($hook_name)\" folder is empty"
    return
  }

  # Find all .sh and .nu scripts in hook folder
  let scripts = (ls $hook_folder
    | where type == file
    | where {|f| ($f.name | str ends-with ".sh") or ($f.name | str ends-with ".nu")}
    | sort-by name)

  if ($scripts | length) == 0 {
    print $"==> Skipped: the \"($hook_name)\" folder does not contain any valid scripts"
    return
  }

  mut found = 0

  # Execute each script
  for script in $scripts {
    let script_path = $script.name

    # Check if script is executable
    let is_executable = (^test -x $script_path | complete | get exit_code) == 0

    if not $is_executable {
      print $"==> The script \"($script_path)\" was skipped, because it lacks the executable flag"
      continue
    }

    print $"==> Running the script \(cwd: (pwd)\): \"($script_path)\""
    $found = ($found + 1)

    # Run script based on extension
    let result = if ($script_path | str ends-with ".nu") {
      # Nushell script - run directly with nu
      ^nu $script_path | complete
    } else {
      # Shell script - run as appropriate user
      run_as $user $script_path | complete
    }

    if $result.exit_code != 0 {
      print $"==> Failed at executing script \"($script_path)\". Exit code: ($result.exit_code)"
      print $result.stderr
      exit 1
    }

    print $"==> Finished executing the script: \"($script_path)\""
  }

  if $found > 0 {
    print $"=> Completed executing scripts in the \"($hook_name)\" folder"
  }
}
