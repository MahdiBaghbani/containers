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

# Top-level-files-only contract:
# - Copies every file directly under core_dir into dest (no subdirectories).
# - When overlays_root/<band> exists, same-named overlay files replace core copies.
# - Bands in CORE_ONLY_BANDS may omit an overlay directory (core files only).
# - Any other band without an overlay directory is a configuration error.

const CORE_ONLY_BANDS = ["v3.10.1"]

export def resolve_configs [
  core_dir: string
  overlays_root: string
  band: string
  dest: string
] {
  if not ($core_dir | path exists) {
    error make {msg: $"Core config directory not found: ($core_dir)"}
  }

  if ($band | is-empty) {
    error make {msg: "Config overlay band must not be empty"}
  }

  ^mkdir -p $dest

  let core_files = (try {
    ls $core_dir | where type == file | get name
  } catch {
    []
  })

  for file in $core_files {
    let filename = ($file | path basename)
    ^cp $file $"($dest)/($filename)"
  }

  let overlay_dir = $"($overlays_root)/($band)"
  if not ($overlay_dir | path exists) {
    if $band in $CORE_ONLY_BANDS {
      return
    }
    error make {
      msg: $"Unknown or missing config overlay band: ($band). Expected overlays at ($overlay_dir) or a core-only band: ($CORE_ONLY_BANDS | str join ', ')"
    }
  }

  let overlay_files = (try {
    ls $overlay_dir | where type == file | get name
  } catch {
    []
  })

  for file in $overlay_files {
    let filename = ($file | path basename)
    ^cp $file $"($dest)/($filename)"
  }
}
